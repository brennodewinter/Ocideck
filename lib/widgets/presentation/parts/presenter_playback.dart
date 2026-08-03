// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterPlayback on _FullscreenPresenterState {
  /// Decode the current slide's images plus its neighbours into the image cache
  /// ahead of time. Because a precached [FileImage] resolves synchronously, the
  /// next slide paints its picture on the very first frame instead of flashing
  /// the black Scaffold behind it while the file decodes — essential for a clean
  /// recording. Best-effort: decode errors are swallowed.
  void _precacheNeighbours() {
    if (!mounted) return;
    final logo = widget.themeProfile.logoPath;
    if (logo != null && logo.isNotEmpty) {
      _precachePath(logo, trusted: true);
    }
    // Current first, then the likely next/previous targets.
    for (final offset in const [0, 1, -1, 2]) {
      final i = _index + offset;
      if (i < 0 || i >= widget.slides.length) continue;
      final slide = widget.slides[i];
      _precachePath(slide.imagePath);
      _precachePath(slide.imagePath2);
    }
  }

  void _precachePath(String path, {bool trusted = false}) {
    // Gebundelde (asset:) en in-memory (mem:) paden hebben geen
    // bestandsresolutie; op web bestaan File-paden sowieso niet.
    if (isBundledAssetPath(path)) {
      precacheImage(
        cappedBundledAssetImage(bundledAssetKey(path)),
        context,
        onError: (_, _) {},
      );
      return;
    }
    final memBytes = WebAssetStore.isMemPath(path)
        ? WebAssetStore.bytesFor(path)
        : null;
    if (memBytes != null) {
      precacheImage(cappedMemoryImage(memBytes), context, onError: (_, _) {});
      return;
    }
    if (kIsWeb) return;
    final resolved = trusted
        ? resolveTrustedAssetPath(path, widget.projectPath)
        : resolveSlideAssetPath(path, widget.projectPath);
    if (resolved == null) return;
    // Capped provider (same cache key as display) so the precached frame is
    // reused and an animated image is decoded animation-preserving, not frozen.
    precacheImage(cappedFileImage(File(resolved)), context, onError: (_, _) {});
  }

  void _scheduleAdvance() {
    // Funnel point for every navigation (next/prev/jump/auto) and the initial
    // frame, so neighbour images are always warm before they are shown.
    _precacheNeighbours();
    // Same funnel handles question slides: draw a fresh round / start the timer
    // when the shown slide actually changed (idempotent on repeat calls).
    _onSlideShown();
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _rebuild(() => _progress = 0);

    // Auto-modus uit: nooit vanzelf wisselen.
    if (!_autoPlay || _tableEditMode) return;

    final slide = widget.slides[_index.clamp(0, widget.slides.length - 1)];

    if (_advanceOnMediaEnd && autoAdvanceWaitsForMedia(slide)) return;

    final dur = slide.advanceDuration;
    if (dur <= 0) return;
    // Op de laatste slide alleen doortikken als we herhalen.
    if (_index >= widget.slides.length - 1 && !_loop) return;

    final totalMs = (dur * 1000).round();
    final startTime = DateTime.now();

    // Tick elke 50ms voor een vloeiende voortgangsbalk
    _advanceTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      final p = (elapsed / totalMs).clamp(0.0, 1.0);
      _rebuild(() => _progress = p);
      if (elapsed >= totalMs) {
        t.cancel();
        _autoAdvance();
      }
    });
  }

  /// Automatisch doorschakelen (tijd of media-einde): naar de volgende slide,
  /// of bij herhaling vanaf de laatste terug naar de eerste. Zonder herhaling
  /// blijft de laatste slide gewoon staan.
  void _autoAdvance() {
    if (_blank != _Blank.none || _tableEditMode) return;
    final plan = _richTextPlanFor(_currentSlide);
    if (plan != null && _richTextPage < plan.pageCount - 1) {
      _setRichTextPage(_richTextPage + 1);
      _scheduleAdvance();
      return;
    }
    // Niet automatisch voorbij een onbeantwoorde vraag schuiven.
    if (_questionBlocksAdvance) return;
    // Auto-play volgt dezelfde sprong-uit als handmatig (#1162), maar vult de
    // retrace-stack bewust níet: in een kiosk-lus zou die eindeloos groeien.
    final jumpIndex = _indexOfAnchor(widget.slides, _currentSlide.nextAnchor);
    final target =
        jumpIndex ??
        (_index < widget.slides.length - 1 ? _index + 1 : (_loop ? 0 : null));
    if (target == null) return;
    _commitActiveInk();
    _persistUserNoteFromController();
    _rebuild(() {
      _index = target;
      _richTextPage = 0;
      _timelineStep = 0;
    });
    _loadUserNoteIntoController();
    _scheduleAdvance();
  }

  void _onMediaCompleted({int? index, String? kind}) {
    if (index != null && index != _index) return;
    final slide = widget.slides[_index.clamp(0, widget.slides.length - 1)];
    // A video is primary on a video slide. Ignore an attached audio track that
    // happens to finish earlier.
    if (kind == 'audio' &&
        slide.type == SlideType.video &&
        slide.videoPath.isNotEmpty &&
        slide.videoAutoplay) {
      return;
    }
    if (_autoPlay && _advanceOnMediaEnd && autoAdvanceWaitsForMedia(slide)) {
      _autoAdvance();
    }
  }

  void _toggleAutoPlay() {
    _rebuild(() => _autoPlay = !_autoPlay);
    _scheduleAdvance();
  }

  void _toggleLoop() {
    _rebuild(() => _loop = !_loop);
    _scheduleAdvance();
  }

  void _toggleMediaAdvance() {
    _rebuild(() => _advanceOnMediaEnd = !_advanceOnMediaEnd);
    _scheduleAdvance();
  }
}
