import 'package:material_ui/material_ui.dart';

import '../../../services/scene/scene.dart';
import '../../../theme/app_theme.dart';

/// Paints a [Scene] — the Flutter backend for Procesverbetering engines
/// (PROCESS_IMPROVEMENT.md §7). Layout maths live in the engines; this only
/// draws what they already decided.
class ScenePainter extends CustomPainter {
  ScenePainter(this.scene);

  final Scene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / scene.width;
    final sy = size.height / scene.height;
    canvas.save();
    canvas.scale(sx, sy);
    for (final node in scene.nodes) {
      switch (node) {
        case SceneRect():
          final paint = Paint()
            ..style = node.fill != null
                ? PaintingStyle.fill
                : PaintingStyle.stroke
            ..color = AppTheme.parseHexColor(node.fill ?? node.stroke ?? '#000')
            ..strokeWidth = node.strokeWidth;
          final r = RRect.fromRectAndRadius(
            Rect.fromLTWH(node.x, node.y, node.width, node.height),
            Radius.circular(node.cornerRadius),
          );
          canvas.drawRRect(r, paint);
          if (node.fill != null && node.stroke != null) {
            canvas.drawRRect(
              r,
              Paint()
                ..style = PaintingStyle.stroke
                ..color = AppTheme.parseHexColor(node.stroke!)
                ..strokeWidth = node.strokeWidth,
            );
          }
        case SceneLine():
          canvas.drawLine(
            Offset(node.x1, node.y1),
            Offset(node.x2, node.y2),
            Paint()
              ..color = AppTheme.parseHexColor(node.stroke)
              ..strokeWidth = node.strokeWidth,
          );
        case ScenePath():
          if (node.points.length < 4) break;
          final path = Path()..moveTo(node.points[0], node.points[1]);
          for (var i = 2; i + 1 < node.points.length; i += 2) {
            path.lineTo(node.points[i], node.points[i + 1]);
          }
          if (node.closed) path.close();
          if (node.fill != null) {
            canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.fill
                ..color = AppTheme.parseHexColor(node.fill!),
            );
          }
          if (node.stroke != null) {
            canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..color = AppTheme.parseHexColor(node.stroke!)
                ..strokeWidth = node.strokeWidth,
            );
          }
        case SceneText():
          final tp = TextPainter(
            text: TextSpan(
              text: node.text,
              style: TextStyle(
                color: AppTheme.parseHexColor(node.fill),
                fontSize: node.fontSize,
                fontWeight:
                    FontWeight.values[((node.fontWeight / 100).round() - 1)
                        .clamp(0, FontWeight.values.length - 1)],
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: node.maxWidth == null ? 1 : null,
          )..layout(maxWidth: node.maxWidth ?? double.infinity);
          tp.paint(canvas, Offset(node.x, node.y - tp.height * 0.8));
        case SceneImageRef():
          // Image decoding belongs to the host; engines that need images pass
          // a resolved backend. Until then draw a placeholder frame.
          canvas.drawRect(
            Rect.fromLTWH(node.x, node.y, node.width, node.height),
            Paint()
              ..style = PaintingStyle.stroke
              ..color = AppTheme.slideInkFaint,
          );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScenePainter old) => old.scene != scene;
}

/// Widget wrapper so [ScenePainter] stays reachable from the widget tree /
/// tests (dead-code gate) before engines wire it into slide_preview.
class ScenePreview extends StatelessWidget {
  const ScenePreview({super.key, required this.scene});

  final Scene scene;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ScenePainter(scene),
      size: Size(scene.width, scene.height),
    );
  }
}
