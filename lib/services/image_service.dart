import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import '../models/slide.dart';
import '../platform/platform_features.dart';
import '../utils/asset_destination.dart';
import '../utils/atomic_file.dart';
import '../utils/log.dart';
import '../utils/project_path.dart';
import 'asset_staging.dart';
import 'slide_image_refs.dart';
import 'web_asset_store.dart';

/// Waarom een afbeelding kiezen/plakken géén pad opleverde. [cancelled] is een
/// bewuste keuze van de gebruiker (geen melding tonen); de overige redenen
/// verdienen uitleg in de UI in plaats van een stil mislukken.
enum ImageImportFailure {
  cancelled,
  rejected,
  noClipboardImage,
  writeFailed,
  memoryBudgetExceeded,
}

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

  /// Injecteerbaar zodat de Linux-route onder `flutter test` (waar
  /// `Platform.isLinux` altijd de testmachine volgt) tóch te bewijzen is.
  final bool Function() _isLinux;

  ImageService({String Function()? languageCode, bool Function()? isLinux})
    : _languageCode = languageCode ?? (() => 'nl'),
      _isLinux = isLinux ?? (() => isLinuxDesktop);

  /// Het eigen klembordkanaal van de Linux-runner (my_application.cc).
  /// Het pasteboard-pakket heeft geen Linux-schrijftak: `writeImage` is daar
  /// een stille no-op, dus schrijven loopt op Linux via dit kanaal (#758).
  static const _linuxClipboardChannel = MethodChannel('ocideck/clipboard');

  String _d(String text) => AppLocalizations.sourceFor(_languageCode(), text);

  /// Per-asset import caps. Images and media are both validated by magic bytes
  /// (not just the picker's extension filter) on top of these caps — see
  /// [imageMimeFromBytes] and [mediaMimeFromBytes].
  static const maxImageBytes = 64 * 1024 * 1024; // 64 MiB
  static const maxMediaBytes = 1024 * 1024 * 1024; // 1 GiB

  /// Zet gevalideerde webbytes in de appbrede store en vertaalt een vol
  /// geheugenbudget naar een uitkomst die de UI gericht kan uitleggen.
  static ImageImportOutcome storeWebImage(
    Uint8List bytes, {
    required String name,
  }) {
    try {
      return ImageImportOutcome.success(WebAssetStore.put(bytes, name: name));
    } on WebAssetBudgetExceeded catch (e) {
      logWarning('ImageService.storeWebImage: web asset budget exceeded', e);
      return const ImageImportOutcome.failed(
        ImageImportFailure.memoryBudgetExceeded,
      );
    }
  }

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

  /// The MIME type behind [b]'s audio/video **container** signature, or null
  /// when the bytes match none of them.
  ///
  /// Images have been signature-checked since the beginning; video and audio
  /// were only ever size-capped, so an arbitrary file renamed to `.mp4` was
  /// accepted into the project and later handed to the platform media stack.
  /// A container check is the same guarantee images already had. (Added
  /// 2026-07-22.)
  ///
  /// This identifies the *container*, not the codec inside it — that is all a
  /// magic-byte check can honestly claim, and it is what keeps a non-media file
  /// out. Decoding stays the platform's job.
  static String? mediaMimeFromBytes(List<int> b) {
    if (b.length < 4) return null;
    // ISO-BMFF (MP4/MOV/M4A/M4V): a box length, then "ftyp" at offset 4.
    if (b.length >= 12 &&
        b[4] == 0x66 &&
        b[5] == 0x74 &&
        b[6] == 0x79 &&
        b[7] == 0x70) {
      return 'video/mp4';
    }
    // Matroska / WebM (EBML header).
    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) {
      return 'video/webm';
    }
    // Ogg / Opus / Vorbis: "OggS".
    if (b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
      return 'audio/ogg';
    }
    // FLAC: "fLaC".
    if (b[0] == 0x66 && b[1] == 0x4C && b[2] == 0x61 && b[3] == 0x43) {
      return 'audio/flac';
    }
    // MP3: an ID3 tag, or a bare frame sync (11 set bits).
    if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return 'audio/mpeg';
    if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return 'audio/mpeg';
    // RIFF containers: "RIFF" ....  then the form type at offset 8.
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46) {
      // "WAVE"
      if (b[8] == 0x57 && b[9] == 0x41 && b[10] == 0x56 && b[11] == 0x45) {
        return 'audio/wav';
      }
      // "AVI "
      if (b[8] == 0x41 && b[9] == 0x56 && b[10] == 0x49) {
        return 'video/x-msvideo';
      }
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

  /// Size cap **and** container signature — the two checks an imported media
  /// file has to pass. [what] names the caller for the log line only.
  Future<bool> _isAcceptableMedia(String path, String what) async {
    if (!await _isWithinMediaCap(path)) {
      logWarning('ImageService.$what: rejected (exceeds size cap)');
      return false;
    }
    try {
      final handle = await File(path).open();
      try {
        final head = await handle.read(16);
        if (mediaMimeFromBytes(head) == null) {
          // Geen bestandsnaam in de log: die is door de gebruiker gekozen en
          // kan een persoonsnaam dragen.
          logWarning(
            'ImageService.$what: geweigerd — de inhoud is geen bekende '
            'audio- of videocontainer',
          );
          return false;
        }
      } finally {
        await handle.close();
      }
    } catch (e) {
      // Fail-closed: onleesbaar is niet aantoonbaar in orde.
      logWarning('ImageService.$what: media signature check failed', e);
      return false;
    }
    return true;
  }

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
      return storeWebImage(bytes, name: file.name);
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
    // Op web bestaat dit pad niet, en het faalt luidruchtiger dan je zou
    // denken: `PlatformFile.path` GOOIT daar een kale String (file_picker
    // 5.5.0 — geen null en geen blob:-URL, zoals hier eerder stond). Die vloog
    // ongevangen omhoog zodra iemand in de webversie op "Bestand kiezen" drukte.
    // Bovendien schrijft `_importIntoProject` naar schijf, wat er ook niet is.
    // De knop is inmiddels ook verborgen (video_slide_editor.dart); deze poort
    // staat er zodat het bestand zijn eigen belofte waarmaakt.
    if (!supportsLocalProjectFolders) return null;
    final result = await FilePicker.pickFiles(
      type: FileType.video,
      dialogTitle: _d('Kies een video'),
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    if (!await _isAcceptableMedia(path, 'pickVideo')) return null;
    return _importIntoProject(path, projectPath, subdir: 'media');
  }

  Future<String?> pickAudio({String? projectPath}) async {
    // Zelfde verhaal als [pickVideo]: `path` gooit op web.
    if (!supportsLocalProjectFolders) return null;
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      dialogTitle: _d('Kies een audiobestand'),
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    if (!await _isAcceptableMedia(path, 'pickAudio')) return null;
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
  ///
  /// Op Linux via het eigen runner-kanaal; de native kant meldt of de bytes
  /// werkelijk als afbeelding op het klembord staan.
  Future<bool> copyImageBytesToClipboard(Uint8List bytes) async {
    try {
      if (bytes.isEmpty) return false;
      if (_isLinux()) {
        final ok = await _linuxClipboardChannel.invokeMethod<bool>(
          'writeImage',
          bytes,
        );
        return ok ?? false;
      }
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
        return storeWebImage(bytes, name: 'geplakt.png');
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
        // Altijd met '/': een verwijzing in het deck is portabel (net als de
        // deck-serializer, die p.posix schrijft). Zonder de conversie zet
        // p.relative op Windows `images\pasted_…png` in de dia — niet-portabel.
        return ImageImportOutcome.success(
          p.relative(file.path, from: projectPath).replaceAll(r'\', '/'),
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
      // Met '/' de deck in — zie de toelichting bij pasteImage hierboven.
      return p.relative(normalized, from: projectPath).replaceAll(r'\', '/');
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
  ///
  /// Élke verwijzing telt mee, ook een `![…](…)` midden in de vrije tekst. Bleef
  /// die achter als absoluut pad, dan wijst de opgeslagen presentatie naar een
  /// bestand buiten haar eigen map: bij de maker werkt het, bij de ontvanger is
  /// het een leeg vak.
  ///
  /// Kopiëren is asynchroon en herschrijven niet, dus het gaat in twee slagen:
  /// eerst elk pad naar zijn nieuwe plek, dan de dia in haar geheel om.
  Future<List<Slide>> copyImagesToProject(
    List<Slide> slides,
    String projectPath,
  ) async {
    final imagesDir = Directory(p.join(projectPath, 'images'));
    await imagesDir.create(recursive: true);

    final updated = <Slide>[];
    for (final slide in slides) {
      final copied = <String, String>{};
      for (final path in slideImagePaths(slide).toSet()) {
        final dest = await _copyImageToProject(path, imagesDir);
        if (dest != null) copied[path] = dest;
      }
      updated.add(rewriteSlideImagePaths(slide, (path) => copied[path]));
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
      final video = await _mediaToProject(
        next.videoPath,
        mediaDir,
        isAudio: false,
      );
      if (video != null) next = next.copyWith(videoPath: video);
      final audio = await _mediaToProject(
        next.audioPath,
        mediaDir,
        isAudio: true,
      );
      if (audio != null) next = next.copyWith(audioPath: audio);
      updated.add(next);
    }
    return updated;
  }

  /// Het projectrelatieve mediapad voor [path], of `null` als er niets te doen
  /// is (leeg, al projectrelatief, of een URL die geen bestand is).
  ///
  /// Twee bronnen: een `mem:`-pad draagt zijn bytes mee (een geïmporteerde of
  /// remote presentatie), een absoluut pad wijst naar schijf.
  Future<String?> _mediaToProject(
    String path,
    Directory mediaDir, {
    required bool isAudio,
  }) async {
    if (WebAssetStore.isMemPath(path)) {
      return _materializeMemAsset(
        path,
        mediaDir,
        subdir: 'media',
        // Per soort, niet één terugval voor allebei: een audiobestand zonder
        // extensie in de store zou anders als `.mp4` landen.
        fallbackName: isAudio ? 'audio.m4a' : 'video.mp4',
        fallbackExtension: isAudio ? '.m4a' : '.mp4',
      );
    }
    if (!_shouldCopy(path)) return null;
    return _copyToDir(path, mediaDir);
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
    if (WebAssetStore.isMemPath(sourcePath)) {
      return _materializeMemImage(sourcePath, imagesDir);
    }
    if (sourcePath.isEmpty ||
        sourcePath.startsWith('images/') ||
        !p.isAbsolute(sourcePath)) {
      return null;
    }
    return _copyInto(sourcePath, imagesDir, 'images');
  }

  /// Schrijf een in-geheugen `mem:`-afbeelding als echt bestand in de
  /// projectmap `images/` en geef de projectrelatieve verwijzing terug. Slides
  /// uit een remote deck (git/WebDAV/S3) dragen hun beeld als `mem:`-pad; zonder
  /// deze stap slaat een gewone opslag die bytes nergens op en breekt de
  /// afbeelding na herladen (zie [WebAssetStore]).
  ///
  /// Null (het pad blijft ongemoeid) als de bytes weg zijn — bijvoorbeeld na een
  /// paginaherlaad op web, waar de store leeg is.
  Future<String?> _materializeMemImage(String memPath, Directory imagesDir) =>
      _materializeMemAsset(
        memPath,
        imagesDir,
        subdir: 'images',
        fallbackName: 'afbeelding.png',
        fallbackExtension: '.png',
      );

  /// Schrijf een in-geheugen `mem:`-asset als echt bestand in [destDir] en geef
  /// het projectrelatieve pad terug.
  ///
  /// Gedeeld door beeld en media. Media had deze route niet, en dat was een
  /// stil gat: een presentatie-import zet ingebedde video als `mem:`-pad neer,
  /// maar `_shouldCopy` liet alleen absolute paden door — de bytes werden dus
  /// nooit weggeschreven en het deck hield een verwijzing over naar een bestand
  /// dat nooit heeft bestaan (#772).
  Future<String?> _materializeMemAsset(
    String memPath,
    Directory destDir, {
    required String subdir,
    required String fallbackName,
    required String fallbackExtension,
  }) async {
    final bytes = WebAssetStore.bytesFor(memPath);
    if (bytes == null) return null;
    final rawName = WebAssetStore.nameFor(memPath) ?? fallbackName;
    // Namen uit de store dragen doorgaans een extensie (git-assets heten
    // `<sha256>.<ext>`); ontbreekt die, dan is de terugval veilig.
    final filename = p.extension(rawName).isEmpty
        ? '$rawName$fallbackExtension'
        : rawName;
    final dest = await resolveAssetDestinationForBytes(
      destDir,
      filename,
      bytes,
    );
    if (dest == null) return null;
    if (!dest.alreadyPresent) await writeBytesAtomic(dest.file, bytes);
    return '$subdir/${p.basename(dest.file.path)}';
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
