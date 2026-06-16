import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;

import '../models/deck.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../widgets/slides/slide_preview.dart';

/// Renders the exact on-screen slide previews to PNG images so exports look
/// identical to what the user sees (WYSIWYG).
///
/// Each slide is mounted in an [Overlay] inside a keyed [RepaintBoundary] that
/// is positioned off-screen. A RepaintBoundary records its subtree into its
/// own layer regardless of where it sits on screen, so `toImage` captures the
/// full slide even though nothing is visible to the user.
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
    required String? projectPath,
    TlpLevel tlp = TlpLevel.none,
    bool showClassificationWatermark = false,
    String organization = '',
    int targetWidth = 1920,
    void Function(int done, int total)? onProgress,
    void Function(String phase, int done, int total)? onStage,
  }) async {
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

    final logo = _resolve(themeProfile.logoPath ?? '', projectPath);

    final results = <Uint8List>[];
    try {
      for (var i = 0; i < slides.length; i++) {
        onStage?.call('prepare', i, slides.length);
        // Warm this slide's images immediately before capturing it. Doing it
        // per slide (instead of once up front) guarantees the bitmap is decoded
        // and resident in the cache at capture time, no matter how many images
        // the whole deck contains.
        if (!context.mounted) break;
        await _precachePaths(context, [
          _resolve(slides[i].imagePath, projectPath),
          _resolve(slides[i].imagePath2, projectPath),
          logo,
        ]);
        if (!context.mounted) break;

        onStage?.call('render', i, slides.length);
        final key = GlobalKey();
        final entry = OverlayEntry(
          builder: (_) => Positioned(
            left: -logicalSize.width - 100,
            top: -logicalSize.height - 100,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: logicalSize.width,
                height: logicalSize.height,
                child: SlidePreviewWidget(
                  slide: slides[i],
                  projectPath: projectPath,
                  themeProfile: themeProfile,
                  slideNumber: i + 1,
                  slideCount: slides.length,
                  tlp: tlp,
                  showClassificationWatermark: showClassificationWatermark,
                  organization: organization,
                ),
              ),
            ),
          ),
        );

        overlay.insert(entry);
        try {
          final png = await _capture(key, pixelRatio);
          results.add(png);
        } finally {
          entry.remove();
        }
        onStage?.call('done', i + 1, slides.length);
        onProgress?.call(i + 1, slides.length);
      }
    } finally {
      imageCache.maximumSize = prevMaxSize;
      imageCache.maximumSizeBytes = prevMaxBytes;
    }
    return results;
  }

  static Future<Uint8List> _capture(GlobalKey key, double pixelRatio) async {
    // Allow build + layout + paint to settle before capturing. Wait for a
    // couple of frames first so LayoutBuilder-driven subtrees (e.g. zoomed
    // images) have a chance to lay out and paint their decoded bitmap.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    RenderRepaintBoundary? boundary;
    for (var attempt = 0; attempt < 30; attempt++) {
      final obj = key.currentContext?.findRenderObject();
      if (obj is RenderRepaintBoundary && !obj.debugNeedsPaint) {
        boundary = obj;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
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

  /// Decode and cache the given (already resolved) image paths, awaiting all of
  /// them. Nulls and duplicates are ignored; decode errors are swallowed so a
  /// single missing file never aborts the whole export.
  static Future<void> _precachePaths(
    BuildContext context,
    List<String?> paths,
  ) async {
    final unique = paths.whereType<String>().toSet();
    final futures = <Future<void>>[];
    for (final path in unique) {
      if (!context.mounted) return;
      futures.add(
        precacheImage(FileImage(File(path)), context, onError: (_, _) {}),
      );
    }
    await Future.wait(futures);
  }

  static String? _resolve(String imagePath, String? projectPath) {
    if (imagePath.isEmpty) return null;
    if (p.isAbsolute(imagePath)) return imagePath;
    if (projectPath != null) return p.join(projectPath, imagePath);
    return imagePath;
  }
}
