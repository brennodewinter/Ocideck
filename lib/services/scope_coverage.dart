import '../models/deck.dart';
import '../models/finding_spec.dart';
import '../models/scope_matrix_spec.dart';
import '../models/slide.dart';

/// Scope-coverage checker (PENTEST_MIAUW §10.4): the "did you actually test
/// everything you scoped" guardrail. A scope object is a **gap** when it is
/// still marked *not tested* and no finding references it — so it is in scope
/// but has neither a test result nor a finding.

/// A scope object that is in scope but not covered by a test or a finding.
class ScopeGap {
  const ScopeGap({required this.object, required this.type});

  final String object;
  final ScopeObjectType type;
}

/// Normalize a scope-object string for matching: trim, lower-case and drop a
/// trailing slash. The scope-matrix cell and a finding's scope object are two
/// independently free-typed fields, so a raw `==` would miss e.g. a trailing `/`.
String normalizeScopeObject(String value) {
  var v = value.trim().toLowerCase();
  if (v.endsWith('/')) v = v.substring(0, v.length - 1);
  return v;
}

/// The scope objects that are in scope but neither marked tested nor referenced
/// by any finding. Reads every `scopeMatrix` slide's rows and cross-references
/// them against the findings' scope objects. Each object is reported once.
List<ScopeGap> deckScopeCoverageGaps(Deck deck) {
  final findingObjects = <String>{
    for (final s in deck.slides)
      if (s.type == SlideType.finding && s.findingRole == FindingRole.header)
        normalizeScopeObject(FindingSpec.parse(s.customMarkdown).scopeObject),
  }..remove('');

  // Per object het óngunstigste oordeel, niet het eerste.
  //
  // De ontdubbeling sloeg toe vóórdat er naar de status werd gekeken, dus won de
  // eerste rij. Stond hetzelfde object op een planningsmatrix als getest en op
  // de uitvoeringsmatrix als niet-getest, dan verdween het gat — en andersom
  // verscheen het weer zodra je de twee dia's van volgorde wisselde. Hetzelfde
  // deck, twee antwoorden.
  final worst = <String, ScopeGap>{};
  final covered = <String>{};
  for (final slide in deck.slides) {
    if (slide.type != SlideType.scopeMatrix) continue;
    final spec = ScopeMatrixSpec.fromSlide(slide.title, slide.tableRows);
    for (final row in spec.rows) {
      final key = normalizeScopeObject(row.object);
      if (key.isEmpty) continue;
      if (row.status.isTested || findingObjects.contains(key)) {
        covered.add(key);
      } else {
        worst.putIfAbsent(
          key,
          () => ScopeGap(object: row.object, type: row.type),
        );
      }
    }
  }
  // Eén niet-getoetste vermelding is genoeg om het een gat te noemen, ook als
  // een andere matrix hetzelfde object wél afvinkt.
  return [for (final e in worst.entries) e.value];
}
