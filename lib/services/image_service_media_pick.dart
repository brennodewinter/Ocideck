part of 'image_service.dart';

/// Mediatransport tussen projectmappen als extension op [ImageService] —
/// verplaatst uit `image_service.dart` voor het bestandsplafond (zelfde
/// patroon als `image_service_svg.dart`). Deze leden zijn nooit een
/// override-doel voor testfakes; de kies-methoden (`pickVideo` e.a.) blijven
/// bewust óp de klasse want die wél virtueel moeten blijven.
extension ImageServiceMediaTransport on ImageService {
  Future<List<Slide>> copyMediaToProject(
    List<Slide> slides,
    String projectPath, {
    String? sourceProjectPath,
  }) async {
    final mediaDir = await createContainedProjectDirectory(
      projectPath,
      'media',
    );

    final updated = <Slide>[];
    for (final slide in slides) {
      var next = slide;
      final video = await _mediaToProject(
        next.videoPath,
        mediaDir,
        fallbackName: 'video.mp4',
        fallbackExtension: '.mp4',
        sourceProjectPath: sourceProjectPath,
      );
      if (video != null) next = next.copyWith(videoPath: video);
      // Ondertitels reizen mee naar de doelmap (#2841): de `<track>` in de
      // markdown moet bij het gekopieerde deck naar een lokaal bestand wijzen.
      final captions = await _mediaToProject(
        next.videoCaptions,
        mediaDir,
        fallbackName: 'ondertitels.vtt',
        fallbackExtension: '.vtt',
        sourceProjectPath: sourceProjectPath,
      );
      if (captions != null) next = next.copyWith(videoCaptions: captions);
      final audio = await _mediaToProject(
        next.audioPath,
        mediaDir,
        fallbackName: 'audio.m4a',
        fallbackExtension: '.m4a',
        sourceProjectPath: sourceProjectPath,
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
    // Per soort een eigen terugval: een bestand zonder extensie in de store
    // zou anders met de verkeerde landen (.mp4 voor een .vtt bijvoorbeeld).
    required String fallbackName,
    required String fallbackExtension,
    String? sourceProjectPath,
  }) async {
    if (WebAssetStore.isMemPath(path)) {
      final bytes = WebAssetStore.bytesFor(path);
      if (bytes == null || bytes.length > ImageService.maxMediaBytes) {
        return null;
      }
      return _materializeMemAsset(
        path,
        mediaDir,
        subdir: 'media',
        fallbackName: fallbackName,
        fallbackExtension: fallbackExtension,
      );
    }
    if (!_shouldCopy(path)) return null;
    final root = AssetStaging.isStagedPath(path)
        ? AssetStaging.rootPath
        : sourceProjectPath;
    if (root == null) return null;
    final trusted = resolveContainedRealPath(path, root);
    if (trusted == null || !await _isWithinMediaCap(trusted)) {
      logWarning('ImageService.copyMedia: rejected (exceeds size cap)');
      return null;
    }
    return _copyToDir(trusted, mediaDir);
  }

  bool _shouldCopy(String path) {
    return path.isNotEmpty &&
        !path.startsWith('media/') &&
        !path.startsWith('images/') &&
        p.isAbsolute(path);
  }

  Future<String?> _copyToDir(String sourcePath, Directory destDir) async =>
      _copyInto(sourcePath, destDir, 'media');
}
