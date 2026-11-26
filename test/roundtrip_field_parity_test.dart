@Tags(['registration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../tool/check_roundtrip_field_parity.dart' as gate;

void main() {
  test('the real inventories reject a newly added unsaved field', () {
    final cases = File(gate.roundtripCasesPath).readAsStringSync();
    for (final spec in [
      ('Slide', 'lib/models/slide.dart', 'slideRoundtripCases', 'slideCase'),
      (
        'ThemeProfile',
        'lib/models/settings.dart',
        'themeRoundtripCases',
        'themeCase',
      ),
    ]) {
      final source = File(spec.$2).readAsStringSync();
      final probes = gate.caseFields(cases, spec.$3, spec.$4);
      final excluded = gate.roundtripExclusions[spec.$1]!;
      expect(
        gate.roundtripParityProblems(
          gate.modelFields(source, spec.$1),
          probes,
          exclusions: excluded,
        ),
        isEmpty,
      );
      final changed = source.replaceFirst(
        'class ${spec.$1} {',
        'class ${spec.$1} { final int unsavedProbe = 42;',
      );
      expect(
        gate.roundtripParityProblems(
          gate.modelFields(changed, spec.$1),
          probes,
          exclusions: excluded,
        ),
        ['unsavedProbe: no executable roundtrip case or documented exclusion'],
      );
    }
  });
  const model = '''
class Slide {
  final String title;
  int newUnsavedField = 0;
  final int a = 1, b = 2;
  static const cache = 0;
  String get derived => title;
}
class Other { final int ignored = 0; }
''';
  test(
    'new mutable, initialized and multiple instance fields are inventoried',
    () {
      final fields = gate.modelFields(model, 'Slide');
      expect(fields, {'title', 'newUnsavedField', 'a', 'b'});
      expect(gate.roundtripParityProblems(fields, {'title', 'a', 'b'}), [
        'newUnsavedField: no executable roundtrip case or documented exclusion',
      ]);
    },
  );
  test(
    'classifications reject stale entries, overlap, empty reasons and new debt',
    () {
      expect(gate.roundtripParityProblems({'title'}, {'title'}), isEmpty);
      expect(
        gate.roundtripParityProblems(
          {'title'},
          {},
          exclusions: {'title': 'Transient'},
        ),
        isEmpty,
      );
      expect(
        gate.roundtripParityProblems({'title'}, {'title', 'removed'}),
        isNotEmpty,
      );
      expect(
        gate.roundtripParityProblems(
          {'title'},
          {'title'},
          exclusions: {'title': 'Transient'},
        ),
        isNotEmpty,
      );
      expect(
        gate.roundtripParityProblems({'title'}, {}, exclusions: {'title': ' '}),
        isNotEmpty,
      );
      expect(
        gate.roundtripParityProblems({'title'}, {}, debt: {'title'}),
        isNotEmpty,
      );
    },
  );

  String cases(String entries) => 'final probes = <String, Object>{$entries};';
  Set<String> read(String source) =>
      gate.caseFields(source, 'probes', 'slideCase');
  const probe =
      "'title': slideCase(type, (s) => s.copyWith(title: 'Changed'), (s) => s.title)";
  test(
    'inventory reads the same executable getter and fixture used at runtime',
    () {
      expect(read(cases(probe)), {'title'});
      expect(
        () => read(cases(probe.replaceAll('s.title)', 's.subtitle)'))),
        throwsFormatException,
      );
      expect(
        () => read(
          cases(probe.replaceAll('copyWith(title:', 'copyWith(subtitle:')),
        ),
        throwsFormatException,
      );
      expect(() => read(cases("$probe, $probe")), throwsFormatException);
      expect(() => read(cases("'title': 'title'")), throwsFormatException);
      expect(() => read(cases('...other')), throwsFormatException);
      expect(() => read(cases('')), throwsFormatException);
      expect(
        () => gate.modelFields('class Other {}', 'Slide'),
        throwsFormatException,
      );
    },
  );
}
