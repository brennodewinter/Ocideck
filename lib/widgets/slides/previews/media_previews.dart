// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

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

class _AudioPlaybackState extends State<_AudioPlayback> {
  VideoPlayerController? _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(_AudioPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath != widget.audioPath ||
        oldWidget.autoplay != widget.autoplay) {
      _init();
    }
  }

  /// Bumped on every (re)init so an in-flight run that has been superseded by a
  /// newer one (rapid slide switches) can bail and clean up its controller.
  int _initGen = 0;

  Future<void> _init() async {
    final gen = ++_initGen;
    // Detach and null the old controller *before* awaiting its dispose, so a
    // concurrent _init sees no controller and cannot dispose it a second time.
    _controller?.removeListener(_onTick);
    final old = _controller;
    _controller = null;
    await old?.dispose();
    if (gen != _initGen) return; // superseded
    _completed = false;
    final path = _resolvePath(widget.audioPath, widget.projectPath);
    if (path == null) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      if (gen != _initGen) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      if (widget.autoplay) await controller.play();
    } catch (e) {
      logWarning('_AudioPlaybackState._init: audio controller init failed', e);
    }
    if (gen != _initGen) {
      await controller.dispose();
      return;
    }
    _controller = controller;
    if (mounted) setState(() {});
  }

  /// Detecteer het einde van de audio en meld dat één keer (voor auto-advance).
  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _completed) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    if (dur > Duration.zero &&
        pos.inMilliseconds >= dur.inMilliseconds - 200 &&
        !c.value.isPlaying) {
      _completed = true;
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Positioned(
      right: widget.w * 0.035,
      bottom: widget.w * 0.035,
      child: IconButton(
        tooltip: 'Audio',
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
      color: _hexColor(profile.slideBackgroundColor),
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
                    _resolvedImage(context, slide.imagePath, projectPath),
                    _captionOverlay(context, slide.imageCaption, w),
                  ],
                ),
              ),
              SizedBox(
                width: rightW,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _resolvedImage(context, slide.imagePath2, projectPath),
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
                  linkColor: const Color(0xFF8BB8FF),
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
          bgColor: _hexColor(profile.slideBackgroundColor),
          // When zoomed out, anchor the image to the top so the bottom title
          // banner sits in the freed-up space instead of over the picture.
          alignment: hasTitle ? Alignment.topCenter : Alignment.center,
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
                linkColor: const Color(0xFF8BB8FF),
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

class _VideoPreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;
  final bool autoplay;
  final VoidCallback? onComplete;

  const _VideoPreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
    this.autoplay = false,
    this.onComplete,
  });

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  String? _path;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(_VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.videoPath != widget.slide.videoPath ||
        oldWidget.autoplay != widget.autoplay) {
      _init();
    }
  }

  /// Bumped on every (re)init so an in-flight run that has been superseded by a
  /// newer one (rapid slide switches) can bail and clean up its controller.
  int _initGen = 0;

  Future<void> _init() async {
    final gen = ++_initGen;
    // Detach and null the old controller *before* awaiting its dispose, so a
    // concurrent _init sees no controller and cannot dispose it a second time.
    _controller?.removeListener(_onTick);
    final old = _controller;
    _controller = null;
    await old?.dispose();
    if (gen != _initGen) return; // superseded
    _completed = false;
    _path = _resolvePath(widget.slide.videoPath, widget.projectPath);
    if (_path == null) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(File(_path!));
    try {
      await controller.initialize();
      if (gen != _initGen) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      await controller.setLooping(false);
      if (widget.autoplay) await controller.play();
    } catch (e) {
      logWarning('_VideoPreviewState._init: video controller init failed', e);
      // Keep the placeholder visible when the platform cannot open the file.
    }
    if (gen != _initGen) {
      await controller.dispose();
      return;
    }
    _controller = controller;
    if (mounted) setState(() {});
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _completed ||
        !widget.autoplay) {
      return;
    }
    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration > Duration.zero &&
        position.inMilliseconds >= duration.inMilliseconds - 200 &&
        !controller.value.isPlaying) {
      _completed = true;
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      color: _hexColor(widget.profile.slideBackgroundColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            )
          else
            _mediaPlaceholder(Icons.movie_outlined, 'Video'),
          if (widget.slide.title.isNotEmpty)
            Positioned(
              left: widget.w * 0.06,
              right: widget.w * 0.06,
              top: widget.w * 0.04,
              child: _md(
                context,
                widget.slide.title,
                _applyFont(
                  widget.font,
                  TextStyle(
                    color: _hexColor(widget.profile.textColor),
                    fontSize: widget.w * 0.038,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                linkColor: _hexColor(widget.profile.accentColor),
              ),
            ),
          Positioned(
            left: widget.w * 0.04,
            bottom: widget.w * 0.035,
            child: IconButton(
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
                    ? Icons.pause_circle
                    : Icons.play_circle,
              ),
              iconSize: widget.w * 0.045,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rendert een afbeelding met zoomfactor op basis van BoxFit.contain.
///   imageSize = 0   → cover (Marp-standaard, vult frame, snijdt bij)
///   imageSize = 100 → volledige afbeelding zichtbaar (contain, evt. randen)
///   imageSize > 100 → inzoomen: groter dan contain, bijgesneden door ClipRect
///   imageSize < 100 → nog meer uitzoomen: afbeelding kleiner dan contain
Widget _zoomedImage(
  BuildContext context,
  String imagePath,
  String? projectPath,
  int imageSize, {
  Color bgColor = Colors.black,
  Alignment alignment = Alignment.center,
}) {
  if (imageSize == 0) {
    return _resolvedImage(
      context,
      imagePath,
      projectPath,
    ); // BoxFit.cover standaard
  }
  final scale = imageSize / 100.0;
  // Size the image box to `scale` × the available area and let BoxFit.contain
  // fit the picture inside it. This produces the same visual result as a
  // Transform.scale but without a transform layer, which `RepaintBoundary
  // .toImage` (used for exports) captures far more reliably — a scaled
  // transform layer would frequently render blank in the exported PNG.
  return ClipRect(
    child: ColoredBox(
      color: bgColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxW = constraints.maxWidth * scale;
          final boxH = constraints.maxHeight * scale;
          return Align(
            alignment: alignment,
            child: SizedBox(
              width: boxW,
              height: boxH,
              // BoxFit.contain: toont de volledige afbeelding zonder bijsnijden
              child: _resolvedImage(
                context,
                imagePath,
                projectPath,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _resolvedImage(
  BuildContext context,
  String imagePath,
  String? projectPath, {
  BoxFit fit = BoxFit.cover,
}) {
  if (imagePath.isEmpty) return _imagePlaceholder(context);

  final resolved = resolveSlideAssetPath(imagePath, projectPath);
  if (resolved == null) return _imagePlaceholder(context);

  return Image.file(
    File(resolved),
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    // Keep showing the previous frame while the next image decodes. Without
    // this the widget paints nothing for a frame on a source change, which
    // shows up as a black flash between slides — fatal when recording video.
    gaplessPlayback: true,
    errorBuilder: (context, error, stackTrace) => _imagePlaceholder(context),
  );
}

Widget _captionOverlay(
  BuildContext context,
  String caption,
  double w, {
  double? right,
  double? bottom,
}) {
  final text = caption.trim();
  if (text.isEmpty) return const SizedBox.shrink();
  // Een copyright/bijschrift staat rechtsonder; als daar een TLP-markering
  // staat, schuift het bijschrift erboven zodat het niet wordt overschreven.
  final lift = _SlideLinkScope.hasBottomTlpOf(context)
      ? _tlpVerticalReserve(w)
      : 0.0;
  return Positioned(
    right: right ?? w * _kTlpEdge,
    bottom: (bottom ?? _tlpBottomInset(w)) + lift,
    child: Container(
      constraints: BoxConstraints(maxWidth: w * 0.5),
      padding: EdgeInsets.symmetric(horizontal: w * 0.008, vertical: w * 0.005),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.011,
          height: 1.25,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

Widget _mediaPlaceholder(IconData icon, String label) {
  return Container(
    color: const Color(0xFFE2E8F0),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF94A3B8), size: 32),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

Widget _imagePlaceholder(BuildContext context) {
  return ColoredBox(
    color: const Color(0xFFE2E8F0),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = constraints.biggest.shortestSide;
        if (shortestSide < 48) {
          return Center(
            child: Icon(
              Icons.image_outlined,
              color: const Color(0xFF94A3B8),
              size: shortestSide * 0.65,
            ),
          );
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.image_outlined,
                color: Color(0xFF94A3B8),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.d('Afbeelding'),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
              ),
            ],
          ),
        );
      },
    ),
  );
}
