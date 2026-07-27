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
        // Web: een pakket-video leeft als `mem:`-bytes ([WebAssetStore]);
        // [createMediaController] maakt er een `blob:`-URL van. Zonder deze tak
        // geeft resolveSlideAssetPath op web null en speelt lokale video nooit
        // (#854).
        final vp = widget.slide.videoPath;
        if (WebAssetStore.isMemPath(vp)) return vp;
        return _resolvePath(vp, widget.projectPath);
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
        color: AppTheme.parseHexColor(widget.profile.slideBackgroundColor),
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
              _mediaPlaceholder(
                context,
                Icons.movie_outlined,
                context.l10n.d('Video'),
              ),
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
                      color: AppTheme.parseHexColor(widget.profile.textColor),
                      fontSize: widget.w * 0.038,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  linkColor: AppTheme.parseHexColor(widget.profile.accentColor),
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

  /// De reden waarom deze embed niet speelt, of null zolang alles goed gaat.
  /// Zolang dit null is en de speler nog niet "ok" meldde, tonen we de
  /// laad-placeholder; is het gezet, dan de foutmelding met die reden.
  VideoEmbedError? _error;

  /// De speler meldde dat hij klaarstaat. Vóór dat moment is een leeg vlak
  /// "nog aan het laden", niet "stuk" — en dat onderscheid was precies wat de
  /// gebruiker miste.
  bool _playerReady = false;

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
      // Online media net uitgezet: stop de lopende speler vóór we het view
      // loslaten, anders speelt hij door (zie [_stopPlayback]).
      _stopPlayback();
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
            // Onze eigen stop-navigatie bij het verlaten van de dia
            // (zie [_stopPlayback]): een lege pagina sloopt de speler en dempt
            // het geluid. Geen tracking-oorsprong, dus die mag altijd door.
            if (u == 'about:blank') return NavigationDecision.navigate;
            final allowed = origin == 'youtube'
                ? youTubePlayerNavigationAllowed(u)
                : vimeoPlayerNavigationAllowed(u);
            return allowed
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onHttpAuthRequest: (request) async {
            // Weiger auth-prompts vanuit de embed.
          },
          // Alleen een fout op de hóófdlading telt hier als netwerkfout. Een
          // embed laadt tientallen subresources (het IFrame-script, thumbnails,
          // tracking) die los mogen mislukken zonder dat de video stuk is; die
          // hebben `isForMainFrame == false` en negeren we. Bij twijfel (null)
          // zwijgen we ook — de JS-timeout in de embed-HTML is het echte vangnet
          // voor "de speler kwam nooit klaar", en die maakt geen vals alarm.
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              _reportError(VideoEmbedError.network);
            }
          },
        ),
      );
    _setEmbedBackground(controller);
    _controller = controller;
    _loadEmbed();
    if (mounted) setState(() {});
  }

  /// Een zwarte achtergrond onder de speler — puur cosmetisch, en niet overal
  /// geïmplementeerd: op macOS gooit `setBackgroundColor` een
  /// `UnimplementedError` ("opaque is not implemented on macOS"). Zolang die
  /// aanroep in de cascade van [_initWebView] stond, sneuvelde daarmee de héle
  /// controller-opbouw: `_controller` bleef null, en de embed kwam nooit verder
  /// dan de "Video"-placeholder. Een YouTube- of Vimeo-video speelde op macOS
  /// dus simpelweg nooit af.
  ///
  /// De kleur mag falen: de embed-HTML zet zelf al `background:#000`, en de
  /// speler vult het vlak. Alleen de video mag niet aan de kleur onderdoorgaan.
  void _setEmbedBackground(WebViewController controller) {
    try {
      controller.setBackgroundColor(Colors.black);
    } on UnimplementedError catch (e) {
      logWarning(
        '_VideoEmbedPreviewState._initWebView: '
        'setBackgroundColor unsupported on this platform',
        e,
      );
    }
  }

  void _loadEmbed() {
    final controller = _controller;
    if (controller == null) return;
    _completed = false;
    // Een nieuwe lading is een schone lei: de vorige fout en klaar-status horen
    // niet mee te reizen naar een andere video op dezelfde slide.
    if (_error != null || _playerReady) {
      setState(() {
        _error = null;
        _playerReady = false;
      });
    }
    final html = _buildEmbedHtml();
    if (html == null) return;
    final baseUrl = widget.source.kind == VideoSourceKind.youtube
        ? kYouTubeEmbedOrigin
        : 'https://player.vimeo.com';
    controller.loadHtmlString(html, baseUrl: baseUrl);
  }

  void _onJsMessage(JavaScriptMessage message) {
    final m = message.message;
    if (m.startsWith('pos:')) {
      final ms = int.tryParse(m.substring(4));
      if (ms != null) {
        if (!_playerReady) setState(() => _playerReady = true);
        VideoPlayheadBus.publish(
          VideoPlayhead(
            slideId: widget.slide.id,
            positionMs: ms,
            durationMs: 0,
          ),
        );
      }
    } else if (m == 'ok') {
      if (!_playerReady || _error != null) {
        setState(() {
          _playerReady = true;
          _error = null;
        });
      }
    } else if (m.startsWith('err:')) {
      _reportError(videoEmbedErrorFromCode(m.substring(4)));
    } else if (m == 'ended') {
      if (_completed) return;
      _completed = true;
      // Video meldt alleen tijdens autoplay (handmatig afspelen mag niet
      // ongevraagd doorbladeren).
      if (widget.autoplay) widget.onComplete?.call();
    }
  }

  /// Een speler die eerst "ok" meldde en daarna een fout, is meestal een clip
  /// die middenin stokt; de gebruiker heeft dan al beeld gehad. De reden die de
  /// gebruiker mist is de fout die vóór het spelen komt (insluiten uit, video
  /// weg, geen verbinding), dus die laten we winnen.
  void _reportError(VideoEmbedError error) {
    if (!mounted || _playerReady || _error != null) return;
    setState(() => _error = error);
  }

  String? _buildEmbedHtml() {
    // `embedUri` levert null zodra er geen embed-id is, dus die ene bron is de
    // hele bewaking; beide spelers bouwen nu op dezelfde URL.
    final endMs = widget.slide.videoEndMs;
    final embed = widget.source
        .embedUri(
          startMs: widget.slide.videoStartMs,
          endMs: widget.slide.videoEndMs,
          autoplay: widget.autoplay,
        )
        ?.toString();
    if (embed == null) return null;
    return widget.source.kind == VideoSourceKind.youtube
        ? _youTubeHtml(embed, endMs)
        : _vimeoHtml(embed, endMs);
  }

  @override
  void dispose() {
    _stopPlayback();
    VideoPlayheadBus.clearFor(widget.slide.id);
    super.dispose();
  }

  /// Stopt de speler wanneer de dia wordt verlaten.
  ///
  /// Alleen de widget uit de boom halen dempt het geluid niet: op macOS
  /// (WKWebView) wordt het platform-view niet meteen vrijgegeven en speelt de
  /// YouTube/Vimeo-embed dóór nadat je naar de volgende dia bent. We navigeren
  /// de webview daarom naar een lege pagina; dat sloopt de speler en daarmee
  /// zijn geluid, meteen — nog vóór het view wordt afgebroken. Fire-and-forget:
  /// in `dispose` valt er niets te awaiten, en een fout betekent dat het view al
  /// weg is, dus dan speelt er ook niets meer.
  void _stopPlayback() {
    final controller = _controller;
    if (controller == null) return;
    controller.loadRequest(Uri.parse('about:blank')).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.allowRemoteMedia)
            _remoteBlockedPlaceholder(context, widget.slide.videoPath)
          else if (_error != null)
            _videoEmbedErrorPlaceholder(
              context,
              _error!,
              widget.slide.videoPath,
            )
          else if (controller != null) ...[
            WebViewWidget(controller: controller),
            // De speler zit al in beeld, maar meldde nog geen positie of "ok".
            // Toon zolang een subtiele laadhint zodat een trage lading niet met
            // een dood vlak wordt verward.
            if (!_playerReady) const IgnorePointer(child: _VideoEmbedLoading()),
          ] else
            _mediaPlaceholder(
              context,
              Icons.movie_outlined,
              context.l10n.d('Video'),
            ),
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
                      color: AppTheme.parseHexColor(widget.profile.textColor),
                      fontSize: widget.w * 0.038,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  linkColor: AppTheme.parseHexColor(widget.profile.accentColor),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// De enige oorsprong die een YouTube-embed van OciDeck mag aanspreken.
///
/// `youtube-nocookie.com` is de variant die pas een profiel opbouwt als er
/// werkelijk gekeken wordt; `youtube.com` volgt de bezoeker vanaf de eerste
/// byte. Elders in de code werd de nocookie-vorm al netjes gebruikt — behalve
/// hier, waar het speler-script van de trackende oorsprong kwam en de speler
/// zelf daarmee óók daar terechtkwam. Eén constante, zodat dat niet opnieuw
/// uiteen kan lopen.
const String kYouTubeEmbedOrigin = 'https://www.youtube-nocookie.com';

/// Of de speler naar [url] mag navigeren.
///
/// De speler zelf en zijn beeldmateriaal mogen; `www.youtube.com` mag niet.
/// Dat lijkt streng tot je ziet waar die navigatie vandaan komt: het YouTube-
/// logo in de speler is een link naar de kijkpagina. Eén klik daarop tijdens
/// een presentatie verving de dia door de trackende oorsprong — precies wat de
/// nocookie-variant moest voorkomen — en liet de presentator achter op een
/// pagina die niet zijn presentatie is. Weigeren doet allebei die dingen niet.
///
/// Let op de vorm: dit toetst de hóst, niet "komt deze tekenreeks ergens voor".
/// Met een `contains` zou `https://youtube.com.kwaadaardig.example/` erdoor
/// glippen.
@visibleForTesting
bool youTubePlayerNavigationAllowed(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  const players = {
    'youtube-nocookie.com', // de speler zelf
    'ytimg.com', // miniaturen en speler-assets
    'googlevideo.com', // de videostroom
  };
  return players.any((d) => host == d || host.endsWith('.$d'));
}

/// Dezelfde toets voor Vimeo, en om dezelfde reden.
///
/// Hier stond een `contains('vimeo.com')`, terwijl het commentaar bij de
/// YouTube-variant hierboven precies uitlegt waarom dat niet deugt:
/// `https://vimeo.com.kwaadaardig.example/` bevat de tekenreeks en zou dus
/// navigeren. De redenering was gemaakt en op één van de twee takken toegepast.
@visibleForTesting
bool vimeoPlayerNavigationAllowed(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  const players = {
    'player.vimeo.com', // de speler zelf
    'vimeo.com', // de embed-pagina
    'vimeocdn.com', // miniaturen, speler-assets en de videostroom
  };
  return players.any((d) => host == d || host.endsWith('.$d'));
}

/// HTML voor een YouTube-embed: een kále `youtube-nocookie`-iframe, precies
/// zoals de Vimeo-embed.
///
/// Er komt geen script meer van YouTube aan te pas. Dat was de vorige opzet
/// (`www.youtube.com/iframe_api`) en die had twee gaten tegelijk: het script
/// zelf kwam van de trackende oorsprong, én `YT.Player` bouwde daarmee een
/// speler-iframe op `www.youtube.com` in plaats van op de nocookie-variant. De
/// gebruiker die "online media" aanzette voor één video, gaf daarmee ongemerkt
/// een bezoek aan het domein dat wél volgt.
///
/// Wat het script deed, kan de speler zelf: `start`, `end`, `autoplay` en
/// `rel` zitten al in de embed-URL ([VideoSource.embedUri]), en de
/// gebeurtenissen (klaar, fout, einde, positie) komen via het postMessage-kanaal
/// dat de speler met `enablejsapi=1` opent — hetzelfde kanaal waar het
/// IFrame-script zelf een omhulsel omheen is.
///
/// Drie meldpaden, in oplopende wanhoop:
/// * de speler meldt zelf (`onReady`, `onError`, `infoDelivery`) — het normale
///   geval, en de enige die `err:<code>` kan opleveren (101/150 = insluiten
///   staat uit, verreweg de vaakste oorzaak van "hij laadt niet");
/// * het iframe laadt wél maar de speler zwijgt: na een korte marge melden we
///   `ok`, zodat er geen valse fout over een video komt die gewoon speelt;
/// * er laadt niets: `err:noapi`, in plaats van een zwart vlak zonder reden.
String _youTubeHtml(String embedUrl, int endMs) {
  return '''<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;background:#000;height:100%}iframe{width:100%;height:100%;border:0}</style></head>
<body><iframe id="f" src="$embedUrl" allow="autoplay; fullscreen; encrypted-media; picture-in-picture" allowfullscreen></iframe>
<script>
var endMs=$endMs, ready=false, ended=false, f=document.getElementById('f');
function post(m){try{OciDeck.postMessage(m)}catch(e){}}
function send(o){try{f.contentWindow.postMessage(JSON.stringify(o),'$kYouTubeEmbedOrigin')}catch(e){}}
// De speler stuurt pas gebeurtenissen zodra hij een luisteraar kent. Blijven
// aankloppen tot dat lukt: het iframe kan nog bezig zijn.
function listen(){send({event:'listening',id:1,channel:'ocideck'})}
function markReady(){if(!ready){ready=true;post('ok')}}
function finish(){if(!ended){ended=true;post('ended')}}
var tries=0, poke=setInterval(function(){listen();if(++tries>40||ready){clearInterval(poke)}},250);
f.addEventListener('load',function(){listen();setTimeout(markReady,3000)});
window.addEventListener('message',function(e){
  if(e.origin!=='$kYouTubeEmbedOrigin'){return}
  var d;try{d=(typeof e.data==='string')?JSON.parse(e.data):e.data}catch(x){return}
  if(!d||!d.event){return}
  if(d.event==='onReady'||d.event==='initialDelivery'){markReady()}
  else if(d.event==='onError'){post('err:'+d.info)}
  else if(d.event==='onStateChange'&&d.info===0){finish()}
  else if(d.event==='infoDelivery'&&d.info){
    markReady();
    if(typeof d.info.currentTime==='number'){
      var ms=Math.round(d.info.currentTime*1000);
      post('pos:'+ms);
      if(endMs>0&&ms>=endMs){send({event:'command',func:'pauseVideo',args:[],id:1,channel:'ocideck'});finish()}
    }
    if(d.info.playerState===0){finish()}
  }
});
// Laadt er helemaal niets (offline, geblokkeerd), dan komt de speler nooit
// klaar. Meld dat na een royale marge in plaats van zwart te blijven.
setTimeout(function(){if(!ready){post('err:noapi')}},8000);
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
var endMs=$endMs, ready=false;
function post(m){try{OciDeck.postMessage(m)}catch(e){}}
if(window.Vimeo){
  var player=new Vimeo.Player(document.getElementById('f'));
  player.on('timeupdate',function(d){ready=true;var ms=Math.round(d.seconds*1000);post('pos:'+ms);if(endMs>0&&ms>=endMs){player.pause();post('ended')}});
  player.on('loaded',function(){ready=true;post('ok')});
  player.on('ended',function(){post('ended')});
  player.on('error',function(e){post('err:'+((e&&e.name)||'vimeo'))});
} else { post('err:noapi'); }
setTimeout(function(){if(!ready){post('err:noapi')}},8000);
</script></body></html>''';
}

/// Waaróm een online video niet speelt. Elke waarde krijgt een eigen icoon en
/// tekst, zodat de gebruiker niet naar een zwart vlak hoeft te raden.
enum VideoEmbedError {
  /// De eigenaar staat insluiten van deze video niet toe (YouTube 101/150).
  /// Verreweg de meest voorkomende oorzaak van "hij laadt niet".
  embeddingDisabled,

  /// De video bestaat niet meer, is privé of op deze URL niet te vinden
  /// (YouTube 100, Vimeo not found).
  unavailable,

  /// De video-URL zelf deugt niet (YouTube 2/5).
  invalid,

  /// Geen verbinding met de videobron: netwerkfout, DNS, of de speler-API die
  /// niet laadt.
  network,
}

/// Vertaalt een `err:<code>` uit de embed-HTML naar een [VideoEmbedError].
///
/// De YouTube IFrame-API-codes: 2 = ongeldige parameter, 5 = HTML5-fout,
/// 100 = niet gevonden/privé, 101 & 150 = insluiten door de eigenaar uitgezet.
/// Vimeo meldt een foutnaam; `noapi` is onze eigen code voor "speler-API laadde
/// niet". Onbekende codes vallen naar [VideoEmbedError.network], de meest
/// neutrale reden ("er ging iets mis met de bron").
VideoEmbedError videoEmbedErrorFromCode(String code) {
  switch (code) {
    case '101':
    case '150':
      return VideoEmbedError.embeddingDisabled;
    case '100':
    case 'PrivacyError':
    case 'PasswordError':
    case 'NotFoundError':
      return VideoEmbedError.unavailable;
    case '2':
    case '5':
      return VideoEmbedError.invalid;
    case 'noapi':
    default:
      return VideoEmbedError.network;
  }
}

/// Icoon, titel en detailregel per foutsoort. Publiek zodat een test kan
/// bewaken dat elke oorzaak een eigen, herkenbare reden krijgt.
({IconData icon, String title, String detail}) videoEmbedErrorContent(
  AppLocalizations l10n,
  VideoEmbedError error,
) {
  return switch (error) {
    VideoEmbedError.embeddingDisabled => (
      icon: Icons.lock_outline,
      title: l10n.d('De eigenaar staat insluiten niet toe'),
      detail: l10n.d('Deze video is alleen op de bron zelf te bekijken.'),
    ),
    VideoEmbedError.unavailable => (
      icon: Icons.videocam_off_outlined,
      title: l10n.d('Video niet gevonden'),
      detail: l10n.d('De video is verwijderd, privé of de link klopt niet.'),
    ),
    VideoEmbedError.invalid => (
      icon: Icons.link_off_outlined,
      title: l10n.d('Ongeldige video-link'),
      detail: l10n.d('Controleer de URL van de video op deze slide.'),
    ),
    VideoEmbedError.network => (
      icon: Icons.wifi_off_outlined,
      title: l10n.d('Geen verbinding met de videobron'),
      detail: l10n.d('Controleer de internetverbinding en probeer opnieuw.'),
    ),
  };
}

/// Het zichtbare "waarom speelt dit niet"-vlak. Vervangt het dode zwart-of-grijs
/// dat elke faalmodus vroeger op één hoop gooide.
Widget _videoEmbedErrorPlaceholder(
  BuildContext context,
  VideoEmbedError error,
  String url,
) {
  final content = videoEmbedErrorContent(context.l10n, error);
  return Container(
    color: AppTheme.slideRuleSoft,
    padding: const EdgeInsets.all(16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(content.icon, color: AppTheme.slideInkFaint, size: 32),
          const SizedBox(height: 8),
          Text(
            content.title,
            style: TextStyle(
              color: AppTheme.slideInkMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            content.detail,
            style: TextStyle(color: AppTheme.slideInkSoft, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            url,
            style: TextStyle(color: AppTheme.slideInkFaint, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

/// Een discrete laadhint over de nog-lege speler: een online video kost even,
/// en zonder deze hint is die tussentijd niet te onderscheiden van "stuk".
class _VideoEmbedLoading extends StatelessWidget {
  const _VideoEmbedLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(Colors.white70),
        ),
      ),
    );
  }
}
