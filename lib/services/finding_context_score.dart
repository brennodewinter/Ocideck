import '../models/cvss_builder.dart';
import '../models/finding_spec.dart';
import '../models/scope_matrix_spec.dart';
import '../models/slide.dart';
import 'cvss/cvss4.dart';
import 'scope_coverage.dart';

/// Context-score wiring (PENTEST_MIAUW §10.5): a finding's **context
/// (environmental) score** is derived live from the CIA rating of the scope
/// object it references. The rating lives on the scope matrix (`ScopeRow.cia`),
/// so the score is never baked into the finding — changing a scope object's
/// rating re-scores every finding that points at it.

/// The scope-object → CIA-rating index for [rows]. Only rows with a defined
/// rating are included; the key is the normalised scope-object string (see
/// [normalizeScopeObject]) so it matches a finding's own, independently
/// free-typed, scope object. When two rows name the same object, the later wins.
Map<String, CiaRating> scopeCiaIndexFromRows(Iterable<ScopeRow> rows) {
  final index = <String, CiaRating>{};
  for (final row in rows) {
    if (!row.cia.isDefined) continue;
    final key = normalizeScopeObject(row.object);
    if (key.isEmpty) continue;
    index[key] = row.cia;
  }
  return index;
}

/// Every scope object across all `scopeMatrix` slides in [slides], in document
/// order. Feeds both the CIA index and the finding-editor/wizard scope-object
/// pickers.
List<ScopeRow> deckScopeRows(Iterable<Slide> slides) => [
  for (final slide in slides)
    if (slide.type == SlideType.scopeMatrix)
      ...ScopeMatrixSpec.fromSlide(slide.title, slide.tableRows).rows,
];

/// The scope-object → CIA-rating index built from every `scopeMatrix` slide in
/// [slides]. See [scopeCiaIndexFromRows].
Map<String, CiaRating> deckScopeCiaIndex(Iterable<Slide> slides) =>
    scopeCiaIndexFromRows(deckScopeRows(slides));

/// The CIA rating of the scope object named [object] in [index], or an empty
/// rating when it is not rated. Matches on the normalised object string.
CiaRating scopeObjectCia(String object, Map<String, CiaRating> index) =>
    index[normalizeScopeObject(object)] ?? const CiaRating();

/// The context (environmental) [Cvss4] for [spec], or `null` when its scope
/// object has no CIA rating in [index] or its base vector does not parse — the
/// caller then falls back to the base score. See [contextCvss].
Cvss4? findingContextCvss(FindingSpec spec, Map<String, CiaRating> index) {
  if (index.isEmpty || spec.scopeObject.isEmpty) return null;
  final cia = index[normalizeScopeObject(spec.scopeObject)];
  if (cia == null) return null;
  return contextCvss(spec.cvssVector, cia);
}

/// The severity band shown for [spec] given the deck's CIA [index]: the context
/// band when a rating applies, otherwise the base band (or `null` when there is
/// no valid vector). This is the "effective" severity used by previews and the
/// management roll-up so a finding reads consistently everywhere.
Cvss4Severity? findingEffectiveSeverity(
  FindingSpec spec,
  Map<String, CiaRating> index,
) => (findingContextCvss(spec, index) ?? spec.cvss)?.severity;
