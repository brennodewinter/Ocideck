import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/cvss_builder.dart';
import '../models/deck.dart';
import '../models/document_signature.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import 'web_asset_store.dart';
import '../utils/bundled_asset.dart';
import '../utils/image_limits.dart';
import '../utils/project_path.dart';
import 'finding_context_score.dart';
import 'slide_layout_metrics.dart';
import '../widgets/document_signature_view.dart'
    show decodeEmbeddedSignatureImage;
import '../widgets/slides/slide_preview.dart';

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

  /// Render [slides] to PNG bytes at [targetWidth] x (targetWidth * 9/16).
  static Future<List<Uint8List>> rasterize({
    required BuildContext context,
    required List<Slide> slides,
    required ThemeProfile themeProfile,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    required String? projectPath,
    DocumentSignature? signature,
    String sealedAt = '',
    TlpLevel tlp = TlpLevel.none,
    bool showClassificationWatermark = false,
    String organization = '',
    int targetWidth = 1920,
    void Function(int done, int total)? onProgress,
    void Function(String phase, int done, int total)? onStage,
    // Polled tussen slides: true = stoppen. De aanroeper krijgt dan een
    // onvolledige lijst terug en hoort die weg te gooien.
    bool Function()? isCancelled,
  }) async {
    if (slides.isEmpty) return const [];

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
    final rawLogo = themeProfile.logoPath ?? '';
    final logo = isBundledAssetPath(rawLogo)
        ? rawLogo
        : resolveTrustedAssetPath(rawLogo, projectPath);
    final allPaths = <String>{
      ?logo,
      for (final slide in slides) ...[
        ?_resolveOrMem(slide.imagePath, projectPath),
        ?_resolveOrMem(slide.imagePath2, projectPath),
      ],
    };

    final repaintKey = GlobalKey();
    final hostKey = GlobalKey<_RasterSlideHostState>();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -logicalSize.width - 100,
        top: -logicalSize.height - 100,
        child: _RasterSlideHost(
          key: hostKey,
          repaintKey: repaintKey,
          initialSlide: slides.first,
          projectPath: projectPath,
          themeProfile: themeProfile,
          cockpitColorScheme: cockpitColorScheme,
          slideCount: slides.length,
          signature: signature,
          sealedAt: sealedAt,
          tlp: tlp,
          showClassificationWatermark: showClassificationWatermark,
          organization: organization,
          scopeCia: deckScopeCiaIndex(slides),
        ),
      ),
    );

    final results = <Uint8List>[];
    try {
      overlay.insert(entry);
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return results;

      onStage?.call('precache', 0, allPaths.length);
      await _precachePathsBatched(
        context,
        allPaths,
        onProgress: (done, total) => onStage?.call('precache', done, total),
      );
      if (!context.mounted) return results;

      // The sign-off's drawn signature is a deck-level embedded image, not a
      // slide path — precache it (as the same MemoryImage the preview uses, via
      // the shared decoder's stable bytes) so it paints on the first captured
      // frame instead of decoding a beat too late.
      final sigBytes = signature == null
          ? null
          : decodeEmbeddedSignatureImage(signature.imagePath);
      if (sigBytes != null) {
        await precacheImage(MemoryImage(sigBytes), context, onError: (_, _) {});
        if (!context.mounted) return results;
      }

      for (var i = 0; i < slides.length; i++) {
        if (isCancelled?.call() ?? false) break;
        onStage?.call('prepare', i, slides.length);
        hostKey.currentState!.showSlide(
          slides[i],
          i + 1,
          numberStart: numberedListStartFor(slides, i),
          fitScaleOverride: sharedSplitFitScale(
            slides,
            i,
            themeProfile,
            themeProfile.fontFamily,
          ),
        );
        if (!context.mounted) break;

        onStage?.call('render', i, slides.length);
        final png = await _capture(repaintKey, pixelRatio);
        results.add(png);

        onStage?.call('done', i + 1, slides.length);
        onProgress?.call(i + 1, slides.length);
      }
    } finally {
      entry.remove();
      imageCache.maximumSize = prevMaxSize;
      imageCache.maximumSizeBytes = prevMaxBytes;
    }
    return results;
  }

  static Future<Uint8List> _capture(GlobalKey key, double pixelRatio) async {
    await WidgetsBinding.instance.endOfFrame;
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
  final CockpitColorScheme cockpitColorScheme;
  final int slideCount;
  final DocumentSignature? signature;
  final String sealedAt;
  final TlpLevel tlp;
  final bool showClassificationWatermark;
  final String organization;
  final Map<String, CiaRating> scopeCia;

  const _RasterSlideHost({
    super.key,
    required this.repaintKey,
    required this.initialSlide,
    required this.projectPath,
    required this.themeProfile,
    required this.cockpitColorScheme,
    required this.slideCount,
    required this.signature,
    required this.sealedAt,
    required this.tlp,
    required this.showClassificationWatermark,
    required this.organization,
    required this.scopeCia,
  });

  @override
  State<_RasterSlideHost> createState() => _RasterSlideHostState();
}

class _RasterSlideHostState extends State<_RasterSlideHost> {
  late Slide _slide;
  late int _slideNumber;
  int _numberStart = 1;
  double? _fitScaleOverride;

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
  }) {
    if (_slide.id == slide.id &&
        _slideNumber == slideNumber &&
        _numberStart == numberStart &&
        _fitScaleOverride == fitScaleOverride) {
      return;
    }
    setState(() {
      _slide = slide;
      _slideNumber = slideNumber;
      _numberStart = numberStart;
      _fitScaleOverride = fitScaleOverride;
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
          slide: _slide,
          projectPath: widget.projectPath,
          themeProfile: widget.themeProfile,
          cockpitColorScheme: widget.cockpitColorScheme,
          slideNumber: _slideNumber,
          slideCount: widget.slideCount,
          numberStart: _numberStart,
          fitScaleOverride: _fitScaleOverride,
          deckSignature: widget.signature,
          sealedAt: widget.sealedAt,
          tlp: widget.tlp,
          showClassificationWatermark: widget.showClassificationWatermark,
          organization: widget.organization,
          scopeCia: widget.scopeCia,
        ),
      ),
    );
  }
}
