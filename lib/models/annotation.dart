import 'dart:ui';

/// Annotation tools available while presenting. Drawings live in a layer that
/// is fully separate from the Marp content — they are never written to the
/// markdown.
enum InkTool { laser, pen, highlighter, eraser }

/// A single freehand stroke on the annotation layer.
///
/// Coordinates are normalized (0..1) within the 16:9 slide rectangle and the
/// width is a fraction of the slide width, so a stroke renders identically on
/// the laptop preview and the beamer regardless of resolution or letterboxing.
class InkStroke {
  final InkTool tool;
  final int color; // ARGB
  final double width; // fraction of the slide width
  final List<Offset> points; // normalized 0..1

  const InkStroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  InkStroke copyWith({List<Offset>? points}) => InkStroke(
    tool: tool,
    color: color,
    width: width,
    points: points ?? this.points,
  );

  /// Compact JSON: points are flattened to [x0, y0, x1, y1, …].
  Map<String, dynamic> toJson() => {
    'tool': tool.name,
    'color': color,
    'width': width,
    'points': [
      for (final p in points) ...[_round(p.dx), _round(p.dy)],
    ],
  };

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;

  factory InkStroke.fromJson(Map<String, dynamic> json) {
    final raw = (json['points'] as List?)?.cast<num>() ?? const [];
    final pts = <Offset>[];
    for (var i = 0; i + 1 < raw.length; i += 2) {
      pts.add(Offset(raw[i].toDouble(), raw[i + 1].toDouble()));
    }
    return InkStroke(
      tool: InkTool.values.firstWhere(
        (t) => t.name == json['tool'],
        orElse: () => InkTool.pen,
      ),
      color: (json['color'] as num?)?.toInt() ?? 0xFFEF4444,
      width: (json['width'] as num?)?.toDouble() ?? 0.004,
      points: pts,
    );
  }
}

/// The annotation-map key for one page of a slide. Page 0 (and every slide that
/// doesn't paginate) keeps the bare slide id, so single-page annotations and
/// older sidecars keep matching; later pages of a rich-text slide — which all
/// share one slide id — get a distinct suffix so marks don't bleed across pages.
String annotationKey(String slideId, int page) =>
    page <= 0 ? slideId : '$slideId#p$page';

/// The page a [key] refers to for slide [slideId], or null when the key belongs
/// to a different slide. Inverse of [annotationKey]: `id` → 0, `id#pN` → N.
int? annotationPageForKey(String key, String slideId) {
  if (key == slideId) return 0;
  final prefix = '$slideId#p';
  if (!key.startsWith(prefix)) return null;
  return int.tryParse(key.substring(prefix.length));
}

/// Encode/decode a per-slide map of strokes keyed by slide id.
List<Map<String, dynamic>> encodeStrokes(List<InkStroke> strokes) => [
  for (final s in strokes) s.toJson(),
];

List<InkStroke> decodeStrokes(List<dynamic> raw) => [
  for (final e in raw) InkStroke.fromJson(Map<String, dynamic>.from(e as Map)),
];
