import 'package:ocideck_form_core/src/form_words.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

void main() {
  group('countFormWords — the shared vectors (FORM_INTAKE.md §4.7)', () {
    for (final v in vectorSection('words')) {
      final text = v['text'] as String;
      test('${v['why']}: ${_show(text)} → ${v['count']}', () {
        expect(countFormWords(text), v['count'] as int);
      });
    }
  });

  group('countFormChars — the shared vectors', () {
    for (final v in vectorSection('chars')) {
      final text = v['text'] as String;
      test('${v['why']}: ${_show(text)} → ${v['count']}', () {
        expect(countFormChars(text), v['count'] as int);
      });
    }
  });

  test('the vector file is large enough to mean something', () {
    expect(vectorSection('words').length, greaterThanOrEqualTo(50));
    expect(vectorSection('chars').length, greaterThanOrEqualTo(15));
  });

  test('line endings never change a count', () {
    const text = 'een twee\n- drie\n> vier\n\nvijf';
    for (final eol in ['\r\n', '\r']) {
      expect(countFormWords(text.replaceAll('\n', eol)), countFormWords(text));
      expect(countFormChars(text.replaceAll('\n', eol)), countFormChars(text));
    }
  });

  test('adding blank lines or surrounding space does not change a count', () {
    expect(countFormWords('\n\n  een twee  \n\n'), 2);
    expect(countFormChars('\n\n  een twee  \n\n'), 8);
  });

  test('a long answer is counted in one pass, quickly', () {
    final text = List.generate(20000, (i) => 'woord$i').join(' ');
    final sw = Stopwatch()..start();
    expect(countFormWords(text), 20000);
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });
}

String _show(String s) => s.length > 40
    ? '"${s.substring(0, 40).replaceAll('\n', r'\n')}…"'
    : '"${s.replaceAll('\n', r'\n').replaceAll('\r', r'\r')}"';
