// Part of the add_slide_dialog library — see add_slide_dialog.dart. Split out
// for the file-size ratchet: the larger inline wireframes of
// [SlideTypePreviewPainter] live here as an extension in the same library, so
// [SlideTypePreviewPainter.paint] keeps its private `_bar` helper and fields
// while staying under the method-length ceiling as new slide types are added.
part of 'add_slide_dialog.dart';

extension _PreviewWireframes on SlideTypePreviewPainter {
  /// Horizontal rail with four nodes and cards alternating above/below.
  void _paintTimelineWireframe(Canvas canvas) {
    // The palette tokens are static on the painter; alias them once so the
    // drawing below reads the same as the other inline wireframes.
    final accent = SlideTypePreviewPainter._accent;
    final ink = SlideTypePreviewPainter._ink;
    final soft = SlideTypePreviewPainter._soft;
    final fill = SlideTypePreviewPainter._fill;
    canvas.drawLine(
      const Offset(18, 45),
      const Offset(146, 45),
      _paint(accent)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    const xs = [26.0, 66.0, 106.0, 142.0];
    for (var i = 0; i < xs.length; i++) {
      final x = xs[i];
      final above = i.isEven;
      final cardY = above ? 12.0 : 56.0;
      _bar(canvas, x - 16, cardY, 32, 22, fill, radius: 3);
      _bar(canvas, x - 12, cardY + 4, 14, 5, accent, radius: 2);
      _bar(canvas, x - 12, cardY + 12, 22, 4, soft, radius: 2);
      canvas.drawLine(
        Offset(x, 45),
        Offset(x, above ? 34 : 56),
        _paint(accent.withValues(alpha: 0.4))..strokeWidth = 1.5,
      );
      canvas.drawCircle(
        Offset(x, 45),
        6,
        _paint(accent.withValues(alpha: 0.18)),
      );
      canvas.drawCircle(Offset(x, 45), 4, _paint(accent));
      canvas.drawCircle(
        Offset(x, 45),
        4,
        _paint(ink)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }
}
