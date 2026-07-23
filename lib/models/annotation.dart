import 'dart:ui';
import 'dart:math';

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

  /// A stable identity for this stroke, unique within the deck.
  ///
  /// Added for the git merge (GIT_STORAGE D7, #541). The merge unions the
  /// stroke sets — two people drawing on one slide did not disagree — and a
  /// union needs to know which strokes are *the same* stroke. Without an id
  /// the only handle is the point list, and two independent copies of the same
  /// drawing would union into a double-drawn one.
  ///
  /// Never reused, never derived from the content: a stroke that is redrawn in
  /// the same place is a different stroke.
  final String id;

  /// Whether this stroke was erased.
  ///
  /// **A tombstone, not a deletion**, and that is the whole point. The union
  /// merge is the right answer for adding, and the obviously wrong one for
  /// erasing: drop an erased stroke from the file and the other side of the
  /// merge — which still has it — brings it back. A deletion that returns is
  /// worse than one that does not work, because the user believed it was gone.
  ///
  /// So an erased stroke stays in the file, marked. The renderer skips it, the
  /// merge keeps it, and erasing survives.
  final bool erased;

  const InkStroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    required this.id,
    this.erased = false,
  });

  InkStroke copyWith({List<Offset>? points, bool? erased}) => InkStroke(
    tool: tool,
    color: color,
    width: width,
    points: points ?? this.points,
    id: id,
    erased: erased ?? this.erased,
  );

  /// Compact JSON: points are flattened to [x0, y0, x1, y1, …].
  ///
  /// `erased` is written only when true — the common case is a stroke that is
  /// simply there, and a sidecar full of `"erased": false` is noise in a file
  /// people read in a diff.
  Map<String, dynamic> toJson() => {
    'id': id,
    'tool': tool.name,
    'color': color,
    'width': width,
    if (erased) 'erased': true,
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
    final id = json['id'];
    return InkStroke(
      tool: InkTool.values.firstWhere(
        (t) => t.name == json['tool'],
        orElse: () => InkTool.pen,
      ),
      color: (json['color'] as num?)?.toInt() ?? 0xFFEF4444,
      width: (json['width'] as num?)?.toDouble() ?? 0.004,
      points: pts,
      // Het leespad voor sidecars van vóór de identiteit: geef er alsnog een.
      // Een verzonnen id is precies goed voor het geval waar hij voor bedoeld
      // is — twee kanten van een merge — want twee kopieën van zo'n oud bestand
      // krijgen verschillende ids en verenigen dus tot dubbel getekende lijnen.
      // Dat is zichtbaar en herstelbaar; stil één van beide laten vallen niet.
      id: id is String && id.isNotEmpty ? id : newStrokeId(),
      erased: json['erased'] == true,
    );
  }
}

/// Een verse streekidentiteit.
///
/// Tijd plus toeval: het tijdsdeel houdt de ids in een bestand ruwweg op
/// tekenvolgorde, wat een diff leesbaar houdt, en het toevalsdeel zorgt dat
/// twee mensen die tegelijk tekenen elkaar niet raken. Geen UUID-pakket
/// ervoor binnengehaald — dit hoeft niet wereldwijd uniek te zijn, alleen
/// binnen de twee kanten van één merge.
String newStrokeId() {
  final r = Random();
  final tail = List<int>.generate(
    6,
    (_) => r.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$tail';
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
