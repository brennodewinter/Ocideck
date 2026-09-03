import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import '../models/cvss_builder.dart';
import '../models/deck.dart';
import '../models/improvement_y01.dart';
import '../models/marp_style.dart';
import '../models/document_signature.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import 'privacy/privacy_projection.dart';
import 'web_asset_store.dart';
import '../utils/bundled_asset.dart';
import '../utils/image_limits.dart';
import '../utils/project_path.dart';
import 'finding_context_score.dart';
import 'slide_image_refs.dart';
import 'slide_layout_metrics.dart';
import '../widgets/document_signature_view.dart'
    show decodeEmbeddedSignatureImage;
import '../widgets/slides/slide_preview.dart';
import '../theme/brand_logo.dart';

/// De export kon geen frame krijgen om de dia in te tekenen.
///
/// Rasteren gebeurt door de échte voorvertoning te laten tekenen en het
/// resultaat vast te leggen. Dat kan alleen als de engine frames aflevert, en
/// dat doet ze niet wanneer het venster niet zichtbaar is — geminimaliseerd,
/// achter een ander venster, of op een andere Space. Voorheen bleef de export
/// daar oneindig in hangen zonder één teken van leven.
class SlideRasterizerNoFrameException implements Exception {
  const SlideRasterizerNoFrameException(this.waited);

  /// Hoe lang er tevergeefs op een frame is gewacht.
  final Duration waited;

  @override
  String toString() =>
      'SlideRasterizerNoFrameException: geen frame na ${waited.inSeconds}s. '
      'Rasteren vereist een zichtbaar venster; houd het tijdens de export op '
      'de voorgrond.';
}

/// Bovengrens op de geschatte totale renderbytes van één raster-export.
///
/// De rasterizer houdt alle gerenderde PNG's in een lijst vast en verhoogt de
/// image-cache tot 1 GB; PDF/PPTX-assemblage begint pas als álles gerasteriseerd
/// is. Honderden hoog-entropische dia's kunnen zo meerdere gigabytes aan renders
/// tegelijk vasthouden (#1047). Boven dit onderbouwde totaalbudget weigert de
/// export vóóraf — vóór er ook maar één dia getekend is — met een duidelijke
/// melding, in plaats van gaandeweg het geheugen uit te putten. De schatting is
/// een bovengrens: `dia's × breedte × hoogte × 4` (rauwe RGBA per capture; de
/// PNG is doorgaans kleiner). 4 GiB laat een royaal deck toe en vangt alleen het
/// pathologische geval.
const int kMaxRasterExportBytes = 4 * 1024 * 1024 * 1024; // 4 GiB

/// Gegooid wanneer een raster-export [kMaxRasterExportBytes] zou overschrijden.
/// De UI vertaalt dit via `userFacingError`.
class RasterExportBudgetExceeded implements Exception {
  const RasterExportBudgetExceeded({
    required this.slideCount,
    required this.estimatedBytes,
    required this.limitBytes,
  });

  /// Aantal dia's in de geweigerde export.
  final int slideCount;

  /// De geschatte totale renderbytes (bovengrens).
  final int estimatedBytes;

  /// Het plafond ([kMaxRasterExportBytes], tenzij overschreven).
  final int limitBytes;

  @override
  String toString() =>
      'RasterExportBudgetExceeded(slides: $slideCount, '
      'estimated: $estimatedBytes, limit: $limitBytes)';
}

/// Renders the exact on-screen slide previews to PNG images so exports look
/// identical to what the user sees (WYSIWYG).
///
/// Slides are mounted once in a persistent off-screen [OverlayEntry] and updated
/// in place between captures, which avoids rebuilding the whole preview tree
/// for every slide.
class SlideRasterizer {
  /// Logical size used while laying out a slide. The real output resolution is
  /// [logicalSize] * [pixelRatio]; because the preview is fully proportional
  /// the logical size only affects sampling quality.
  static const Size logicalSize = Size(1280, 720);

  /// Hoe lang op één frame gewacht wordt voor de export opgeeft.
  ///
  /// Ruim genoeg voor een trage debug-build met zware dia's, kort genoeg dat
  /// niemand naar een bevroren balk zit te kijken zonder te weten waarom.
  static const Duration frameTimeout = Duration(seconds: 20);

  /// Wacht op een getekend frame — met een grens.
  ///
  /// Twee dingen die [WidgetsBinding.endOfFrame] alléén niet geeft:
  ///
  /// 1. **Een frame wordt afgedwongen.** `endOfFrame` lost pas op als er een
  ///    frame ís; het plant er zelf geen. Zonder `scheduleFrame` hangt het
  ///    wachten af van of iets ánders toevallig om een frame vroeg.
  /// 2. **Het wachten eindigt.** Levert de engine niets — venster onzichtbaar,
  ///    door het besturingssysteem afgeknepen — dan komt `endOfFrame` nooit
  ///    terug. Oneindig wachten zonder terugkoppeling is de slechtste
  ///    faalvorm die er is: de gebruiker ziet een export die niets doet en
  ///    niets zegt. Liever een nette fout die vertelt wat eraan scheelt.
  static Future<void> _awaitFrame(Duration timeout) async {
    WidgetsBinding.instance.scheduleFrame();
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(timeout);
    } on TimeoutException {
      throw SlideRasterizerNoFrameException(timeout);
    }
  }

  /// Render [audience] to PNG bytes at [targetWidth] x (targetWidth * 9/16).
  ///
  /// Neemt bewust een [AudienceDeck] en geen rauwe slides: rasteren is een
  /// ontvangend oppervlak (de pixels worden een PDF, een PPTX, of het
  /// klembord), en de projectiegrens hoort dus in het typesysteem te staan en
  /// niet in een afspraak. Zie `PrivacyProjection`.
  static Future<List<Uint8List>> rasterize({
    required BuildContext context,
    required AudienceDeck audience,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    bool showClassificationWatermark = false,
    int targetWidth = 1920,
    void Function(int done, int total)? onProgress,
    void Function(String phase, int done, int total)? onStage,
    // Polled tussen slides: true = stoppen. Een afgebroken export levert dan
    // een lege lijst op — de deels verzamelde renders worden opgeruimd zodat er
    // niets blijft rondslingeren (#1047).
    bool Function()? isCancelled,
    // Injecteerbaar zodat de blokkade-weg toetsbaar is: met de echte 20s zou
    // elke test die hem raakt twintig seconden stilstaan.
    Duration frameTimeout = SlideRasterizer.frameTimeout,
    // Injecteerbaar zodat de budgetweigering toetsbaar is zonder een deck van
    // honderden dia's te hoeven bouwen.
    int maxExportBytes = kMaxRasterExportBytes,
  }) async {
    final slides = audience.slides;
    if (slides.isEmpty) return const [];

    _enforceExportBudget(
      slideCount: slides.length,
      targetWidth: targetWidth,
      maxExportBytes: maxExportBytes,
    );

    // Alles wat de render nodig heeft, komt uit het geprojecteerde deck — niet
    // uit los meegegeven velden die per ongeluk van de bron konden komen.
    final deck = audience.deck;
    final themeProfile = deck.themeProfile;
    final projectPath = deck.projectPath;
    final signature = deck.signature;

    final overlay = Overlay.of(context, rootOverlay: true);
    final pixelRatio = targetWidth / logicalSize.width;

    // The global image cache has a modest default budget (~100 MB / 1000
    // entries). A deck with several full-resolution photos blows past that, so
    // images decoded for earlier slides get evicted before later slides are
    // captured — which made every image vanish after the first handful of
    // slides. Raise the budget for the duration of the export, then restore it.
    final imageCache = PaintingBinding.instance.imageCache;
    final prevMaxSize = imageCache.maximumSize;
    final prevMaxBytes = imageCache.maximumSizeBytes;
    imageCache.maximumSize = (slides.length * 4) + 64;
    imageCache.maximumSizeBytes = 1024 * 1024 * 1024; // 1 GB

    // The logo is trusted style-profile config (not deck content), so it may
    // live outside the project — unlike slide images, which stay contained.
    // Een `asset:`-logo (ingebouwd profiel) heeft geen bestandsresolutie.
    // #1931: effectiveSlideLogoPath kiest de donkere variant op een donkere
    // dia-achtergrond (gebundeld merk-logo automatisch, eigen logo via
    // logoDarkPath).
    final rawLogo = effectiveSlideLogoPath(themeProfile) ?? '';
    final logo = isBundledAssetPath(rawLogo)
        ? rawLogo
        : resolveTrustedAssetPath(rawLogo, projectPath);
    // Élke afbeelding van de dia wordt voorgeladen, ook een `![…](…)` in de
    // vrije tekst: zonder precache is de afbeelding nog niet gedecodeerd op het
    // moment dat het beeldje wordt vastgelegd, en belandt er een leeg vak in de
    // PDF of PPTX.
    final allPaths = <String>{
      ?logo,
      for (final slide in slides)
        for (final path in slideImagePaths(slide))
          ?_resolveOrMem(path, projectPath),
    };

    final repaintKey = GlobalKey();
    final hostKey = GlobalKey<_RasterSlideHostState>();
    final entry = _buildRasterOverlayEntry(
      hostKey: hostKey,
      repaintKey: repaintKey,
      audience: audience,
      cockpitColorScheme: cockpitColorScheme,
      showClassificationWatermark: showClassificationWatermark,
    );

    final results = <Uint8List>[];
    var cancelled = false;
    try {
      overlay.insert(entry);
      // De eerste melding staat vóór het eerste wachten, en dat is opzet.
      // Stond hij erna, dan zag de gebruiker bij een blokkade hier helemaal
      // niets: geen fase, geen teller, geen fout — alleen een export die stil
      // bleef staan. Nu is minstens zichtbaar dát er begonnen is.
      onStage?.call('precache', 0, allPaths.length);
      await _awaitFrame(frameTimeout);
      if (!context.mounted) return results;

      await _precachePathsBatched(
        context,
        allPaths,
        onProgress: (done, total) => onStage?.call('precache', done, total),
      );
      if (!context.mounted) return results;

      // The sign-off's drawn signature is a deck-level embedded image, not a
      // slide path — precache it so it paints on the first captured frame
      // instead of decoding a beat too late.
      await _precacheSignatureImage(context, signature);
      if (!context.mounted) return results;

      final numberStarts = numberedListStarts(slides);
      for (var i = 0; i < slides.length; i++) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          break;
        }
        onStage?.call('prepare', i, slides.length);
        hostKey.currentState!.showSlide(
          slides[i],
          i + 1,
          numberStart: numberStarts[i],
          fitScaleOverride: sharedSplitFitScale(
            slides,
            i,
            themeProfile,
            themeProfile.fontFamily,
          ),
          splitRunPosition: splitRunPositionFor(slides, i),
        );
        if (!context.mounted) break;

        onStage?.call('render', i, slides.length);
        final png = await _capture(repaintKey, pixelRatio, frameTimeout);
        results.add(png);

        onStage?.call('done', i + 1, slides.length);
        onProgress?.call(i + 1, slides.length);
      }
    } finally {
      entry.remove();
      imageCache.maximumSize = prevMaxSize;
      imageCache.maximumSizeBytes = prevMaxBytes;
      // Ruim de tijdens de export gedecodeerde afbeeldingen meteen op in plaats
      // van ze in de (nu weer kleine) cache te laten uitzweven; ze zijn na de
      // capture niet meer nodig. Bij annulering gaan ook de deels verzamelde
      // renders eraan, zodat een afgebroken export niets laat rondslingeren.
      imageCache.clear();
      imageCache.clearLiveImages();
      if (cancelled) results.clear();
    }
    return results;
  }

  /// Weigert een export vóóraf op een onderbouwd totaalbudget: honderden
  /// hoog-entropische dia's zouden anders gaandeweg gigabytes aan renders
  /// vasthouden vóór de PDF/PPTX-assemblage begint (#1047). De schatting is een
  /// bovengrens op de rauwe capture per dia; hier is nog niets getekend, dus de
  /// weigering kost geen geheugen.
  static void _enforceExportBudget({
    required int slideCount,
    required int targetWidth,
    required int maxExportBytes,
  }) {
    final targetHeight = (targetWidth * logicalSize.height / logicalSize.width)
        .round();
    final estimatedBytes = slideCount * targetWidth * targetHeight * 4;
    if (estimatedBytes > maxExportBytes) {
      throw RasterExportBudgetExceeded(
        slideCount: slideCount,
        estimatedBytes: estimatedBytes,
        limitBytes: maxExportBytes,
      );
    }
  }

  /// Bouwt de off-screen overlay-entry die het te rasteren dia-oppervlak host.
  /// Uitgesplitst uit [rasterize] zodat die methode onder de lengte-ratchet
  /// blijft; alle velden komen uit het geprojecteerde [audience]-deck.
  static OverlayEntry _buildRasterOverlayEntry({
    required GlobalKey<_RasterSlideHostState> hostKey,
    required GlobalKey repaintKey,
    required AudienceDeck audience,
    required CockpitColorScheme cockpitColorScheme,
    required bool showClassificationWatermark,
  }) {
    final deck = audience.deck;
    final slides = audience.slides;
    return OverlayEntry(
      builder: (_) => Positioned(
        left: -logicalSize.width - 100,
        top: -logicalSize.height - 100,
        child: _RasterSlideHost(
          key: hostKey,
          repaintKey: repaintKey,
          initialSlide: slides.first,
          projectPath: deck.projectPath,
          themeProfile: deck.themeProfile,
          deckMarpStyle: deck.marpStyle,
          cockpitColorScheme: cockpitColorScheme,
          slideCount: slides.length,
          signature: deck.signature,
          sealedAt: deck.sealAt,
          tlp: deck.tlp,
          showClassificationWatermark: showClassificationWatermark,
          organization: deck.organization,
          scopeCia: deckScopeCiaIndex(slides),
          reportLanguage: deck.language,
          improvementY01: deck.improvementY01Metric,
        ),
      ),
    );
  }

  /// Precache the deck's drawn sign-off signature (a deck-level embedded image,
  /// via the same stable-bytes MemoryImage the preview uses) so it paints on the
  /// first captured frame. No-op when the deck is unsigned.
  static Future<void> _precacheSignatureImage(
    BuildContext context,
    DocumentSignature? signature,
  ) async {
    if (signature == null) return;
    final sigBytes = decodeEmbeddedSignatureImage(signature.imagePath);
    if (sigBytes == null) return;
    await precacheImage(
      cappedMemoryImage(sigBytes),
      context,
      onError: (_, _) {},
    );
  }

  static Future<Uint8List> _capture(
    GlobalKey key,
    double pixelRatio,
    Duration frameTimeout,
  ) async {
    await _awaitFrame(frameTimeout);
    RenderRepaintBoundary? boundary;
    for (var attempt = 0; attempt < 12; attempt++) {
      final obj = key.currentContext?.findRenderObject();
      if (obj is RenderRepaintBoundary && !obj.debugNeedsPaint) {
        boundary = obj;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    boundary ??=
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Decode image paths in small parallel batches so the UI stays responsive
  /// and progress can be reported.
  static Future<void> _precachePathsBatched(
    BuildContext context,
    Iterable<String> paths, {
    void Function(int done, int total)? onProgress,
  }) async {
    // Op web zijn er geen lokale bestandspaden — alleen al het construeren
    // van een dart:io File gooit daar. `mem:`-paden (WebAssetStore) en
    // `asset:`-paden (gebundelde logo's) worden wél voorgeladen, zodat de
    // capture niet vóór de eerste decode valt.
    final list = paths
        .where(
          (path) =>
              !kIsWeb ||
              WebAssetStore.isMemPath(path) ||
              isBundledAssetPath(path),
        )
        .toList();
    if (list.isEmpty) return;
    const batchSize = 4;
    var done = 0;
    ImageProvider providerFor(String path) {
      if (isBundledAssetPath(path)) {
        return cappedBundledAssetImage(bundledAssetKey(path));
      }
      final memBytes = WebAssetStore.isMemPath(path)
          ? WebAssetStore.bytesFor(path)
          : null;
      return memBytes != null
          ? cappedMemoryImage(memBytes)
          : cappedFileImage(File(path));
    }

    for (var i = 0; i < list.length; i += batchSize) {
      if (!context.mounted) return;
      final batch = list.skip(i).take(batchSize);
      await Future.wait(
        batch.map(
          (path) =>
              precacheImage(providerFor(path), context, onError: (_, _) {}),
        ),
      );
      done += batch.length;
      onProgress?.call(done, list.length);
      await Future<void>.delayed(Duration.zero);
    }
  }

  // Route through the shared containment guard so an untrusted deck can't make
  // the export precache read files outside the project via absolute or `../`
  // image paths. `mem:`-paden (WebAssetStore) hebben geen bestandsresolutie
  // nodig en gaan er ongewijzigd doorheen.
  static String? _resolveOrMem(String imagePath, String? projectPath) =>
      WebAssetStore.isMemPath(imagePath)
      ? imagePath
      : resolveSlideAssetPath(imagePath, projectPath);
}

class _RasterSlideHost extends StatefulWidget {
  final GlobalKey repaintKey;
  final Slide initialSlide;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final MarpStyle deckMarpStyle;
  final CockpitColorScheme cockpitColorScheme;
  final int slideCount;
  final DocumentSignature? signature;
  final String sealedAt;
  final TlpLevel tlp;
  final bool showClassificationWatermark;
  final String organization;
  final String reportLanguage;
  final Map<String, CiaRating> scopeCia;
  final ImprovementY01Metric improvementY01;

  const _RasterSlideHost({
    super.key,
    required this.repaintKey,
    required this.initialSlide,
    required this.projectPath,
    required this.themeProfile,
    required this.deckMarpStyle,
    required this.cockpitColorScheme,
    required this.slideCount,
    required this.signature,
    required this.sealedAt,
    required this.tlp,
    required this.showClassificationWatermark,
    required this.organization,
    required this.reportLanguage,
    required this.scopeCia,
    this.improvementY01 = ImprovementY01Metric.empty,
  });

  @override
  State<_RasterSlideHost> createState() => _RasterSlideHostState();
}

class _RasterSlideHostState extends State<_RasterSlideHost> {
  late Slide _slide;
  late int _slideNumber;
  int _numberStart = 1;
  double? _fitScaleOverride;
  ({int page, int total})? _splitRunPosition;

  @override
  void initState() {
    super.initState();
    _slide = widget.initialSlide;
    _slideNumber = 1;
  }

  void showSlide(
    Slide slide,
    int slideNumber, {
    int numberStart = 1,
    double? fitScaleOverride,
    ({int page, int total})? splitRunPosition,
  }) {
    if (_slide.id == slide.id &&
        _slideNumber == slideNumber &&
        _numberStart == numberStart &&
        _fitScaleOverride == fitScaleOverride &&
        _splitRunPosition == splitRunPosition) {
      return;
    }
    setState(() {
      _slide = slide;
      _slideNumber = slideNumber;
      _numberStart = numberStart;
      _fitScaleOverride = fitScaleOverride;
      _splitRunPosition = splitRunPosition;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: widget.repaintKey,
      child: SizedBox(
        width: SlideRasterizer.logicalSize.width,
        height: SlideRasterizer.logicalSize.height,
        child: SlidePreviewWidget(
          // Een gerasterde pagina (PDF/PPTX) kan niet scrollen: een groot
          // mermaid-diagram valt hier terug op passend verkleinen i.p.v. een
          // scrollvenster (#872), zodat het hele diagram op de pagina staat.
          scrollableMermaid: false,
          slide: _slide,
          projectPath: widget.projectPath,
          themeProfile: widget.themeProfile,
          deckMarpStyle: widget.deckMarpStyle,
          cockpitColorScheme: widget.cockpitColorScheme,
          slideNumber: _slideNumber,
          slideCount: widget.slideCount,
          numberStart: _numberStart,
          fitScaleOverride: _fitScaleOverride,
          splitRunPosition: _splitRunPosition,
          deckSignature: widget.signature,
          sealedAt: widget.sealedAt,
          tlp: widget.tlp,
          showClassificationWatermark: widget.showClassificationWatermark,
          organization: widget.organization,
          scopeCia: widget.scopeCia,
          reportLanguage: widget.reportLanguage,
          improvementY01: widget.improvementY01,
        ),
      ),
    );
  }
}
