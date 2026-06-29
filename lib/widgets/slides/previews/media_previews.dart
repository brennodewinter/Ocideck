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
  final VideoSource source;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;
  final bool autoplay;
  final bool allowRemoteMedia;
  final VoidCallback? onComplete;

  const _VideoPreview({
    required this.slide,
    required this.source,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
    this.autoplay = false,
    this.allowRemoteMedia = false,
    this.onComplete,
  });

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview>
    with _MediaPlaybackHost<_VideoPreview> {
  // De afspeel-/pauzeknop blijft verborgen tot de muis boven de video hangt,
  // zodat hij de dia niet ontsiert tijdens het presenteren.
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    initMedia();
  }

  @override
  void didUpdateWidget(_VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.videoPath != widget.slide.videoPath ||
        oldWidget.slide.videoStartMs != widget.slide.videoStartMs ||
        oldWidget.slide.videoEndMs != widget.slide.videoEndMs ||
        oldWidget.allowRemoteMedia != widget.allowRemoteMedia ||
        oldWidget.autoplay != widget.autoplay) {
      initMedia();
    }
  }

  @override
  String? resolveMediaPath() {
    switch (widget.source.kind) {
      case VideoSourceKind.localFile:
        return _resolvePath(widget.slide.videoPath, widget.projectPath);
      case VideoSourceKind.remoteFile:
        // Live laden alleen als de gebruiker remote media heeft toegestaan én
        // de URL door de SSRF-gate komt; anders placeholder met de URL.
        if (!widget.allowRemoteMedia) return null;
        return VideoSource.isAllowedRemoteUrl(widget.slide.videoPath)
            ? widget.slide.videoPath
            : null;
      case VideoSourceKind.youtube:
      case VideoSourceKind.vimeo:
      case VideoSourceKind.none:
        return null; // embeds gaan via _VideoEmbedPreview
    }
  }

  @override
  int get mediaStartMs => widget.slide.videoStartMs;

  @override
  int get mediaEndMs => widget.slide.videoEndMs;

  @override
  bool get mediaAutoplay => widget.autoplay;

  // Video meldt het einde alleen tijdens autoplay: handmatig afspelen mag niet
  // ongevraagd doorbladeren.
  @override
  bool get reportsMediaCompletion => widget.autoplay;

  @override
  Future<void> configureController(VideoPlayerController controller) =>
      controller.setLooping(false);

  @override
  void onMediaComplete() => widget.onComplete?.call();

  @override
  void onPositionTick(int positionMs, int durationMs) {
    VideoPlayheadBus.publish(
      VideoPlayhead(
        slideId: widget.slide.id,
        positionMs: positionMs,
        durationMs: durationMs,
      ),
    );
  }

  @override
  void dispose() {
    VideoPlayheadBus.clearFor(widget.slide.id);
    super.dispose();
  }

  @override
  String get mediaLogLabel =>
      '_VideoPreviewState.initMedia: video controller init failed';

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return MouseRegion(
      onEnter: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: Container(
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
            else if (widget.source.kind == VideoSourceKind.remoteFile &&
                !widget.allowRemoteMedia)
              _remoteBlockedPlaceholder(context, widget.slide.videoPath)
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
              // Verborgen tot je over de video hovert; dan vloeit hij in. Als hij
              // verborgen is laat IgnorePointer tikken door (doorbladeren blijft
              // werken) en is hij niet bereikbaar.
              child: IgnorePointer(
                ignoring: !_hovering,
                child: AnimatedOpacity(
                  opacity: _hovering ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: IconButton(
                    onPressed:
                        controller == null || !controller.value.isInitialized
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Speelt een YouTube/Vimeo-embed af in een [WebViewWidget]. De officiële
/// speler-API's (YouTube IFrame API / Vimeo player.js) regelen het afspelen; een
/// JS-channel (`OciDeck`) meldt de positie (voor het "knippen") en het einde van
/// het — eventueel geknipte — segment (voor auto-advance). De trim-grenzen gaan
/// via de embed-URL (start) en worden in JS bewaakt (eind).
class _VideoEmbedPreview extends StatefulWidget {
  final Slide slide;
  final VideoSource source;
  final double w;
  final String font;
  final ThemeProfile profile;
  final bool autoplay;
  final bool allowRemoteMedia;
  final VoidCallback? onComplete;

  const _VideoEmbedPreview({
    required this.slide,
    required this.source,
    required this.w,
    required this.font,
    required this.profile,
    this.autoplay = false,
    this.allowRemoteMedia = false,
    this.onComplete,
  });

  @override
  State<_VideoEmbedPreview> createState() => _VideoEmbedPreviewState();
}

class _VideoEmbedPreviewState extends State<_VideoEmbedPreview> {
  WebViewController? _controller;
  bool _completed = false;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    if (widget.allowRemoteMedia) {
      // Stel het platform-view na de eerste frame samen, net als de Mermaid-host
      // (concurreert dan niet met het opstarten van vensters op macOS).
      WidgetsBinding.instance.addPostFrameCallback((_) => _initWebView());
    }
  }

  @override
  void didUpdateWidget(_VideoEmbedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.slide.videoPath != widget.slide.videoPath ||
        oldWidget.slide.videoStartMs != widget.slide.videoStartMs ||
        oldWidget.slide.videoEndMs != widget.slide.videoEndMs ||
        oldWidget.autoplay != widget.autoplay ||
        oldWidget.allowRemoteMedia != widget.allowRemoteMedia;
    if (!changed) return;
    if (widget.allowRemoteMedia) {
      if (_controller == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _initWebView());
      } else {
        _loadEmbed();
      }
    } else {
      setState(() => _controller = null);
    }
  }

  void _initWebView() {
    if (!mounted || _controller != null) return;
    final origin = widget.source.kind == VideoSourceKind.youtube
        ? 'youtube'
        : 'vimeo';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel('OciDeck', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Sta alleen de eerste lading + navigatie binnen de speler-origins toe;
          // pop-ups en wegnavigeren worden geblokkeerd.
          onNavigationRequest: (request) {
            if (!_initialLoadDone) {
              _initialLoadDone = true;
              return NavigationDecision.navigate;
            }
            final u = request.url;
            final allowed = origin == 'youtube'
                ? (u.contains('youtube.com') ||
                      u.contains('youtube-nocookie.com') ||
                      u.contains('ytimg.com') ||
                      u.contains('google.com'))
                : (u.contains('vimeo.com') || u.contains('vimeocdn.com'));
            return allowed
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onHttpAuthRequest: (request) async {
            // Weiger auth-prompts vanuit de embed.
          },
        ),
      );
    _controller = controller;
    _loadEmbed();
    if (mounted) setState(() {});
  }

  void _loadEmbed() {
    final controller = _controller;
    if (controller == null) return;
    _completed = false;
    final html = _buildEmbedHtml();
    if (html == null) return;
    final baseUrl = widget.source.kind == VideoSourceKind.youtube
        ? 'https://www.youtube-nocookie.com'
        : 'https://player.vimeo.com';
    controller.loadHtmlString(html, baseUrl: baseUrl);
  }

  void _onJsMessage(JavaScriptMessage message) {
    final m = message.message;
    if (m.startsWith('pos:')) {
      final ms = int.tryParse(m.substring(4));
      if (ms != null) {
        VideoPlayheadBus.publish(
          VideoPlayhead(
            slideId: widget.slide.id,
            positionMs: ms,
            durationMs: 0,
          ),
        );
      }
    } else if (m == 'ended') {
      if (_completed) return;
      _completed = true;
      // Video meldt alleen tijdens autoplay (handmatig afspelen mag niet
      // ongevraagd doorbladeren).
      if (widget.autoplay) widget.onComplete?.call();
    }
  }

  String? _buildEmbedHtml() {
    final id = widget.source.embedId;
    if (id == null) return null;
    final startSec = (widget.slide.videoStartMs / 1000).floor();
    final endMs = widget.slide.videoEndMs;
    final auto = widget.autoplay ? 1 : 0;
    if (widget.source.kind == VideoSourceKind.youtube) {
      return _youTubeHtml(id, startSec, endMs, auto);
    }
    final embed = widget.source
        .embedUri(
          startMs: widget.slide.videoStartMs,
          endMs: widget.slide.videoEndMs,
          autoplay: widget.autoplay,
        )
        ?.toString();
    if (embed == null) return null;
    return _vimeoHtml(embed, endMs);
  }

  @override
  void dispose() {
    VideoPlayheadBus.clearFor(widget.slide.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      color: const Color(0xFF000000),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.allowRemoteMedia)
            _remoteBlockedPlaceholder(context, widget.slide.videoPath)
          else if (controller != null)
            WebViewWidget(controller: controller)
          else
            _mediaPlaceholder(Icons.movie_outlined, 'Video'),
          if (widget.slide.title.isNotEmpty)
            Positioned(
              left: widget.w * 0.06,
              right: widget.w * 0.06,
              top: widget.w * 0.04,
              child: IgnorePointer(
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
            ),
        ],
      ),
    );
  }
}

/// HTML voor een YouTube-embed via de IFrame Player API. Bewaakt het knip-einde
/// ([endMs] > 0) en meldt positie/einde via de `OciDeck`-channel.
String _youTubeHtml(String id, int startSec, int endMs, int autoplay) {
  return '''<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;background:#000;height:100%}#p{width:100%;height:100%}</style></head>
<body><div id="p"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player, endMs=$endMs;
function post(m){try{OciDeck.postMessage(m)}catch(e){}}
function onYouTubeIframeAPIReady(){
  player=new YT.Player('p',{videoId:'$id',playerVars:{autoplay:$autoplay,controls:1,rel:0,modestbranding:1,playsinline:1,start:$startSec},events:{onReady:onReady,onStateChange:onState}});
}
function onReady(e){tick()}
function onState(e){if(e.data===YT.PlayerState.ENDED){post('ended')}}
function tick(){try{if(player&&player.getCurrentTime){var ms=Math.round(player.getCurrentTime()*1000);post('pos:'+ms);if(endMs>0&&ms>=endMs){player.pauseVideo();post('ended')}}}catch(e){}setTimeout(tick,250)}
</script></body></html>''';
}

/// HTML voor een Vimeo-embed via player.js. Start gaat via de #t-fragment in
/// [embedUrl]; het knip-einde ([endMs] > 0) wordt in JS bewaakt.
String _vimeoHtml(String embedUrl, int endMs) {
  return '''<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;background:#000;height:100%}iframe{width:100%;height:100%;border:0}</style></head>
<body><iframe id="f" src="$embedUrl" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>
<script src="https://player.vimeo.com/api/player.js"></script>
<script>
var endMs=$endMs;
function post(m){try{OciDeck.postMessage(m)}catch(e){}}
var player=new Vimeo.Player(document.getElementById('f'));
player.on('timeupdate',function(d){var ms=Math.round(d.seconds*1000);post('pos:'+ms);if(endMs>0&&ms>=endMs){player.pause();post('ended')}});
player.on('ended',function(){post('ended')});
</script></body></html>''';
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
  bool trustedAsset = false,
}) {
  if (imagePath.isEmpty) return _imagePlaceholder(context);

  // Online afbeelding: render live via NetworkImage (zelfde decode-cap als
  // bestanden), maar alleen als de remote-media-gate open staat én de URL door
  // de SSRF-gate komt. Anders een placeholder met de URL.
  if (VideoSource.looksLikeUrl(imagePath)) {
    final allowed =
        _SlideLinkScope.allowRemoteMediaOf(context) &&
        VideoSource.isAllowedRemoteUrl(imagePath);
    if (!allowed) return _remoteBlockedPlaceholder(context, imagePath);
    return Image(
      image: cappedNetworkImage(imagePath),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _imagePlaceholder(context),
    );
  }

  // The logo is trusted style-profile config and may live outside the opened
  // deck's project folder; slide images stay project-contained (untrusted deck
  // content must not read arbitrary files).
  final resolved = trustedAsset
      ? resolveTrustedAssetPath(imagePath, projectPath)
      : resolveSlideAssetPath(imagePath, projectPath);
  if (resolved == null) return _imagePlaceholder(context);
  // Block a project-internal symlink that points outside the project (cached,
  // so the per-frame cost is O(1) after the first render of each image).
  if (!trustedAsset &&
      projectPath != null &&
      !isRenderPathContained(resolved, projectPath)) {
    return _imagePlaceholder(context);
  }

  return Image(
    // Cap the decode so a huge-dimensioned (possibly untrusted) image can't
    // exhaust memory; see cappedFileImage / kMaxImageDecodeDimension.
    image: cappedFileImage(File(resolved)),
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

/// Placeholder voor online media die niet live geladen wordt (de remote-media-
/// gate staat uit, of de URL is afgekeurd). Toont de URL zodat de gebruiker ziet
/// waar de media vandaan zou komen, plus een hint dat online media uit staat.
Widget _remoteBlockedPlaceholder(BuildContext context, String url) {
  return Container(
    color: const Color(0xFFE2E8F0),
    padding: const EdgeInsets.all(16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: Color(0xFF94A3B8),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.d('Online media staat uit'),
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            url,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
