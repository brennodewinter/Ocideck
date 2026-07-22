// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Pauzeert een mediacontroller vóór dispose en breekt 'm dan af. Op desktop
/// kan de audio anders blijven doorspelen nadat de controller al is opgeruimd:
/// de dispose-melding reist los van de pauze-opdracht over het platformkanaal.
/// Pause vóór dispose op hetzelfde kanaal garandeert dat het geluid stopt.
/// Veilig op een niet-geïnitialiseerde controller (pause/dispose no-op'en dan).
/// Gebruikt bij elke teardown: widget-dispose én het vervangen van een oude of
/// achterhaalde controller in [_MediaPlaybackHost.initMedia] (snel wisselen).
Future<void> _stopAndDispose(VideoPlayerController? controller) async {
  if (controller == null) return;
  await controller.pause();
  await controller.dispose();
}

/// Gedeelde levenscyclus voor de audio- en videopreview. Beide spelen via een
/// [VideoPlayerController] (video_player dekt op desktop ook audio) en delen
/// exact dezelfde (her)initialisatie met generatie-bewaking tegen snelle
/// slide-wissels, eind-detectie en teardown. De subklasse vult alleen de
/// mediaspecifieke delen in: het pad, de autoplay-vlag, eventuele extra
/// controller-configuratie en de eind-callback.
///
/// De controller, [_completed] en de generatieteller leven hier, zodat de
/// race-bewaking (en de pauze-vóór-dispose) op één plek staat in plaats van in
/// twee bijna-identieke kopieën.
mixin _MediaPlaybackHost<T extends StatefulWidget> on State<T> {
  VideoPlayerController? _controller;
  bool _completed = false;

  /// Bumped on every (re)init so an in-flight run that has been superseded by a
  /// newer one (rapid slide switches) can bail and clean up its controller.
  int _initGen = 0;

  // ── Door de subklasse ingevuld ───────────────────────────────────────────

  /// Resolved pad/URL naar de media, of null als er niets te spelen is (of de
  /// remote-media-gate dicht staat). Voor een lokaal bestand is dit een
  /// bestandspad; voor een live URL de URL zelf.
  String? resolveMediaPath();

  /// Of de media automatisch start.
  bool get mediaAutoplay;

  /// Begin/eind van het te spelen segment in milliseconden (het "knippen"). 0 =
  /// vanaf begin / tot natuurlijk einde. Standaard de hele media.
  int get mediaStartMs => 0;
  int get mediaEndMs => 0;

  /// Of het einde van de media gemeld moet worden (voor auto-advance). Audio
  /// meldt altijd; video alleen tijdens autoplay.
  bool get reportsMediaCompletion => true;

  /// Maakt de controller voor [source]. Een `http(s)`-bron wordt een
  /// netwerk-controller, anders een bestand-controller. Subklassen hoeven dit
  /// zelden te overschrijven.
  VideoPlayerController createMediaController(String source) {
    final uri = Uri.tryParse(source);
    final scheme = uri?.scheme.toLowerCase();
    if (uri != null && (scheme == 'http' || scheme == 'https')) {
      return VideoPlayerController.networkUrl(uri);
    }
    return VideoPlayerController.file(File(source));
  }

  /// Extra controller-instelling vóór play (bv. setLooping). Standaard niets.
  Future<void> configureController(VideoPlayerController controller) async {}

  /// Aangeroepen wanneer de media (eenmalig) is afgelopen.
  void onMediaComplete();

  /// Aangeroepen bij elke tick met de huidige positie en duur (ms). Standaard
  /// niets; de videopreview gebruikt dit om de playhead te publiceren.
  void onPositionTick(int positionMs, int durationMs) {}

  /// Label voor de waarschuwing als initialisatie faalt.
  String get mediaLogLabel;

  // ── Gedeelde levenscyclus ────────────────────────────────────────────────

  Future<void> initMedia() async {
    final gen = ++_initGen;
    // Detach and null the old controller *before* awaiting its dispose, so a
    // concurrent initMedia sees no controller and cannot dispose it twice.
    _controller?.removeListener(_onMediaTick);
    final old = _controller;
    _controller = null;
    await _stopAndDispose(old);
    if (gen != _initGen) return; // superseded
    _completed = false;
    final path = resolveMediaPath();
    if (path == null) {
      if (mounted) setState(() {});
      return;
    }
    // SSRF gate for a remote media URL: resolve the host and refuse an internal
    // target before VideoPlayerController.networkUrl, which would otherwise
    // resolve+connect with no host check (see NetGuard.isAllowedMediaUrlResolved).
    if (VideoSource.looksLikeUrl(path) &&
        !await NetGuard.isAllowedMediaUrlResolved(path)) {
      if (gen != _initGen) return;
      if (mounted) setState(() {}); // keep the placeholder visible
      return;
    }
    if (gen != _initGen) return; // superseded while resolving
    final controller = createMediaController(path);
    try {
      await controller.initialize();
      if (gen != _initGen) {
        await _stopAndDispose(controller);
        return;
      }
      controller.addListener(_onMediaTick);
      await configureController(controller);
      // Spoel naar het knip-beginpunt vóór play, zodat dit segment op de juiste
      // plek begint (en niet kort het begin van de hele video laat zien).
      if (mediaStartMs > 0) {
        await controller.seekTo(Duration(milliseconds: mediaStartMs));
      }
      if (mediaAutoplay) await controller.play();
    } catch (e) {
      logWarning(mediaLogLabel, e);
      // Keep the placeholder visible when the platform cannot open the file.
    }
    if (gen != _initGen) {
      await _stopAndDispose(controller);
      return;
    }
    _controller = controller;
    if (mounted) setState(() {});
  }

  /// Detecteer het einde van het (geknipte) segment en meld dat één keer (voor
  /// auto-advance). Twee einden zijn mogelijk: het knip-eindpunt [mediaEndMs]
  /// (bereikt terwijl de video nog speelt) of het natuurlijke einde van de
  /// media. Bij een knip-eindpunt pauzeren we áltijd zodat het beeld niet
  /// doorloopt in het volgende segment; de eind-melding (auto-advance) volgt
  /// alleen als [reportsMediaCompletion].
  void _onMediaTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _completed) return;
    final dur = c.value.duration;
    final pos = c.value.position;
    final endMs = mediaEndMs;

    // Publiceer de positie (voor het "knippen" in de editor).
    onPositionTick(pos.inMilliseconds, dur.inMilliseconds);

    // Knip-eindpunt: bereikt terwijl de media nog speelt → stop hier.
    if (endMs > 0 && pos.inMilliseconds >= endMs) {
      _completed = true;
      if (c.value.isPlaying) c.pause();
      if (reportsMediaCompletion) onMediaComplete();
      return;
    }

    // Natuurlijk einde (alleen relevant voor de auto-advance-melding).
    if (!reportsMediaCompletion) return;
    if (dur > Duration.zero &&
        pos.inMilliseconds >= dur.inMilliseconds - 200 &&
        !c.value.isPlaying) {
      _completed = true;
      onMediaComplete();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onMediaTick);
    // Pauzeer vóór dispose, anders blijft de audio op desktop doorspelen nadat
    // de widget is afgebroken (bv. bij het verlaten met Esc). Zie [_stopAndDispose].
    _stopAndDispose(controller);
    super.dispose();
  }
}

class _AudioPlayback extends StatefulWidget {
  final String audioPath;
  final String? projectPath;
  final bool autoplay;
  final double w;
  final VoidCallback? onComplete;

  const _AudioPlayback({
    required this.audioPath,
    required this.projectPath,
    required this.autoplay,
    required this.w,
    this.onComplete,
  });

  @override
  State<_AudioPlayback> createState() => _AudioPlaybackState();
}

class _AudioPlaybackState extends State<_AudioPlayback>
    with _MediaPlaybackHost<_AudioPlayback> {
  @override
  void initState() {
    super.initState();
    initMedia();
  }

  @override
  void didUpdateWidget(_AudioPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath != widget.audioPath ||
        oldWidget.autoplay != widget.autoplay) {
      initMedia();
    }
  }

  @override
  String? resolveMediaPath() =>
      _resolvePath(widget.audioPath, widget.projectPath);

  @override
  bool get mediaAutoplay => widget.autoplay;

  @override
  void onMediaComplete() => widget.onComplete?.call();

  @override
  String get mediaLogLabel =>
      '_AudioPlaybackState.initMedia: audio controller init failed';

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Positioned(
      right: widget.w * 0.035,
      bottom: widget.w * 0.035,
      child: IconButton(
        tooltip: context.l10n.d('Audio'),
        onPressed: controller == null || !controller.value.isInitialized
            ? null
            : () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
        icon: Icon(
          controller?.value.isPlaying == true
              ? Icons.volume_up
              : Icons.volume_up_outlined,
        ),
        iconSize: widget.w * 0.032,
      ),
    );
  }
}

// ── Individual slide-type renderers ──────────────────────────────────────────

class _TwoImagesPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  const _TwoImagesPreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final splitFraction = (slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.5)
        .clamp(0.1, 0.9);
    final leftW = w * splitFraction;
    final rightW = w * (1 - splitFraction);
    final titleSize = w * 0.032;

    return Container(
      color: AppTheme.parseHexColor(profile.slideBackgroundColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Twee afbeeldingen naast elkaar
          Row(
            children: [
              SizedBox(
                width: leftW,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _resolvedImage(
                      context,
                      slide.imagePath,
                      projectPath,
                      alignment: focalAlignment(
                        slide.imageFocalX,
                        slide.imageFocalY,
                      ),
                      semanticLabel: imageSemanticsLabel(
                        context,
                        slide.imageCaption,
                        altText: slide.imageAltText,
                      ),
                    ),
                    _captionOverlay(context, slide.imageCaption, w),
                  ],
                ),
              ),
              SizedBox(
                width: rightW,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _resolvedImage(
                      context,
                      slide.imagePath2,
                      projectPath,
                      alignment: focalAlignment(
                        slide.imageFocalX2,
                        slide.imageFocalY2,
                      ),
                      semanticLabel: imageSemanticsLabel(
                        context,
                        slide.imageCaption2,
                        altText: slide.imageAltText2,
                      ),
                    ),
                    _captionOverlay(context, slide.imageCaption2, w),
                  ],
                ),
              ),
            ],
          ),
          // Optionele ondertitel
          if (slide.title.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: w * 0.04,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.04,
                  vertical: w * 0.015,
                ),
                child: _md(
                  context,
                  slide.title,
                  _applyFont(
                    font,
                    TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  linkColor: AppTheme.paleBlue2,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  const _ImagePreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final hasTitle = slide.title.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        _zoomedImage(
          context,
          slide.imagePath,
          projectPath,
          slide.imageSize,
          bgColor: AppTheme.parseHexColor(profile.slideBackgroundColor),
          // A focal point (crop) decides which part of the picture stays in
          // view. Without one, keep the old default: when zoomed out, anchor to
          // the top so the bottom title banner sits in the freed-up space.
          alignment: hasCustomFocal(slide.imageFocalX, slide.imageFocalY)
              ? focalAlignment(slide.imageFocalX, slide.imageFocalY)
              : (hasTitle ? Alignment.topCenter : Alignment.center),
          semanticLabel: imageSemanticsLabel(
            context,
            slide.imageCaption,
            altText: slide.imageAltText,
          ),
        ),
        if (slide.title.isNotEmpty)
          Positioned(
            left: w * 0.06,
            right: w * 0.06,
            bottom: w * 0.06,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.04,
                vertical: w * 0.02,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: _md(
                context,
                slide.title,
                _applyFont(
                  font,
                  TextStyle(
                    color: Colors.white,
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                linkColor: AppTheme.paleBlue2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        _captionOverlay(context, slide.imageCaption, w),
      ],
    );
  }
}
