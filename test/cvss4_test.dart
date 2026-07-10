// Oracle-based tests for the native CVSS v4.0 engine (lib/services/cvss/).
//
// Every expected score/severity below was computed by running the official
// FIRST reference calculator (github.com/FIRSTdotorg/cvss-v4-calculator,
// cvss_score.js over cvss_lookup.js / max_composed.js / max_severity.js)
// unchanged over the canonical form of each vector. The fixtures are therefore
// an INDEPENDENT oracle: the Dart engine must reproduce them exactly. They
// cover the all-High base, the all-None zero case, Threat (E:A/E:P/E:U),
// Environmental CR/IR/AR overrides, Modified-metric propagation, the MSI:S /
// MSA:S Safety cases, Supplemental metrics (which never move the score) and a
// spread of Base combinations across every severity band.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/cvss/cvss4.dart';

/// (canonical vector, expected score, expected severity band).
typedef _Fixture = (String, double, Cvss4Severity);

const List<_Fixture> _fixtures = [
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
    10.0,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N',
    0.0,
    Cvss4Severity.none,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
    9.3,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:P/AC:H/AT:P/PR:H/UI:A/VC:N/VI:N/VA:L/SC:N/SI:N/SA:N',
    1.0,
    Cvss4Severity.low,
  ),
  (
    'CVSS:4.0/AV:L/AC:L/AT:N/PR:L/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
    9.3,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:A/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N',
    5.1,
    Cvss4Severity.medium,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N',
    8.7,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:H/AT:P/PR:H/UI:A/VC:L/VI:L/VA:L/SC:L/SI:L/SA:L',
    1.8,
    Cvss4Severity.low,
  ),
  (
    'CVSS:4.0/AV:L/AC:L/AT:N/PR:N/UI:N/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N',
    6.9,
    Cvss4Severity.medium,
  ),
  (
    'CVSS:4.0/AV:P/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N',
    7.0,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/E:A',
    10.0,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/E:P',
    9.3,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/E:U',
    9.1,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N/E:U',
    8.0,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/CR:H/IR:H/AR:H',
    9.3,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/CR:L/IR:L/AR:L',
    8.9,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:L/VA:N/SC:N/SI:N/SA:N/CR:H/IR:M/AR:L',
    8.7,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/MSI:S',
    10.0,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/MSA:S',
    10.0,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:P/AC:H/AT:P/PR:H/UI:A/VC:L/VI:L/VA:L/SC:N/SI:N/SA:N/MSI:S',
    4.1,
    Cvss4Severity.medium,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:N/VA:N/SC:N/SI:N/SA:N/MAV:P/MAC:H',
    1.0,
    Cvss4Severity.low,
  ),
  (
    'CVSS:4.0/AV:P/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/MAV:N',
    10.0,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/MVC:N/MVI:N/MVA:N/MSC:N/MSI:N/MSA:N',
    0.0,
    Cvss4Severity.none,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:L/VI:L/VA:L/SC:N/SI:N/SA:N/S:P/AU:Y/R:A/V:D/RE:L/U:Red',
    5.3,
    Cvss4Severity.medium,
  ),
  (
    'CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:P/VC:L/VI:L/VA:L/SC:L/SI:L/SA:L',
    1.0,
    Cvss4Severity.low,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:L/SI:L/SA:L',
    6.9,
    Cvss4Severity.medium,
  ),
  (
    'CVSS:4.0/AV:L/AC:H/AT:P/PR:H/UI:A/VC:N/VI:N/VA:N/SC:L/SI:N/SA:N',
    1.0,
    Cvss4Severity.low,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:H/SC:N/SI:N/SA:N',
    8.7,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:H/SI:H/SA:H',
    7.9,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:H/SA:N',
    7.7,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/E:U/CR:L/IR:L/AR:L',
    7.9,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:P/AC:H/AT:P/PR:H/UI:A/VC:L/VI:N/VA:N/SC:N/SI:N/SA:N',
    1.0,
    Cvss4Severity.low,
  ),
  (
    'CVSS:4.0/AV:A/AC:L/AT:P/PR:N/UI:N/VC:H/VI:L/VA:L/SC:H/SI:L/SA:N',
    7.2,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:H/VI:H/VA:H/SC:L/SI:L/SA:L/E:P',
    7.4,
    Cvss4Severity.high,
  ),
  (
    'CVSS:4.0/AV:L/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/MSA:S',
    9.8,
    Cvss4Severity.critical,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:N/SI:N/SA:N/E:A/CR:H/IR:H/AR:H',
    6.9,
    Cvss4Severity.medium,
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/E:U/CR:H/IR:H/AR:H/MAV:N/MAC:L/MAT:N/MPR:N/MUI:N/MVC:H/MVI:H/MVA:H/MSC:H/MSI:S/MSA:S/S:N/AU:N/R:A/V:D/RE:L/U:Clear',
    9.5,
    Cvss4Severity.critical,
  ),
];

/// Vectors that must be rejected, with the reason they are invalid.
const List<(String, String)> _invalidVectors = [
  ('', 'empty string'),
  ('CVSS:3.1/AV:N/AC:L', 'wrong version prefix'),
  ('AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H', 'missing prefix'),
  ('CVSS:4.0', 'no metrics at all'),
  ('CVSS:4.0/AV:N', 'only one Base metric present'),
  (
    'CVSS:4.0/AV:N/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
    'Base metric AC omitted',
  ),
  (
    'CVSS:4.0/AC:L/AV:N/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
    'Base metrics AV and AC out of order',
  ),
  (
    'CVSS:4.0/AV:X/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
    'AV:X is not an allowed Base value',
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/E:Z',
    'E:Z is not an allowed Threat value',
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/SI:H',
    'duplicate SI metric',
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/ZZ:Q',
    'unknown metric ZZ',
  ),
  (
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/CR:H/E:A',
    'Threat E after Environmental CR (out of canonical order)',
  ),
  (
    'CVSS:4.0/AVN/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
    'malformed token without a colon',
  ),
  (
    'CVSS:4.0/AV:/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
    'metric with an empty value',
  ),
];

void main() {
  group('score + severity match the FIRST reference oracle', () {
    for (final (vector, expectedScore, expectedSeverity) in _fixtures) {
      test('$vector -> $expectedScore (${expectedSeverity.name})', () {
        final cvss = Cvss4.parseVector(vector);
        expect(cvss.score, expectedScore, reason: vector);
        expect(cvss.severity, expectedSeverity, reason: vector);
      });
    }

    test('has at least 30 representative fixtures', () {
      expect(_fixtures.length, greaterThanOrEqualTo(30));
    });
  });

  group('parse -> build round-trips to the canonical vector string', () {
    for (final (vector, _, _) in _fixtures) {
      test(vector, () {
        expect(Cvss4.parseVector(vector).vector, vector);
      });
    }
  });

  group('invalid vectors are rejected', () {
    for (final (vector, reason) in _invalidVectors) {
      test('rejects: $reason', () {
        expect(
          Cvss4.tryParseVector(vector),
          isNull,
          reason: 'tryParseVector should return null: $reason',
        );
        expect(
          () => Cvss4.parseVector(vector),
          throwsFormatException,
          reason: 'parseVector should throw: $reason',
        );
      });
    }
  });

  group('metric model and accessors', () {
    test('score is clamped into 0.0..10.0', () {
      for (final (vector, _, _) in _fixtures) {
        final score = Cvss4.parseVector(vector).score;
        expect(score, inInclusiveRange(0.0, 10.0), reason: vector);
      }
    });

    test('severity bands follow the FIRST rating scale', () {
      expect(Cvss4Severity.fromScore(0.0), Cvss4Severity.none);
      expect(Cvss4Severity.fromScore(0.1), Cvss4Severity.low);
      expect(Cvss4Severity.fromScore(3.9), Cvss4Severity.low);
      expect(Cvss4Severity.fromScore(4.0), Cvss4Severity.medium);
      expect(Cvss4Severity.fromScore(6.9), Cvss4Severity.medium);
      expect(Cvss4Severity.fromScore(7.0), Cvss4Severity.high);
      expect(Cvss4Severity.fromScore(8.9), Cvss4Severity.high);
      expect(Cvss4Severity.fromScore(9.0), Cvss4Severity.critical);
      expect(Cvss4Severity.fromScore(10.0), Cvss4Severity.critical);
    });

    test('unset optional metrics read as X, Base metrics keep their value', () {
      final cvss = Cvss4.parseVector(
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
      );
      expect(cvss['AV'], 'N');
      expect(cvss['SA'], 'H');
      expect(cvss['E'], 'X');
      expect(cvss['CR'], 'X');
      expect(cvss['MSI'], 'X');
      expect(cvss['NOPE'], isNull);
      expect(cvss.toString(), cvss.vector);
    });

    test('Supplemental metrics never change the score', () {
      const base =
          'CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:L/VI:L/VA:L/SC:N/SI:N/SA:N';
      const withSupplemental = '$base/S:P/AU:Y/R:A/V:D/RE:L/U:Red';
      expect(
        Cvss4.parseVector(withSupplemental).score,
        Cvss4.parseVector(base).score,
      );
    });

    test('a set Modified metric overrides its Base counterpart in scoring', () {
      // Base is all-High (10.0); modifying every impact down to None yields 0.0.
      const vector =
          'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H'
          '/MVC:N/MVI:N/MVA:N/MSC:N/MSI:N/MSA:N';
      final cvss = Cvss4.parseVector(vector);
      expect(cvss.score, 0.0);
      expect(cvss.severity, Cvss4Severity.none);
    });
  });
}
