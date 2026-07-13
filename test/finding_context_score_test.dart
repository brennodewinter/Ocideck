import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cvss_builder.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/finding_context_score.dart';

const _baseVector =
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N';

Slide _scopeSlide(List<ScopeRow> rows) =>
    Slide.create(SlideType.scopeMatrix).copyWith(
      title: 'Scope',
      tableRows: ScopeMatrixSpec(title: 'Scope', rows: rows).toTableRows(),
    );

void main() {
  group('deckScopeCiaIndex', () {
    test('indexes only rated rows, keyed by the normalised object', () {
      final slide = _scopeSlide(const [
        ScopeRow(
          object: 'https://app.example/',
          cia: CiaRating(
            confidentiality: CiaLevel.low,
            integrity: CiaLevel.low,
            availability: CiaLevel.low,
          ),
        ),
        ScopeRow(object: '10.0.0.0/24'), // unrated -> absent
      ]);
      final index = deckScopeCiaIndex([slide]);
      // The trailing slash is normalised away, so a finding's own spelling matches.
      expect(index.keys, ['https://app.example']);
      expect(index['https://app.example']!.confidentiality, CiaLevel.low);
    });

    test('is empty when no scope object is rated', () {
      final slide = _scopeSlide(const [ScopeRow(object: 'a.example')]);
      expect(deckScopeCiaIndex([slide]), isEmpty);
    });
  });

  group('findingContextCvss', () {
    final index = deckScopeCiaIndex([
      _scopeSlide(const [
        ScopeRow(
          object: 'https://app.example',
          cia: CiaRating(
            confidentiality: CiaLevel.low,
            integrity: CiaLevel.low,
            availability: CiaLevel.low,
          ),
        ),
      ]),
    ]);

    test('weights a matching finding by its scope object rating', () {
      const spec = FindingSpec(
        scopeObject: 'https://app.example',
        cvssVector: _baseVector,
      );
      final ctx = findingContextCvss(spec, index);
      expect(ctx, isNotNull);
      expect(ctx!.score, 8.9); // base 9.3 lowered by the low CIA rating
      expect(findingEffectiveSeverity(spec, index), Cvss4Severity.high);
    });

    test('falls back to base when the scope object is not rated', () {
      const spec = FindingSpec(
        scopeObject: 'https://other.example',
        cvssVector: _baseVector,
      );
      expect(findingContextCvss(spec, index), isNull);
      // Effective severity is then the base band (9.3 -> Critical).
      expect(findingEffectiveSeverity(spec, index), Cvss4Severity.critical);
    });

    test('null for an empty index or an empty scope object', () {
      const spec = FindingSpec(scopeObject: '', cvssVector: _baseVector);
      expect(findingContextCvss(spec, const {}), isNull);
      expect(findingContextCvss(spec, index), isNull);
    });
  });
}
