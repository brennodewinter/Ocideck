// Pure Dart scene model for Procesverbetering engines
// (PROCESS_IMPROVEMENT.md §7 / Phase 3a). Engines produce a Scene; two thin
// backends paint it (CustomPainter + SVG). No Flutter imports here.
library;

/// A laid-out slide contents description: explicit positions, no style tree.
class Scene {
  const Scene({required this.width, required this.height, required this.nodes});

  final double width;
  final double height;
  final List<SceneNode> nodes;

  /// Tiny demo scene used by tests and to keep the painter reachable for the
  /// dead-code gate before engines exist.
  factory Scene.demo() => const Scene(
    width: 200,
    height: 100,
    nodes: [
      SceneRect(x: 10, y: 10, width: 80, height: 40, fill: '#2563EB'),
      SceneText(x: 20, y: 35, text: 'demo', fontSize: 14, fill: '#FFFFFF'),
      SceneLine(
        x1: 10,
        y1: 60,
        x2: 190,
        y2: 60,
        stroke: '#64748B',
        strokeWidth: 1,
      ),
    ],
  );
}

/// How an engine measures text without importing Flutter into layout maths.
abstract class TextMeasurer {
  /// Width of [text] at [fontSize] in the active font.
  double widthOf(String text, {required double fontSize});

  /// Line height at [fontSize].
  double lineHeight({required double fontSize});
}

/// A naive monospace-ish measurer for unit tests (no Flutter).
class ApproximateTextMeasurer implements TextMeasurer {
  const ApproximateTextMeasurer();

  @override
  double widthOf(String text, {required double fontSize}) =>
      text.length * fontSize * 0.55;

  @override
  double lineHeight({required double fontSize}) => fontSize * 1.25;
}

sealed class SceneNode {
  const SceneNode();
}

class SceneRect extends SceneNode {
  const SceneRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.cornerRadius = 0,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final String? fill;
  final String? stroke;
  final double strokeWidth;
  final double cornerRadius;
}

class SceneLine extends SceneNode {
  const SceneLine({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.stroke = '#000000',
    this.strokeWidth = 1,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String stroke;
  final double strokeWidth;
}

class ScenePath extends SceneNode {
  const ScenePath({
    required this.points,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.closed = false,
  });

  /// Flattened [x0,y0, x1,y1, …].
  final List<double> points;
  final String? fill;
  final String? stroke;
  final double strokeWidth;
  final bool closed;
}

class SceneText extends SceneNode {
  const SceneText({
    required this.x,
    required this.y,
    required this.text,
    required this.fontSize,
    this.fill = '#000000',
    this.fontWeight = 400,
    this.maxWidth,
  });

  final double x;
  final double y;
  final String text;
  final double fontSize;
  final String fill;
  final int fontWeight;
  final double? maxWidth;
}

class SceneImageRef extends SceneNode {
  const SceneImageRef({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.href,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  /// Path or data URI — resolved by the backend.
  final String href;
}

/// Serialize [scene] to an SVG fragment (viewBox = scene size).
String sceneToSvg(Scene scene) {
  final b = StringBuffer()
    ..write(
      '<svg viewBox="0 0 ${scene.width} ${scene.height}" '
      'xmlns="http://www.w3.org/2000/svg" width="100%">',
    );
  for (final node in scene.nodes) {
    switch (node) {
      case SceneRect(
        :final x,
        :final y,
        :final width,
        :final height,
        :final fill,
        :final stroke,
        :final strokeWidth,
        :final cornerRadius,
      ):
        b.write(
          '<rect x="$x" y="$y" width="$width" height="$height" '
          'rx="$cornerRadius" '
          '${fill != null ? 'fill="$fill"' : 'fill="none"'} '
          '${stroke != null ? 'stroke="$stroke" stroke-width="$strokeWidth"' : ''}/>',
        );
      case SceneLine(
        :final x1,
        :final y1,
        :final x2,
        :final y2,
        :final stroke,
        :final strokeWidth,
      ):
        b.write(
          '<line x1="$x1" y1="$y1" x2="$x2" y2="$y2" '
          'stroke="$stroke" stroke-width="$strokeWidth"/>',
        );
      case ScenePath(
        :final points,
        :final fill,
        :final stroke,
        :final strokeWidth,
        :final closed,
      ):
        if (points.length < 4) break;
        final d = StringBuffer('M ${points[0]} ${points[1]}');
        for (var i = 2; i + 1 < points.length; i += 2) {
          d.write(' L ${points[i]} ${points[i + 1]}');
        }
        if (closed) d.write(' Z');
        b.write(
          '<path d="$d" '
          '${fill != null ? 'fill="$fill"' : 'fill="none"'} '
          '${stroke != null ? 'stroke="$stroke" stroke-width="$strokeWidth"' : ''}/>',
        );
      case SceneText(
        :final x,
        :final y,
        :final text,
        :final fontSize,
        :final fill,
        :final fontWeight,
      ):
        final esc = text
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;');
        b.write(
          '<text x="$x" y="$y" font-size="$fontSize" '
          'font-weight="$fontWeight" fill="$fill">$esc</text>',
        );
      case SceneImageRef(
        :final x,
        :final y,
        :final width,
        :final height,
        :final href,
      ):
        b.write(
          '<image x="$x" y="$y" width="$width" height="$height" '
          'href="${href.replaceAll('"', '&quot;')}"/>',
        );
    }
  }
  b.write('</svg>');
  return b.toString();
}
