part of 'image_service.dart';

/// Mediapickers als extension op [ImageService] — verplaatst uit
/// `image_service.dart` voor het bestandsplafond (zelfde patroon als
/// `image_service_svg.dart`). Een extension zit in dezelfde library en mag
/// dus bij `_private` leden zoals `_importIntoProject`.
extension ImageServiceMediaPick on ImageService {
  /// De gedeelde kies-route voor media: picker → acceptatie → import onder
  /// `media/`. Op web bestaat dit pad niet, en het faalt luidruchtiger dan je
  /// zou denken: `PlatformFile.path` GOOIT daar een kale String (file_picker
  /// 5.5.0 — geen null en geen blob:-URL, zoals hier eerder stond). Die vloog
  /// ongevangen omhoog zodra iemand in de webversie op "Bestand kiezen" drukte.
  /// Bovendien schrijft `_importIntoProject` naar schijf, wat er ook niet is.
  /// De knop is inmiddels ook verborgen (video_slide_editor.dart); deze poort
  /// staat er zodat het bestand zijn eigen belofte waarmaakt.
  Future<String?> _pickIntoProject(
    FileType type,
    String dialogTitle,
    Future<bool> Function(String path) acceptable,
    String? projectPath, {
    List<String>? allowedExtensions,
  }) async {
    if (!supportsLocalProjectFolders) return null;
    final file = await FilePicker.pickFile(
      type: type,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
    final path = file?.path;
    if (path == null) return null;
    if (!await acceptable(path)) return null;
    return _importIntoProject(path, projectPath, subdir: 'media');
  }

  Future<String?> pickVideo({String? projectPath}) async => _pickIntoProject(
    FileType.video,
    _d('Kies een video'),
    (p) => _isAcceptableMedia(p, 'pickVideo'),
    projectPath,
  );

  /// Kiest een ondertitelbestand (`.vtt` of `.srt`) voor een videodia (#2841).
  /// Geen container-check zoals bij [pickVideo]: een captionbestand is platte
  /// tekst — wel dezelfde groottecap en import onder `media/`.
  Future<String?> pickCaptions({String? projectPath}) async => _pickIntoProject(
    FileType.custom,
    _d('Kies een ondertitelbestand'),
    (p) async {
      if (!await _isWithinMediaCap(p)) {
        logWarning('ImageService.pickCaptions: rejected (exceeds size cap)');
        return false;
      }
      return true;
    },
    projectPath,
    allowedExtensions: const ['vtt', 'srt'],
  );

  Future<String?> pickAudio({String? projectPath}) async => _pickIntoProject(
    FileType.audio,
    _d('Kies een audiobestand'),
    (p) => _isAcceptableMedia(p, 'pickAudio'),
    projectPath,
  );
}
