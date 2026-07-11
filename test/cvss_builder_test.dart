import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cvss_builder.dart';
import 'package:ocideck/services/cvss/cvss4.dart';

void main() {
  group('kCvss4BaseMetrics', () {
    test('models all 11 Base metrics in canonical order', () {
      expect(kCvss4BaseMetrics.map((m) => m.code), [
        'AV',
        'AC',
        'AT',
        'PR',
        'UI',
        'VC',
        'VI',
        'VA',
        'SC',
        'SI',
        'SA',
      ]);
      for (final m in kCvss4BaseMetrics) {
        expect(m.options, isNotEmpty, reason: m.code);
      }
    });
  });

  group('assembleCvss4Vector', () {
    test('defaults produce a parseable canonical vector', () {
      final vector = assembleCvss4Vector(const {});
      expect(vector, startsWith('CVSS:4.0/'));
      expect(Cvss4.tryParseVector(vector), isNotNull);
    });

    test('chosen tokens land in the vector', () {
      final vector = assembleCvss4Vector(const {
        'AV': 'N',
        'AC': 'L',
        'VC': 'H',
        'VI': 'H',
      });
      expect(vector, contains('AV:N'));
      expect(vector, contains('VC:H'));
      expect(Cvss4.tryParseVector(vector), isNotNull);
    });

    test('a set CIA rating appends CR/IR/AR in order', () {
      final vector = assembleCvss4Vector(
        const {},
        cia: const CiaRating(
          confidentiality: CiaLevel.high,
          integrity: CiaLevel.medium,
          availability: CiaLevel.low,
        ),
      );
      expect(vector, contains('/CR:H/IR:M/AR:L'));
      expect(Cvss4.tryParseVector(vector), isNotNull);
    });

    test('an unset CIA dimension is omitted', () {
      final vector = assembleCvss4Vector(
        const {},
        cia: const CiaRating(confidentiality: CiaLevel.high),
      );
      expect(vector, contains('CR:H'));
      expect(vector, isNot(contains('IR:')));
      expect(vector, isNot(contains('AR:')));
    });
  });

  group('CIA weighting shifts the CVSS score', () {
    // A high-impact base finding (full confidentiality/integrity/availability
    // impact, easy to exploit).
    const base = {
      'AV': 'N',
      'AC': 'L',
      'AT': 'N',
      'PR': 'N',
      'UI': 'N',
      'VC': 'H',
      'VI': 'H',
      'VA': 'H',
      'SC': 'N',
      'SI': 'N',
      'SA': 'N',
    };

    test('all-High CIA equals no CIA (X defaults to High)', () {
      final none = Cvss4.tryParseVector(assembleCvss4Vector(base))!;
      final high = Cvss4.tryParseVector(
        assembleCvss4Vector(
          base,
          cia: const CiaRating(
            confidentiality: CiaLevel.high,
            integrity: CiaLevel.high,
            availability: CiaLevel.high,
          ),
        ),
      )!;
      expect(high.score, none.score);
    });

    test('a low CIA rating lowers the score below the base', () {
      final none = Cvss4.tryParseVector(assembleCvss4Vector(base))!;
      final low = Cvss4.tryParseVector(
        assembleCvss4Vector(
          base,
          cia: const CiaRating(
            confidentiality: CiaLevel.low,
            integrity: CiaLevel.low,
            availability: CiaLevel.low,
          ),
        ),
      )!;
      expect(low.score, lessThan(none.score));
    });
  });

  group('CiaRating', () {
    test('toEnvironmental maps the three dimensions to CR/IR/AR', () {
      const r = CiaRating(
        confidentiality: CiaLevel.high,
        integrity: CiaLevel.low,
      );
      expect(r.toEnvironmental(), {'CR': 'H', 'IR': 'L', 'AR': 'X'});
      expect(r.isDefined, isTrue);
    });

    test('an empty rating is not defined', () {
      expect(const CiaRating().isDefined, isFalse);
    });
  });
}
