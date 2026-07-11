import '../models/deck.dart';
import '../models/finding_spec.dart';
import '../models/slide.dart';
import 'cvss/cvss4.dart';

/// Auto-numbering + findings-list derivation (PENTEST_MIAUW §10.1). Finding ids
/// (`F-01`, `F-02`, …) are mechanical bookkeeping: this maintains them from deck
/// order and derives the numbered findings list, so the report is internally
/// consistent by construction.

/// A leading `F-<n>` token (with an optional `·`/`:`/`.`/`-` separator) at the
/// start of a heading or title — the auto-numbering prefix.
final _reFindingPrefix = RegExp(
  r'^\s*F-\d+\s*[·:.\-]?\s*',
  caseSensitive: false,
);

/// Replace (or add) the `F-NN · ` prefix on [text] with [id]. A heading that
/// already carries a number is renumbered in place; one without simply gets the
/// prefix prepended.
String applyFindingPrefix(String text, String id) {
  final rest = text.replaceFirst(_reFindingPrefix, '').trim();
  return rest.isEmpty ? id : '$id · $rest';
}

/// One finding in the deck's ordered findings list (PENTEST_MIAUW §4.2).
class FindingListEntry {
  const FindingListEntry({
    required this.id,
    required this.heading,
    required this.severity,
  });

  final String id;
  final String heading;
  final Cvss4Severity severity;
}

/// The ordered findings list — one entry per finding **header** (detail and
/// evidence slides are skipped), in deck order.
List<FindingListEntry> deckFindingList(Deck deck) => [
  for (final s in deck.slides)
    if (s.type == SlideType.finding && s.findingRole == FindingRole.header)
      FindingListEntry(
        id: s.findingId,
        heading: FindingSpec.parse(s.customMarkdown).heading,
        severity:
            FindingSpec.parse(s.customMarkdown).severity ?? Cvss4Severity.none,
      ),
];

/// Sequentially renumber every finding group in [deck] (`F-01`, `F-02`, … in
/// deck order). Each header gets the next id, its `F-NN` heading prefix (and the
/// mirrored slide title) rewritten to match; the group's detail/evidence slides
/// inherit the new id, and their title prefix is refreshed only when it already
/// carried an `F-NN` token (so a hand-renamed detail slide is left alone).
/// Returns [deck] unchanged when it has no findings.
Deck renumberFindings(Deck deck) {
  final slides = List<Slide>.from(deck.slides);
  final idRemap = <String, String>{}; // old non-empty id → new id
  var n = 0;

  for (var i = 0; i < slides.length; i++) {
    final s = slides[i];
    if (s.type != SlideType.finding || s.findingRole != FindingRole.header) {
      continue;
    }
    n++;
    final newId = 'F-${n.toString().padLeft(2, '0')}';
    if (s.findingId.isNotEmpty) idRemap[s.findingId] = newId;
    final spec = FindingSpec.parse(s.customMarkdown);
    final newHeading = applyFindingPrefix(spec.heading, newId);
    slides[i] = s.copyWith(
      findingId: newId,
      customMarkdown: spec.copyWith(heading: newHeading).toMarkdown(),
      title: newHeading,
    );
  }
  if (n == 0) return deck;

  for (var i = 0; i < slides.length; i++) {
    final s = slides[i];
    if (s.findingRole == FindingRole.header) continue;
    final newId = idRemap[s.findingId];
    if (newId == null) continue;
    final title = _reFindingPrefix.hasMatch(s.title)
        ? applyFindingPrefix(s.title, newId)
        : s.title;
    slides[i] = s.copyWith(findingId: newId, title: title);
  }
  return deck.copyWith(slides: slides);
}
