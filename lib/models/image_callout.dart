// The typed model for image callouts — linking a bullet to a place in the
// picture beside it (IMAGE_CALLOUTS.md §3).
//
// Geometry is data in **image space** (0..1, three decimals); presentation is
// not part of it. A region drawn as a spotlight and the same region drawn as an
// outline are one datum and two renderings. The codec is the only code that
// knows callouts are stored deck-side in front matter keyed by anchor — the
// model lives on the [Slide], so collaboration, undo, reorder and delete all
// ride existing machinery.

/// A target in image space (0..1). Either a point or a rectangle.
///
/// Numbers are never clamped on read (§2.4): out-of-range geometry is preserved
/// and reported by the checker, not silently moved. Validation lives in the
/// checker, not in the model — a [CalloutRegion] with `w <= 0` is a valid datum
/// that the renderer refuses to draw.
sealed class CalloutTarget {
  const CalloutTarget();

  /// Three-decimal formatting for the canonical front-matter block (§2.2).
  String get _geometry;

  /// JSON tag for collab codec serialisation.
  String get typeTag;

  Map<String, dynamic> toJson();
  static CalloutTarget fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'point' => CalloutPoint(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      'region' => CalloutRegion(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['w'] as num).toDouble(),
        (json['h'] as num).toDouble(),
      ),
      _ => throw FormatException('Unknown CalloutTarget type: $type'),
    };
  }
}

/// A single point in image space.
class CalloutPoint extends CalloutTarget {
  final double x;
  final double y;

  const CalloutPoint(this.x, this.y);

  @override
  String get typeTag => 'point';

  @override
  String get _geometry => 'point ${_fmt(x)} ${_fmt(y)}';

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'point', 'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is CalloutPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash('point', x, y);
}

/// A rectangle in image space. `(x, y)` is the **top-left corner**, not the
/// centre (§2.2). `w` and `h` are strictly positive and `x + w ≤ 1`,
/// `y + h ≤ 1` — validated by the checker, not clamped on read.
class CalloutRegion extends CalloutTarget {
  final double x;
  final double y;
  final double w;
  final double h;

  const CalloutRegion(this.x, this.y, this.w, this.h);

  @override
  String get typeTag => 'region';

  @override
  String get _geometry =>
      'region ${_fmt(x)} ${_fmt(y)} ${_fmt(w)} ${_fmt(h)}';

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'region', 'x': x, 'y': y, 'w': w, 'h': h};

  @override
  bool operator ==(Object other) =>
      other is CalloutRegion &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash('region', x, y, w, h);
}

/// One reference on a slide: a letter (`A`–`Z`), one or more targets in the
/// image, and a description that carries the meaning for a screen reader
/// (§12.1 — one description per reference, describing the whole group).
class ImageCallout {
  final String reference;
  final List<CalloutTarget> targets;
  final String description;

  const ImageCallout({
    required this.reference,
    required this.targets,
    this.description = '',
  });

  /// Canonical front-matter value: `geometry[; geometry…] | description`.
  String toBlockValue() {
    final geo = targets.map((t) => t._geometry).join('; ');
    return description.isEmpty ? geo : '$geo | $description';
  }

  Map<String, dynamic> toJson() => {
    'reference': reference,
    'targets': targets.map((t) => t.toJson()).toList(),
    'description': description,
  };

  static ImageCallout fromJson(Map<String, dynamic> json) => ImageCallout(
    reference: json['reference'] as String,
    targets: (json['targets'] as List)
        .map((t) => CalloutTarget.fromJson(t as Map<String, dynamic>))
        .toList(),
    description: json['description'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is ImageCallout &&
      other.reference == reference &&
      _listEq(other.targets, targets) &&
      other.description == description;

  @override
  int get hashCode => Object.hash(reference, Object.hashAll(targets), description);

  static bool _listEq(List<CalloutTarget> a, List<CalloutTarget> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Slide-level presentation style for callouts (§3.1). `mode` is a style, not a
/// promise that every target has that shape — the mode-against-target matrix
/// decides how each target is drawn.
enum CalloutPresentation { pin, region, arrow }

/// When the bullet and its marks appear during a presentation (§7). `all` =
/// everything visible from the start; `steps` = one bullet plus all its targets
/// per next action.
enum BulletRevealMode { all, steps }

/// Three-decimal formatting (§2.2): the writer always emits exactly three
/// decimals, so the file heals itself rather than rejecting an honest edit.
String _fmt(double v) => v.toStringAsFixed(3);
