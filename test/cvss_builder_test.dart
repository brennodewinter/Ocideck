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

  group('CiaLevel.fromToken', () {
    test('maps the Environmental tokens', () {
      expect(CiaLevel.fromToken('H'), CiaLevel.high);
      expect(CiaLevel.fromToken('m'), CiaLevel.medium);
      expect(CiaLevel.fromToken(' L '), CiaLevel.low);
    });

    test('X, empty and anything unknown read as notDefined', () {
      expect(CiaLevel.fromToken('X'), CiaLevel.notDefined);
      expect(CiaLevel.fromToken(''), CiaLevel.notDefined);
      expect(CiaLevel.fromToken('?'), CiaLevel.notDefined);
    });
  });

  group('Cvss4.withEnvironmental', () {
    // Oracle-backed base vector: it scores 9.3 (Critical) on its own (see
    // cvss4_test.dart), and a low CR/IR/AR lowers it to 8.9 (High).
    const baseVector =
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N';

    test('low security requirements lower the score', () {
      final base = Cvss4.parseVector(baseVector);
      final ctx = base.withEnvironmental(cr: 'L', ir: 'L', ar: 'L');
      expect(base.score, 9.3);
      expect(ctx.score, 8.9);
      expect(ctx.severity, Cvss4Severity.high);
    });

    test('default (X) requirements leave the score unchanged', () {
      final base = Cvss4.parseVector(baseVector);
      expect(base.withEnvironmental().score, base.score);
    });

    test('preserves the Base metrics and stays parseable', () {
      final ctx = Cvss4.parseVector(baseVector).withEnvironmental(cr: 'H');
      expect(ctx['VC'], 'H');
      expect(ctx['CR'], 'H');
      expect(Cvss4.tryParseVector(ctx.vector), isNotNull);
    });

    test('an unrecognised token clamps to Not Defined', () {
      final ctx = Cvss4.parseVector(baseVector).withEnvironmental(cr: 'bogus');
      expect(ctx['CR'], 'X');
    });
  });

  group('contextCvss', () {
    const baseVector =
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N';

    test('weights the base score by a defined rating', () {
      final ctx = contextCvss(
        baseVector,
        const CiaRating(
          confidentiality: CiaLevel.low,
          integrity: CiaLevel.low,
          availability: CiaLevel.low,
        ),
      );
      expect(ctx, isNotNull);
      expect(ctx!.score, 8.9);
    });

    test('an undefined rating yields null (render the base score)', () {
      expect(contextCvss(baseVector, const CiaRating()), isNull);
    });

    test('an unparseable base vector yields null', () {
      expect(
        contextCvss(
          'not a vector',
          const CiaRating(confidentiality: CiaLevel.high),
        ),
        isNull,
      );
    });
  });
}
