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

/// Waaróm een mediapreview geen (bruikbare) controller heeft, zodat hij een
/// gerichte placeholder kan tonen in plaats van een neutraal, betekenisloos
/// mediavak. `null` zolang er niets misging (geen media, of nog aan het laden).
enum MediaLoadFailure {
  /// De remote-URL is door de SSRF-poort geweigerd (privé/LAN/loopback-doel).
  /// Zelfde geval als bij een afbeelding: "door de beveiliging geweigerd".
  remoteRefused,

  /// De media was toegestaan maar kon niet worden geladen: 404, time-out, een
  /// TLS-fout, of een codec die het platform niet aankan. Zonder dit onderscheid
  /// viel een mislukte remote-video stil terug op een leeg "Video"-vak, niet te
  /// onderscheiden van "nog aan het laden".
  loadError,
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

  /// Waaróm er (nog) geen bruikbare controller is; `null` zolang er niets
  /// misging. De videopreview leest dit om de juiste placeholder te kiezen —
  /// zonder deze reden viel een geweigerde of mislukte remote-video stil terug
  /// op een neutraal "Video"-vak.
  MediaLoadFailure? _loadFailure;
  MediaLoadFailure? get mediaLoadFailure => _loadFailure;

  /// Bumped on every (re)init so an in-flight run that has been superseded by a
  /// newer one (rapid slide switches) can bail and clean up its controller.
  int _initGen = 0;

  // ── Door de subklasse ingevuld ───────────────────────────────────────────

  /// Resolved pad/URL naar de media, of null als er niets te spelen is (of de
  /// remote-media-gate dicht staat). Voor een lokaal bestand is dit een
  /// bestandspad; voor een live URL de URL zelf.
  String? resolveMediaPath();

  /// Of [url] via `resolveDeckAssetUrl` uit de deck-URL zelf kwam (#2282).
  /// Zo'n bron is al door de herkomstgrens (same-origin én binnen de deckmap);
  /// de NetGuard-SSRF-controle hoeft niet nog eens — en zou op web sowieso
  /// weigeren, want dart:io-DNS ontbreekt daar. Subklassen overschrijven dit.
  bool mediaUrlIsDeckAsset(String url) => false;

  /// Of de media automatisch start.
  bool get mediaAutoplay;

  /// Begin/eind van het te spelen segment in milliseconden (het "knippen"). 0 =
  /// vanaf begin / tot natuurlijk einde. Standaard de hele media.
  int get mediaStartMs => 0;
  int get mediaEndMs => 0;

  /// Of het einde van de media gemeld moet worden (voor auto-advance). Audio
  /// meldt altijd; video alleen tijdens autoplay.
  bool get reportsMediaCompletion => true;

  /// De toekomst met het ondertitelbestand voor deze media, of null (#2841).
  /// Alleen de videopreview vult dit in; audio heeft geen captions.
  Future<ClosedCaptionFile>? mediaClosedCaptionFile(String source) => null;

  /// Maakt de controller voor [source]. Een `http(s)`- of `blob:`-bron wordt een
  /// netwerk-controller, anders een bestand-controller. Subklassen hoeven dit
  /// zelden te overschrijven.
  VideoPlayerController createMediaController(String source) {
    // Web: een `mem:`-bron (pakket-media) wordt een `blob:`-URL die als
    // netwerk-URL speelt. Op desktop komt `mem:` hier nooit langs (pakketten
    // pakken naar schijf uit) en levert de helper null (#854).
    final src = WebAssetStore.isMemPath(source)
        ? (memAssetBlobUrl(source) ?? source)
        : source;
    final uri = Uri.tryParse(src);
    final scheme = uri?.scheme.toLowerCase();
    final captions = mediaClosedCaptionFile(src);
    if (uri != null &&
        (scheme == 'http' || scheme == 'https' || scheme == 'blob')) {
      return VideoPlayerController.networkUrl(uri, closedCaptionFile: captions);
    }
    return VideoPlayerController.file(File(src), closedCaptionFile: captions);
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
    _loadFailure = null; // verse poging: elke oude reden vervalt
    final path = resolveMediaPath();
    if (path == null) {
      if (mounted) setState(() {});
      return;
    }
    // SSRF gate for a remote media URL: resolve the host and refuse an internal
    // target before VideoPlayerController.networkUrl, which would otherwise
    // resolve+connect with no host check (see NetGuard.isAllowedRemoteUrlResolved).
    // A URL resolved from the deck URL itself (mediaUrlIsDeckAsset) was already
    // inside that boundary — the user picked that host for the deck.
    if (VideoSource.looksLikeUrl(path) &&
        !await NetGuard.isAllowedRemoteUrlResolved(path)) {
      if (gen != _initGen) return;
      _loadFailure = MediaLoadFailure.remoteRefused;
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
      // Placeholder zichtbaar houden — met een reden, zodat een mislukte
      // remote-video niet als een leeg "Video"-vak leest maar als "kan niet
      // worden geladen".
      _loadFailure = MediaLoadFailure.loadError;
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
  String? resolveMediaPath() {
    // Zelfde reden als bij video (#854): pakket-audio is op web een `mem:`-pad
    // dat [createMediaController] tot een `blob:`-URL maakt. Zonder deze tak
    // geeft resolveSlideAssetPath op web sowieso null.
    final ap = widget.audioPath;
    if (WebAssetStore.isMemPath(ap)) return ap;
    // Deck via URL geopend (#2282): een relatief pad wijst naar een bestand
    // naast het deck op die server — zie [_VideoPreviewState] voor de reden
    // dat dit geen `allowRemoteMedia` vraagt.
    final local = _resolvePath(ap, widget.projectPath);
    if (local != null || widget.projectPath != null) return local;
    if (!SlideLinkScope.allowRemoteMediaOf(context)) return null;
    return resolveDeckAssetUrl(ap, DeckAssetScope.read(context));
  }

  @override
  bool mediaUrlIsDeckAsset(String url) =>
      url ==
      resolveDeckAssetUrl(widget.audioPath, DeckAssetScope.read(context));

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

class _TwoImagesPreview extends StatefulWidget {
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
  State<_TwoImagesPreview> createState() => _TwoImagesPreviewState();
}

class _TwoImagesPreviewState extends State<_TwoImagesPreview> {
  /// De bronverhoudingen (b/h) voor de 'Gelijke hoogte'-weergave (#2867).
  /// `null` = nog niet bekend of niet afleidbaar; de build valt dan terug op
  /// de gewone paneelverdeling in plaats van iets ongeldigs te tekenen.
  double? _aspect1;
  double? _aspect2;

  /// Bumped on every (re)resolve so an in-flight decode that has been
  /// superseded by a path change cannot write a stale ratio.
  int _aspectGen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Niet in initState: de async route leest SlideLinkScope/DeckAssetScope,
    // en inherited widgets mogen daar nog niet gelezen worden. Een gewijzigde
    // scope (andere deck-URL, andere media-gate) herberekent de verhoudingen.
    _resolveAspects();
  }

  @override
  void didUpdateWidget(_TwoImagesPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.imagePath != widget.slide.imagePath ||
        oldWidget.slide.imagePath2 != widget.slide.imagePath2 ||
        oldWidget.slide.twoImagesLayout != widget.slide.twoImagesLayout ||
        oldWidget.projectPath != widget.projectPath) {
      _resolveAspects();
    }
  }

  void _resolveAspects() {
    final gen = ++_aspectGen;
    _aspect1 = _aspectSync(widget.slide.imagePath);
    _aspect2 = _aspectSync(widget.slide.imagePath2);
    if (_aspect1 == null) _resolveAspectAsync(gen, second: false);
    if (_aspect2 == null) _resolveAspectAsync(gen, second: true);
  }

  /// De synchrone routes: `mem:`-bytes en de gecachete headerlezing voor
  /// lokale bestanden (#2685). SVG's dragen hun verhouding in de brontekst.
  /// Bundled assets en remote/deck-URL's hebben geen synchrone route en
  /// vallen hier op `null` — [_resolveAspectAsync] pakt die op.
  double? _aspectSync(String path) {
    if (path.isEmpty) return null;
    if (WebAssetStore.isMemPath(path)) {
      final bytes = WebAssetStore.bytesFor(path);
      if (bytes == null) return null;
      return isSvgImagePath(path)
          ? svgAspectFromBytes(bytes)
          : imageDimensionsFromBytes(bytes)?.aspect;
    }
    // Lokale SVG's gaan óók via de async route: de verhouding staat in de
    // brontekst, en een leesbeurt hoort niet op de UI-isolate thuis.
    if (isBundledAssetPath(path) ||
        VideoSource.looksLikeUrl(path) ||
        isSvgImagePath(path)) {
      return null;
    }
    final resolved = resolveSlideAssetPath(path, widget.projectPath);
    if (resolved == null) return null;
    return readImageDimensions(resolved)?.aspect;
  }

  void _assignAspect(int gen, bool second, double? aspect, bool synchronous) {
    if (aspect == null || gen != _aspectGen) return;
    if (synchronous) {
      if (second) {
        _aspect2 = aspect;
      } else {
        _aspect1 = aspect;
      }
      return;
    }
    if (mounted) {
      setState(() => second ? _aspect2 = aspect : _aspect1 = aspect);
    }
  }

  /// De asynchrone routes: dezelfde image-provider-infrastructuur als de
  /// callout-overlay gebruikt ([calloutImageProvider] + [resolveIntrinsicSize],
  /// ontworpen zodat een cache-hit synchroon terugkomt — dat is wat de
  /// rasterexports nodig hebben om de rij in hún frame te tekenen). Remote en
  /// deck-asset URL's gaan via de netwerkprovider met dezelfde gates als de
  /// weergave zelf; een gebundelde SVG leest zijn verhouding uit de tekst.
  void _resolveAspectAsync(int gen, {required bool second}) {
    final path = second ? widget.slide.imagePath2 : widget.slide.imagePath;
    void done(Size? size, bool synchronous) {
      _assignAspect(
        gen,
        second,
        size == null || size.height <= 0 ? null : size.width / size.height,
        synchronous,
      );
    }

    if (isSvgImagePath(path)) {
      if (isBundledAssetPath(path)) {
        unawaited(
          rootBundle.loadString(bundledAssetKey(path)).then((text) {
            _assignAspect(gen, second, svgAspectFromText(text), false);
          }, onError: (_, _) {}),
        );
        return;
      }
      // Lokale SVG: de eerste 64 KB volstaan — het root-element met
      // width/height/viewBox staat vooraan.
      final resolved = resolveSlideAssetPath(path, widget.projectPath);
      if (resolved == null) return;
      unawaited(() async {
        try {
          final file = await File(resolved).open();
          final bytes = await file.read(64 * 1024);
          await file.close();
          _assignAspect(gen, second, svgAspectFromBytes(bytes), false);
        } catch (e) {
          logError(
            '_TwoImagesPreviewState._resolveAspectAsync: svg head read',
            e,
          );
        }
      }());
      return;
    }
    final provider = calloutImageProvider(path, widget.projectPath);
    if (provider != null) {
      resolveIntrinsicSize(provider, done);
      return;
    }
    if (VideoSource.looksLikeUrl(path)) {
      // Zelfde grens als _resolvedRemoteImage: instelling aan én de URL mag
      // door de SSRF-poort, anders blijft de paneelverdeling de fallback.
      if (!SlideLinkScope.allowRemoteMediaOf(context)) return;
      unawaited(
        NetGuard.isAllowedRemoteUrlResolved(path).then((allowed) {
          if (!allowed || gen != _aspectGen || !mounted) return;
          resolveIntrinsicSize(guardedNetworkImage(path), done);
        }),
      );
      return;
    }
    // Relatief pad in een via URL geopend deck (#2282): opgelost tegen de
    // deck-URL — die host koos de gebruiker zelf, dus geen SSRF-poort.
    final deckAsset = resolveDeckAssetUrl(
      path,
      DeckAssetScope.maybeOf(context),
    );
    if (deckAsset != null) {
      resolveIntrinsicSize(guardedNetworkImage(deckAsset), done);
    }
  }

  Widget _panelRow(BuildContext context) {
    final slide = widget.slide;
    final splitFraction = (slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.5)
        .clamp(0.1, 0.9);
    return Row(
      children: [
        Expanded(
          flex: (splitFraction * 1000).round(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _panelImage(
                context,
                slide.imagePath,
                widget.projectPath,
                slide.imageZoom,
                focalAlignment(slide.imageFocalX, slide.imageFocalY),
                imageSemanticsLabel(
                  context,
                  slide.imageCaption,
                  altText: slide.imageAltText,
                ),
              ),
              _captionOverlay(context, slide.imageCaption, widget.w),
            ],
          ),
        ),
        Expanded(
          flex: ((1 - splitFraction) * 1000).round(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _panelImage(
                context,
                slide.imagePath2,
                widget.projectPath,
                slide.imageZoom,
                focalAlignment(slide.imageFocalX2, slide.imageFocalY2),
                imageSemanticsLabel(
                  context,
                  slide.imageCaption2,
                  altText: slide.imageAltText2,
                ),
              ),
              _captionOverlay(context, slide.imageCaption2, widget.w),
            ],
          ),
        ),
      ],
    );
  }

  /// De 'Gelijke hoogte'-rij (#2867): beide beelden op exact dezelfde
  /// zichtbare hoogte, volledig zichtbaar en onvervormd (contain). Breedtes
  /// volgen de bronverhoudingen; de handmatige verdeling/zoom doet hier
  /// bewust niets. Bijschriften hangen aan hun eigen beeldrechthoek.
  Widget _equalHeightRow(BuildContext context) {
    final slide = widget.slide;
    return LayoutBuilder(
      builder: (context, constraints) {
        final a1 = _aspect1, a2 = _aspect2;
        // De ondertitelbalk ligt over de onderkant heen; in deze modus hoort
        // die geen beeld te bedekken, dus de rij krijgt de ruimte erboven.
        final reserve = slide.title.isNotEmpty ? widget.w * 0.15 : 0.0;
        final row =
            slide.imagePath.isNotEmpty &&
                slide.imagePath2.isNotEmpty &&
                a1 != null &&
                a2 != null
            ? twoImagesEqualHeight(
                aspect1: a1,
                aspect2: a2,
                availW: constraints.maxWidth,
                availH: constraints.maxHeight - reserve,
                gap: widget.w * 0.02,
              )
            : null;
        // Eén ontbrekend beeld, nog ladende of onleesbare afmetingen: de
        // paneelverdeling is de voorspelbare toestand — zij toont ook de
        // placeholders.
        if (row == null) return _panelRow(context);
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _equalImage(
                context,
                slide.imagePath,
                row.leftWidth,
                row.height,
                slide.imageCaption,
                slide.imageAltText,
              ),
              SizedBox(width: row.gap),
              _equalImage(
                context,
                slide.imagePath2,
                row.rightWidth,
                row.height,
                slide.imageCaption2,
                slide.imageAltText2,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _equalImage(
    BuildContext context,
    String path,
    double width,
    double height,
    String caption,
    String altText,
  ) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _resolvedImage(
            context,
            path,
            widget.projectPath,
            fit: BoxFit.contain,
            semanticLabel: imageSemanticsLabel(
              context,
              caption,
              altText: altText,
            ),
          ),
          _captionOverlay(context, caption, widget.w),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    final titleSize = widget.w * 0.032;
    final safe = _mediaBrandStripInsets(widget.w, slide, widget.profile);

    return Container(
      color: _profileSlideBackground(context, widget.profile),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Twee afbeeldingen naast elkaar
          Padding(
            padding: safe,
            child: slide.twoImagesLayout == TwoImagesLayout.equalHeight
                ? _equalHeightRow(context)
                : _panelRow(context),
          ),
          // Optionele ondertitel
          if (slide.title.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: widget.w * 0.04 + safe.bottom,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.w * 0.04,
                  vertical: widget.w * 0.015,
                ),
                child: _md(
                  context,
                  slide.title,
                  _applyFont(
                    widget.font,
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
    if (slide.imageTitleAbove) return _titleAboveLayout(context);
    final hasTitle = slide.title.isNotEmpty;
    final safe = _mediaBrandStripInsets(w, slide, profile);
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: safe,
          child: _zoomedImage(
            context,
            slide.imagePath,
            projectPath,
            slide.imageSize,
            bgColor: AppTheme.parseHexColor(profile.slideBackgroundColor),
            // A focal point (crop) decides which part of the picture stays in
            // view. Without one, keep the old default: when zoomed out, anchor
            // to the top so the bottom title banner sits in the freed-up space.
            alignment: hasCustomFocal(slide.imageFocalX, slide.imageFocalY)
                ? focalAlignment(slide.imageFocalX, slide.imageFocalY)
                : (hasTitle ? Alignment.topCenter : Alignment.center),
            semanticLabel: imageSemanticsLabel(
              context,
              slide.imageCaption,
              altText: slide.imageAltText,
            ),
          ),
        ),
        if (slide.title.isNotEmpty)
          Positioned(
            left: w * 0.06,
            right: w * 0.06,
            bottom: w * 0.06 + safe.bottom,
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

  Widget _titleAboveLayout(BuildContext context) {
    return Padding(
      padding: _mediaBrandStripInsets(w, slide, profile),
      child: Container(
        color: _contentBackground(
          context,
          AppTheme.parseHexColor(profile.slideBackgroundColor),
        ),
        child: Column(
          children: [
            if (slide.title.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  w * 0.06,
                  w * 0.04,
                  w * 0.06,
                  w * 0.02,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _md(
                    context,
                    slide.title,
                    _applyFont(
                      font,
                      TextStyle(
                        color: AppTheme.parseHexColor(profile.textColor),
                        fontSize: w * 0.045,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    linkColor: AppTheme.paleBlue2,
                  ),
                ),
              ),
            if (slide.subtitle.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(w * 0.06, 0, w * 0.06, w * 0.02),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _md(
                    context,
                    slide.subtitle,
                    _applyFont(
                      font,
                      TextStyle(
                        color: AppTheme.parseHexColor(profile.textColor),
                        fontSize: w * 0.026,
                      ),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    linkColor: AppTheme.paleBlue2,
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _resolvedImage(
                    context,
                    slide.imagePath,
                    projectPath,
                    fit: BoxFit.contain,
                    alignment:
                        hasCustomFocal(slide.imageFocalX, slide.imageFocalY)
                        ? focalAlignment(slide.imageFocalX, slide.imageFocalY)
                        : Alignment.center,
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
          ],
        ),
      ),
    );
  }
}

EdgeInsets _mediaBrandStripInsets(double w, Slide slide, ThemeProfile profile) {
  final hasStrip =
      slide.showLogo &&
      profile.brandStripPath?.isNotEmpty == true &&
      profile.brandStripHeight > 0;
  return hasStrip ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
}
