import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import '../models/slide.dart';
import '../utils/log.dart';
import '../utils/project_path.dart';

class ImageService {
  final String Function() _languageCode;

  ImageService({String Function()? languageCode})
    : _languageCode = languageCode ?? (() => 'nl');

  String _d(String text) => AppLocalizations.sourceFor(_languageCode(), text);

  /// Per-asset import caps. Images are validated by magic bytes (not just the
  /// picker's extension filter); video/audio are size-capped only.
  static const maxImageBytes = 64 * 1024 * 1024; // 64 MiB
  static const maxMediaBytes = 1024 * 1024 * 1024; // 1 GiB

  /// True when [path] is within the size cap and its leading bytes match a
  /// known raster image signature (PNG/JPEG/GIF/BMP/WebP).
  Future<bool> _isAcceptableImageFile(String path) async {
    try {
      final file = File(path);
      final len = await file.length();
      if (len <= 0 || len > maxImageBytes) return false;
      final raf = await file.open();
      try {
        final head = await raf.read(16);
        return _looksLikeImage(head);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Whether [b] (a file's leading bytes) matches a known raster image
  /// signature. Public for the import validation and its tests.
  static bool looksLikeImage(List<int> b) => _looksLikeImage(b);

  static bool _looksLikeImage(List<int> b) {
    if (b.length < 4) return false;
    // PNG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true;
    }
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true; // JPEG
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
    if (b[0] == 0x42 && b[1] == 0x4D) return true; // BMP
    // WebP: "RIFF"...."WEBP"
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return true;
    }
    return false;
  }

  Future<bool> _isWithinMediaCap(String path) async {
    try {
      final len = await File(path).length();
      return len > 0 && len <= maxMediaBytes;
    } catch (_) {
      return false;
    }
  }

  Future<String?> pickImage({String? projectPath}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: _d('Kies een afbeelding'),
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    if (!await _isAcceptableImageFile(path)) {
      logWarning(
        'ImageService.pickImage: rejected (too large or not an image)',
      );
      return null;
    }
    return _importIntoProject(path, projectPath, subdir: 'images');
  }

  Future<String?> pickVideo({String? projectPath}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.video,
      dialogTitle: _d('Kies een video'),
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    if (!await _isWithinMediaCap(path)) {
      logWarning('ImageService.pickVideo: rejected (exceeds size cap)');
      return null;
    }
    return _importIntoProject(path, projectPath, subdir: 'media');
  }

  Future<String?> pickAudio({String? projectPath}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      dialogTitle: _d('Kies een audiobestand'),
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    if (!await _isWithinMediaCap(path)) {
      logWarning('ImageService.pickAudio: rejected (exceeds size cap)');
      return null;
    }
    return _importIntoProject(path, projectPath, subdir: 'media');
  }

  /// Schrijf afbeeldings[bytes] naar het systeemklembord. Geeft false terug
  /// bij een fout. Gebruikt voor zowel bestanden als een gerasteriseerde slide.
  Future<bool> copyImageBytesToClipboard(Uint8List bytes) async {
    try {
      if (bytes.isEmpty) return false;
      await Pasteboard.writeImage(bytes);
      return true;
    } catch (e) {
      logError('ImageService.copyImageBytesToClipboard: write image', e);
      return false;
    }
  }

  /// Kopieer de afbeelding op [path] naar het systeemklembord, zodat 'ie
  /// elders geplakt kan worden. Geeft false terug bij een fout/ontbrekend
  /// bestand. De ruwe bytes volstaan: het OS leest gangbare formaten zelf.
  Future<bool> copyImageToClipboard(String path) async {
    try {
      if (path.isEmpty) return false;
      final file = File(path);
      if (!await file.exists()) return false;
      return copyImageBytesToClipboard(await file.readAsBytes());
    } catch (e) {
      logWarning('ImageService.copyImageToClipboard: read image file', e);
      return false;
    }
  }

  /// Read an image from the system clipboard and save it to a temp file.
  /// Returns the absolute path to the temp file, or null if no image is on
  /// the clipboard.
  Future<String?> pasteImage({String? projectPath}) async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null) return null;
      if (bytes.isEmpty || bytes.length > maxImageBytes) return null;
      if (projectPath != null && projectPath.isNotEmpty) {
        final imagesDir = Directory(p.join(projectPath, 'images'));
        await imagesDir.create(recursive: true);
        final file = File(
          p.join(
            imagesDir.path,
            'pasted_${DateTime.now().millisecondsSinceEpoch}.png',
          ),
        );
        await file.writeAsBytes(bytes, flush: true);
        return p.relative(file.path, from: projectPath);
      }
      final cacheDir = await getTemporaryDirectory();
      final dir = Directory(p.join(cacheDir.path, 'pasted_images'));
      await dir.create(recursive: true);
      final file = File(
        p.join(dir.path, 'pasted_${DateTime.now().millisecondsSinceEpoch}.png'),
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _importIntoProject(
    String sourcePath,
    String? projectPath, {
    required String subdir,
  }) async {
    if (projectPath == null || projectPath.isEmpty) return sourcePath;
    final destDir = Directory(p.join(projectPath, subdir));
    await destDir.create(recursive: true);
    final normalized = p.normalize(sourcePath);
    if (p.isWithin(projectPath, normalized)) {
      return p.relative(normalized, from: projectPath);
    }
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    final filename = p.basename(sourcePath);
    final dest = File(p.join(destDir.path, filename));
    if (!await dest.exists()) {
      await src.copy(dest.path);
    }
    return '$subdir/$filename';
  }

  /// Copy images referenced by absolute path into the project images/ dir
  /// and return updated slides with relative paths.
  Future<List<Slide>> copyImagesToProject(
    List<Slide> slides,
    String projectPath,
  ) async {
    final imagesDir = Directory(p.join(projectPath, 'images'));
    await imagesDir.create(recursive: true);

    final updated = <Slide>[];
    for (final slide in slides) {
      var next = slide;
      final copiedImage = await _copyImageToProject(next.imagePath, imagesDir);
      if (copiedImage != null) next = next.copyWith(imagePath: copiedImage);
      final copiedImage2 = await _copyImageToProject(
        next.imagePath2,
        imagesDir,
      );
      if (copiedImage2 != null) next = next.copyWith(imagePath2: copiedImage2);
      updated.add(next);
    }
    return updated;
  }

  Future<List<Slide>> copyMediaToProject(
    List<Slide> slides,
    String projectPath,
  ) async {
    final mediaDir = Directory(p.join(projectPath, 'media'));
    await mediaDir.create(recursive: true);

    final updated = <Slide>[];
    for (final slide in slides) {
      var next = slide;
      if (_shouldCopy(next.videoPath)) {
        final copied = await _copyToDir(next.videoPath, mediaDir);
        if (copied != null) next = next.copyWith(videoPath: copied);
      }
      if (_shouldCopy(next.audioPath)) {
        final copied = await _copyToDir(next.audioPath, mediaDir);
        if (copied != null) next = next.copyWith(audioPath: copied);
      }
      updated.add(next);
    }
    return updated;
  }

  bool _shouldCopy(String path) {
    return path.isNotEmpty &&
        !path.startsWith('media/') &&
        !path.startsWith('images/') &&
        p.isAbsolute(path);
  }

  Future<String?> _copyToDir(String sourcePath, Directory destDir) async {
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    final filename = p.basename(sourcePath);
    final dest = File(p.join(destDir.path, filename));
    if (!await dest.exists()) {
      await src.copy(dest.path);
    }
    return 'media/$filename';
  }

  Future<String?> _copyImageToProject(
    String sourcePath,
    Directory imagesDir,
  ) async {
    if (sourcePath.isEmpty ||
        sourcePath.startsWith('images/') ||
        !p.isAbsolute(sourcePath)) {
      return null;
    }
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    final filename = p.basename(sourcePath);
    final dest = File(p.join(imagesDir.path, filename));
    if (!await dest.exists()) {
      await src.copy(dest.path);
    }
    return 'images/$filename';
  }

  /// Resolve a slide image path to an absolute path for display.
  String resolve(String imagePath, String? projectPath) {
    return resolveEditorAssetPath(imagePath, projectPath) ?? '';
  }
}
