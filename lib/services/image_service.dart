import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/slide.dart';

class ImageService {
  Future<String?> pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: 'Kies een afbeelding',
    );
    return result?.files.single.path;
  }

  Future<String?> pickVideo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.video,
      dialogTitle: 'Kies een video',
    );
    return result?.files.single.path;
  }

  Future<String?> pickAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      dialogTitle: 'Kies een audiobestand',
    );
    return result?.files.single.path;
  }

  /// Schrijf afbeeldings[bytes] naar het systeemklembord. Geeft false terug
  /// bij een fout. Gebruikt voor zowel bestanden als een gerasteriseerde slide.
  Future<bool> copyImageBytesToClipboard(Uint8List bytes) async {
    try {
      if (bytes.isEmpty) return false;
      await Pasteboard.writeImage(bytes);
      return true;
    } catch (_) {
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
    } catch (_) {
      return false;
    }
  }

  /// Read an image from the system clipboard and save it to a temp file.
  /// Returns the absolute path to the temp file, or null if no image is on
  /// the clipboard.
  Future<String?> pasteImage() async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null) return null;
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
    if (imagePath.isEmpty) return '';
    if (p.isAbsolute(imagePath)) return imagePath;
    if (projectPath != null) return p.join(projectPath, imagePath);
    return imagePath;
  }
}
