import 'package:ocideck_form_core/src/form_field_types.dart';
import 'package:ocideck_form_core/src/form_patterns.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

void main() {
  final patterns = (loadVectors()['patterns'] as Map).cast<String, dynamic>();

  test(
    'every named pattern the registry allows has vectors, and vice versa',
    () {
      final allowed = kFormFieldTypes['text']!.rule('pattern')!.values.toSet();
      expect(patterns.keys.toSet(), allowed);
      expect(kFormPatternNames.toSet(), allowed);
    },
  );

  for (final entry in patterns.entries) {
    group('${entry.key} — the shared vectors', () {
      for (final v in (entry.value as List).cast<Map<String, dynamic>>()) {
        final text = v['text'] as String;
        final valid = v['valid'] as bool;
        test(
          '${valid ? 'accepts' : 'refuses'} "${text.replaceAll('\n', r'\n')}" (${v['why']})',
          () {
            expect(matchesFormPattern(entry.key, text), valid);
          },
        );
      }
    });
  }

  test('an unknown pattern name matches nothing (fail closed)', () {
    expect(matchesFormPattern('nope', 'a@b.nl'), isFalse);
    expect(matchesFormPattern('', ''), isFalse);
    expect(
      matchesFormPattern('Email', 'a@b.nl'),
      isFalse,
      reason: 'case-sensitive',
    );
  });

  test('a hostile input is judged in linear time', () {
    final evil = '${'a' * 50000}@${'b.' * 20000}';
    final sw = Stopwatch()..start();
    for (final name in kFormPatternNames) {
      matchesFormPattern(name, evil);
    }
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });
}
