import '../models/slide.dart';
import 'ai_client_service.dart';

/// The free-text condensation consumer of the shared, optional AI backend.
/// When a rich-text slide body sprawls over several rendered pages, the author
/// may ask the model to condense it — either to one short paragraph or to a
/// list of at most [kAiCondenseMaxPoints] key points — while the original text
/// moves to the speaker notes so nothing is thrown away. The pure helpers
/// ([condenseInstruction], [parseCondensePoints], [cleanCondenseSummary],
/// [applyCondenseToSlide]) are network-free and unit-testable.

/// How the model should condense the source text.
enum AiCondenseMode {
  /// One short paragraph that fits on a single slide.
  summary,

  /// A compact list of at most [kAiCondenseMaxPoints] key points; the chosen
  /// [ListStyle] (bullets, numbered, checklist) is applied by the caller, not
  /// asked from the model — that keeps the output plain-text parseable.
  keyPoints,
}

/// The hard cap on key-point items. The prompt asks for it and the parser
/// enforces it: the model's word is a suggestion, not a guarantee.
const kAiCondenseMaxPoints = 8;

/// The hard cap on a summary's length — roughly one paragraph a slide at
/// default scale can hold. Anything longer is clipped at the last sentence
/// boundary rather than trusted to the model.
const kAiCondenseSummaryMaxChars = 550;

/// The per-mode instruction. Deliberately asks for plain, marker-free output:
/// a list style is a slide property here, not something the model chooses, so
/// the parsing stays a line-split and the clip to [kAiCondenseMaxPoints] stays
/// a hard guarantee.
String condenseInstruction(AiCondenseMode mode, String languageName) {
  return switch (mode) {
    AiCondenseMode.summary =>
      'Summarise the text in the context in $languageName, as one short '
          'paragraph that fits on a single presentation slide (about 60 words '
          'at most). Return only the paragraph, with no preamble.',
    AiCondenseMode.keyPoints =>
      'Distil the text in the context into at most $kAiCondenseMaxPoints '
          'concise key points in $languageName. Return one point per line, as '
          'plain text: no list markers, no numbering, no headings, no preamble.',
  };
}

/// What the model returned, cleaned and ready to apply to a slide. [points] is
/// filled for [AiCondenseMode.keyPoints], [summary] for [AiCondenseMode.summary].
class AiCondenseResult {
  const AiCondenseResult({
    required this.mode,
    this.listStyle = ListStyle.bullets,
    this.summary = '',
    this.points = const [],
  });

  final AiCondenseMode mode;

  /// The list style the author picked; only meaningful for
  /// [AiCondenseMode.keyPoints].
  final ListStyle listStyle;
  final String summary;
  final List<String> points;
}

final _reCodeFence = RegExp(r'^\s*```');
final _reListMarker = RegExp(r'^\s*(?:[-*•◦▪▫+]|\d+[.)]|\[[ xX]\])\s+');
final _reCheckbox = RegExp(r'^\[[ xX]\]\s*');
final _reHeading = RegExp(r'^#+\s');

/// Parse a key-points draft into plain item texts, clipped hard to
/// [kAiCondenseMaxPoints]. Tolerant of markers, numbering, checkbox syntax and
/// a wrapping code fence even though the prompt asks for plain lines — the
/// model is a suggestion, the contract is ours. Heading lines are skipped.
/// Returns `[]` when nothing usable came back.
List<String> parseCondensePoints(String raw) {
  final points = <String>[];
  for (final line in raw.split('\n')) {
    // A fence line is decoration, not content: skipping the marker but keeping
    // what is inside saves a draft the model wrapped wholesale in ```.
    if (_reCodeFence.hasMatch(line)) continue;
    var text = line.trim();
    if (text.isEmpty || _reHeading.hasMatch(text)) continue;
    // Two layers: '- [x] item' has a bullet AND a checkbox to peel off.
    text = text
        .replaceFirst(_reListMarker, '')
        .replaceFirst(_reCheckbox, '')
        .trim();
    if (text.isEmpty) continue;
    points.add(text);
    if (points.length >= kAiCondenseMaxPoints) break;
  }
  return points;
}

/// Tidy a summary draft: drop code fences and heading lines, collapse to one
/// paragraph, unwrap surrounding quotes, and clip at the last sentence
/// boundary inside [kAiCondenseSummaryMaxChars].
String cleanCondenseSummary(String raw) {
  final lines = <String>[];
  for (final line in raw.trim().split('\n')) {
    if (_reCodeFence.hasMatch(line)) continue;
    final text = line.trim();
    if (text.isEmpty || _reHeading.hasMatch(text)) continue;
    lines.add(text);
  }
  var t = lines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length >= 2 &&
      ((t.startsWith('"') && t.endsWith('"')) ||
          (t.startsWith('“') && t.endsWith('”')))) {
    t = t.substring(1, t.length - 1).trim();
  }
  if (t.length <= kAiCondenseSummaryMaxChars) return t;
  final window = t.substring(0, kAiCondenseSummaryMaxChars);
  final sentences = RegExp(r'[.!?…]').allMatches(window);
  final cut = sentences.isEmpty ? window.lastIndexOf(' ') : sentences.last.end;
  return (cut > 0 ? window.substring(0, cut) : window).trim();
}

/// Apply a condense result to [slide]. The original body text moves to the
/// speaker notes under [notesHeading] so nothing is lost; what replaces it
/// depends on the mode — a paragraph stays rich text, key points turn the
/// slide into a list of the chosen style. The whole change is one
/// [Slide.copyWith], so one deck mutation (and one undo step) covers it.
Slide applyCondenseToSlide(
  Slide slide,
  AiCondenseResult result, {
  required String notesHeading,
}) {
  final original = slide.customMarkdown.trim();
  final notes = original.isEmpty
      ? slide.notes
      : [
          if (slide.notes.trim().isNotEmpty) slide.notes.trim(),
          notesHeading,
          original,
        ].join('\n\n');
  return switch (result.mode) {
    AiCondenseMode.summary => slide.copyWith(
      customMarkdown: result.summary,
      notes: notes,
    ),
    AiCondenseMode.keyPoints => slide.copyWith(
      listStyle: result.listStyle,
      bullets: [
        for (final point in result.points)
          result.listStyle == ListStyle.checklist
              ? checklistBullet(level: 0, text: point, checked: false)
              : point,
      ],
      // The original prose lives in the notes now; leaving it here too would
      // keep an invisible copy that the serialiser drops anyway.
      customMarkdown: '',
      notes: notes,
    ),
  };
}

/// Wraps a gated [AiClientService] as the rich-text condensation consumer.
class AiCondenseService {
  AiCondenseService(this._client);

  final AiClientService _client;

  /// Condense [sourceText] per [mode] in [languageName]. Returns null when the
  /// model gave nothing usable (empty summary, no points). Propagates the
  /// client's `AiGateException` / `AiRequestException` so the caller can fall
  /// back gracefully.
  Future<AiCondenseResult?> condense({
    required AiCondenseMode mode,
    required ListStyle listStyle,
    required String sourceText,
    required String languageName,
  }) async {
    final draft = await _client.suggest(
      context: sourceText,
      instruction: condenseInstruction(mode, languageName),
    );
    return switch (mode) {
      AiCondenseMode.summary => () {
        final summary = cleanCondenseSummary(draft);
        return summary.isEmpty
            ? null
            : AiCondenseResult(mode: mode, summary: summary);
      }(),
      AiCondenseMode.keyPoints => () {
        final points = parseCondensePoints(draft);
        return points.isEmpty
            ? null
            : AiCondenseResult(
                mode: mode,
                listStyle: listStyle,
                points: points,
              );
      }(),
    };
  }
}
