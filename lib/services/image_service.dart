import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import '../models/slide.dart';
import '../utils/asset_destination.dart';
import '../utils/atomic_file.dart';
import '../utils/log.dart';
import '../utils/project_path.dart';
import 'asset_staging.dart';
import 'web_asset_store.dart';

/// Waarom een afbeelding kiezen/plakken géén pad opleverde. [cancelled] is een
/// bewuste keuze van de gebruiker (geen melding tonen); de overige redenen
/// verdienen uitleg in de UI in plaats van een stil mislukken.
enum ImageImportFailure { cancelled, rejected, noClipboardImage, writeFailed }

/// Uitkomst van een afbeelding kiezen/plakken: een [path] bij succes, anders
/// een [failure] met de reden.
class ImageImportOutcome {
  final String? path;
  final ImageImportFailure? failure;

  const ImageImportOutcome.success(this.path) : failure = null;
  const ImageImportOutcome.failed(this.failure) : path = null;
}

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
    } catch (e) {
      logWarning('ImageService: image signature probe failed', e);
      return false;
    }
  }

  /// Whether [b] (a file's leading bytes) matches a known raster image
  /// signature. Public for the import validation and its tests.
  static bool looksLikeImage(List<int> b) => _looksLikeImage(b);

  static bool _looksLikeImage(List<int> b) => imageMimeFromBytes(b) != null;

  /// The MIME type behind [b]'s raster image signature, or null when the bytes
  /// match none of them. The signature set is the single source of truth for
  /// [looksLikeImage]; callers that must *name* the type (the style-profile
  /// export embeds a logo as `data:<mime>;base64,…`) sniff it here rather than
  /// trusting a file extension or a declared type from an outside file.
  static String? imageMimeFromBytes(List<int> b) {
    if (b.length < 4) return null;
    // PNG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'image/png';
    }
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
    if (b[0] == 0x42 && b[1] == 0x4D) return 'image/bmp';
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
      return 'image/webp';
    }
    return null;
  }

  /// The file extension for a MIME type from [imageMimeFromBytes]. Falls back
  /// to `png` so a materialized file always carries a usable extension.
  static String extensionForImageMime(String mime) => switch (mime) {
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/bmp' => 'bmp',
    'image/webp' => 'webp',
    _ => 'png',
  };

  Future<bool> _isWithinMediaCap(String path) async {
    try {
      final len = await File(path).length();
      return len > 0 && len <= maxMediaBytes;
    } catch (e) {
      logWarning('ImageService: media size check failed', e);
      return false;
    }
  }

  Future<String?> pickImage({String? projectPath}) async =>
      (await pickImageDetailed(projectPath: projectPath)).path;

  /// Als [pickImage], maar met de reden waarom er geen pad kwam, zodat de UI
  /// een afwijzing kan uitleggen i.p.v. stil niets te doen.
  Future<ImageImportOutcome> pickImageDetailed({String? projectPath}) async {
    // Web: de browser-picker levert bytes (geen pad); na dezelfde validatie
    // als hieronder gaat de afbeelding de in-memory store in en krijgt de
    // slide een mem:-pad (zie WebAssetStore).
    if (kIsWeb) {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: _d('Kies een afbeelding'),
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) {
        return const ImageImportOutcome.failed(ImageImportFailure.cancelled);
      }
      if (bytes.isEmpty ||
          bytes.length > maxImageBytes ||
          !_looksLikeImage(bytes)) {
        logWarning(
          'ImageService.pickImage: rejected (too large or not an image)',
        );
        return const ImageImportOutcome.failed(ImageImportFailure.rejected);
      }
      return ImageImportOutcome.success(
        WebAssetStore.put(bytes, name: file.name),
      );
    }
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: _d('Kies een afbeelding'),
    );
    final path = result?.files.single.path;
    if (path == null) {
      return const ImageImportOutcome.failed(ImageImportFailure.cancelled);
    }
    if (!await _isAcceptableImageFile(path)) {
      logWarning(
        'ImageService.pickImage: rejected (too large or not an image)',
      );
      return const ImageImportOutcome.failed(ImageImportFailure.rejected);
    }
    final imported = await _importIntoProject(
      path,
      projectPath,
      subdir: 'images',
    );
    if (imported == null) {
      return const ImageImportOutcome.failed(ImageImportFailure.writeFailed);
    }
    return ImageImportOutcome.success(imported);
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

  /// Read the encoded bytes of a slide image [path] resolved against
  /// [projectPath], for the AI vision call (AI_ASSIST §6.3). Honours project
  /// containment (via [resolveSlideAssetPath]); on web only `mem:` paths resolve
  /// (through [WebAssetStore]). Returns null for an out-of-project path, a `mem:`
  /// miss, or a read error — never throws.
  Future<Uint8List?> readSlideImageBytes(
    String path, {
    String? projectPath,
  }) async {
    if (path.isEmpty) return null;
    if (kIsWeb) {
      return WebAssetStore.isMemPath(path)
          ? WebAssetStore.bytesFor(path)
          : null;
    }
    final resolved = resolveSlideAssetPath(path, projectPath);
    if (resolved == null) return null;
    try {
      return await File(resolved).readAsBytes();
    } catch (e, s) {
      logError('ImageService.readSlideImageBytes', e, s);
      return null;
    }
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
  Future<String?> pasteImage({String? projectPath}) async =>
      (await pasteImageDetailed(projectPath: projectPath)).path;

  /// Als [pasteImage], maar met de reden waarom er geen pad kwam (leeg
  /// klembord, te groot, schrijffout), zodat de UI die kan melden.
  Future<ImageImportOutcome> pasteImageDetailed({String? projectPath}) async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) {
        return const ImageImportOutcome.failed(
          ImageImportFailure.noClipboardImage,
        );
      }
      if (bytes.length > maxImageBytes) {
        logWarning('ImageService.pasteImage: rejected (too large)');
        return const ImageImportOutcome.failed(ImageImportFailure.rejected);
      }
      // Web: geen tijdelijke bestanden — de geplakte afbeelding gaat de
      // in-memory store in, net als bij pickImage.
      if (kIsWeb) {
        if (!_looksLikeImage(bytes)) {
          return const ImageImportOutcome.failed(ImageImportFailure.rejected);
        }
        return ImageImportOutcome.success(
          WebAssetStore.put(bytes, name: 'geplakt.png'),
        );
      }
      if (projectPath != null && projectPath.isNotEmpty) {
        final imagesDir = Directory(p.join(projectPath, 'images'));
        await imagesDir.create(recursive: true);
        final file = File(
          p.join(
            imagesDir.path,
            'pasted_${DateTime.now().millisecondsSinceEpoch}.png',
          ),
        );
        await writeBytesAtomic(file, bytes);
        return ImageImportOutcome.success(
          p.relative(file.path, from: projectPath),
        );
      }
      // Geen projectmap: de stagingmap, met dezelfde images/-indeling, zodat
      // een geplakte afbeelding bij de eerste opslag meeverhuist net als elke
      // andere — en tot die tijd als "nog niet opgeslagen" herkenbaar is.
      final name = 'pasted_${DateTime.now().millisecondsSinceEpoch}.png';
      final staged = await AssetStaging.stageBytes(
        bytes,
        subdir: 'images',
        filename: name,
      );
      if (staged == null) {
        return const ImageImportOutcome.failed(ImageImportFailure.writeFailed);
      }
      return ImageImportOutcome.success(staged);
    } on FileSystemException catch (e) {
      logWarning('ImageService.pasteImage: write failed', e);
      return const ImageImportOutcome.failed(ImageImportFailure.writeFailed);
    }
  }

  /// Neem een bestand op dat de gebruiker al heeft aangewezen — gesleept op de
  /// app, of gekozen uit de afbeeldingenbibliotheek — in plaats van er alleen
  /// naar te verwijzen.
  ///
  /// Zonder deze stap zou de presentatie afhangen van een bestand op een plek
  /// die alleen deze gebruiker heeft; wie het deck doorstuurt, stuurt een gat
  /// mee. Geeft de verwijzing terug die de slide moet vasthouden:
  /// projectrelatief bij een opgeslagen deck, anders een pad in de stagingmap.
  ///
  /// Lukt het kopiëren niet, dan komt het bronpad terug in plaats van null: een
  /// zichtbare afbeelding met een waarschuwingsbadge is bruikbaarder dan een
  /// slide die stil leeg blijft, en de badge vertelt de gebruiker precies wat
  /// er nog buiten de presentatie ligt.
  Future<String> importIntoDeck(
    String sourcePath, {
    String? projectPath,
    String subdir = 'images',
  }) async =>
      await _importIntoProject(sourcePath, projectPath, subdir: subdir) ??
      sourcePath;

  /// Of [path] binnen de importlimiet valt en werkelijk een rasterafbeelding
  /// is. De extensie zegt niets — een hernoemd script heet net zo makkelijk
  /// `.png`.
  Future<bool> isAcceptableImageFile(String path) =>
      _isAcceptableImageFile(path);

  Future<String?> _importIntoProject(
    String sourcePath,
    String? projectPath, {
    required String subdir,
  }) async {
    // Nog geen map op schijf: niet het bronpad onthouden (dat breekt zodra
    // iemand het bestand verplaatst), maar kopiëren naar de stagingmap, die
    // dezelfde indeling heeft als een echt project. Lukt zelfs dat niet, dan
    // is het bronpad nog altijd beter dan niets.
    if (projectPath == null || projectPath.isEmpty) {
      return await AssetStaging.stage(sourcePath, subdir: subdir) ?? sourcePath;
    }
    final destDir = Directory(p.join(projectPath, subdir));
    await destDir.create(recursive: true);
    final normalized = p.normalize(sourcePath);
    if (p.isWithin(projectPath, normalized)) {
      return p.relative(normalized, from: projectPath);
    }
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    final dest = await resolveAssetDestination(
      destDir,
      p.basename(sourcePath),
      src,
    );
    if (dest == null) return null;
    if (!dest.alreadyPresent) await src.copy(dest.file.path);
    return '$subdir/${p.basename(dest.file.path)}';
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

  Future<String?> _copyToDir(String sourcePath, Directory destDir) async =>
      _copyInto(sourcePath, destDir, 'media');

  Future<String?> _copyImageToProject(
    String sourcePath,
    Directory imagesDir,
  ) async {
    if (sourcePath.isEmpty ||
        sourcePath.startsWith('images/') ||
        !p.isAbsolute(sourcePath)) {
      return null;
    }
    return _copyInto(sourcePath, imagesDir, 'images');
  }

  /// Kopieer [sourcePath] naar [destDir] en geef de projectrelatieve
  /// verwijzing terug. Botst de naam met andere inhoud, dan wijkt de kopie uit
  /// naar een vrije naam — vandaar dat de teruggegeven naam die van de
  /// bestemming is en niet die van de bron.
  Future<String?> _copyInto(
    String sourcePath,
    Directory destDir,
    String subdir,
  ) async {
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    final dest = await resolveAssetDestination(
      destDir,
      p.basename(sourcePath),
      src,
    );
    if (dest == null) return null;
    if (!dest.alreadyPresent) await src.copy(dest.file.path);
    return '$subdir/${p.basename(dest.file.path)}';
  }

  /// Resolve a slide image path to an absolute path for display.
  String resolve(String imagePath, String? projectPath) {
    return resolveEditorAssetPath(imagePath, projectPath) ?? '';
  }
}
