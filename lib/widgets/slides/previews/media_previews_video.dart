// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability (video & embed previews (YouTube/Vimeo)); all imports live in the main
// library file. These top-level preview classes/helpers relocate verbatim
// from media_previews.dart — same library, no behaviour change.
part of '../slide_preview.dart';

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
                    tooltip: controller?.value.isPlaying == true
                        ? context.l10n.d('Pauzeren')
                        : context.l10n.d('Afspelen'),
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
