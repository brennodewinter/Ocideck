import 'package:ocideck_form_core/src/form_jcs.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 8785', () {
    test(
      'section 3.2.3: members are sorted by UTF-16 code unit, not by code point',
      () {
        final input = {
          '\u20ac': 'Euro Sign',
          '\r': 'Carriage Return',
          '\ufb33': 'Hebrew Letter Dalet With Dagesh',
          '1': 'One',
          '\ud83d\ude00': 'Emoji: Grinning Face',
          '\u0080': 'Control',
          '\u00f6': 'Latin Small Letter O With Diaeresis',
        };
        final text = canonicalJson(input);
        // U+1F600 is D83D DE00 in UTF-16, which sorts before U+FB33 although its code
        // point is larger. (The text is compared, not a re-parse of it: a browser's JSON.parse
        // puts integer-like keys first whatever their order in the text.)
        expect(
          text,
          '{"\\r":"Carriage Return","1":"One","\u0080":"Control",'
          '"\u00f6":"Latin Small Letter O With Diaeresis","\u20ac":"Euro Sign",'
          '"\ud83d\ude00":"Emoji: Grinning Face",'
          '"\ufb33":"Hebrew Letter Dalet With Dagesh"}',
        );
      },
    );

    test('section 3.2.2: literals and integers', () {
      expect(
        canonicalJson([null, true, false, 0, -1, 56]),
        '[null,true,false,0,-1,56]',
      );
    });

    test(
      'section 3.2.2: strings keep every character but the ones that must be escaped',
      () {
        expect(
          canonicalJson('\u20ac\$\u000f\nA\'B"\\"/'),
          '"\u20ac\$\\u000f\\nA\'B\\"\\\\\\"/"',
        );
      },
    );
  });

  group('strings', () {
    test('the short escapes, and no others', () {
      expect(canonicalJson('\b\t\n\f\r'), r'"\b\t\n\f\r"');
      expect(canonicalJson('"\\'), r'"\"\\"');
    });

    test('control characters below U+0020 are lower-case \\u00xx', () {
      expect(canonicalJson('\u0000'), r'"\u0000"');
      expect(canonicalJson('\u001f'), r'"\u001f"');
      expect(canonicalJson('\u000b'), r'"\u000b"');
      expect(canonicalJson('\u000e'), r'"\u000e"');
    });

    test(
      'everything else is literal: DEL, the line separators, a space, a solidus',
      () {
        expect(canonicalJson('\u007f'), '"\u007f"');
        expect(canonicalJson('\u2028\u2029'), '"\u2028\u2029"');
        expect(canonicalJson(' /'), '" /"');
        expect(canonicalJson('\u0020'), '" "');
      },
    );

    test('a surrogate pair goes out as it is', () {
      expect(canonicalJson('\u{1F600}'), '"\u{1F600}"');
    });

    test(
      'the first and last surrogates pair up, the code units beside them are not surrogates',
      () {
        // U+10000 is D800 DC00, U+10FFFF is DBFF DFFF; D7FF and E000 are ordinary characters.
        for (final ok in [
          '\ud800\udc00',
          '\ud800\udfff',
          '\udbff\udc00',
          '\udbff\udfff',
          '\ud7ff',
          '\ue000',
          '\ud7ff\ue000',
        ]) {
          expect(canonicalJson(ok), '"$ok"', reason: ok.codeUnits.toString());
        }
        for (final bad in [
          '\ud800',
          '\udbff',
          '\udc00',
          '\udfff',
          '\udbff\udbff',
          '\udfff\udc00',
          'x\udbff',
          '\udc00x',
        ]) {
          expect(
            () => canonicalJson(bad),
            throwsA(isA<FormJcsError>()),
            reason: bad.codeUnits.toString(),
          );
        }
      },
    );

    test('a lone surrogate is refused, high or low, anywhere', () {
      for (final bad in [
        '\ud800',
        '\udc00',
        'a\ud800',
        '\ud800a',
        '\udc00\ud800',
        '\ud800\ud800',
        'a\udc00',
      ]) {
        expect(
          () => canonicalJson(bad),
          throwsA(isA<FormJcsError>()),
          reason: bad.codeUnits.toString(),
        );
      }
      expect(() => canonicalJson({'\ud800': 1}), throwsA(isA<FormJcsError>()));
    });
  });

  group('objects and arrays', () {
    test('the order of insertion does not matter', () {
      expect(canonicalJson({'b': 1, 'a': 2}), canonicalJson({'a': 2, 'b': 1}));
      expect(canonicalJson({'b': 1, 'a': 2}), '{"a":2,"b":1}');
    });

    test('nesting is sorted at every level and arrays keep their order', () {
      expect(
        canonicalJson({
          'z': [3, 1, 2],
          'a': {'y': 1, 'x': null},
        }),
        '{"a":{"x":null,"y":1},"z":[3,1,2]}',
      );
    });

    test('empty ones', () {
      expect(canonicalJson({}), '{}');
      expect(canonicalJson([]), '[]');
      expect(canonicalJson(''), '""');
    });

    test('no white space anywhere', () {
      expect(
        canonicalJson({
          'a': [
            1,
            {'b': 'c d'},
          ],
        }),
        '{"a":[1,{"b":"c d"}]}',
      );
    });

    test('a prefix sorts first, and case matters (upper before lower)', () {
      expect(
        canonicalJson({'ab': 1, 'a': 2, 'B': 3, 'b': 4}),
        '{"B":3,"a":2,"ab":1,"b":4}',
      );
    });
  });

  group('what is outside the subset is refused', () {
    test('a number with a fraction or an exponent', () {
      expect(() => canonicalJson(1.5), throwsA(isA<FormJcsError>()));
      expect(() => canonicalJson(double.nan), throwsA(isA<FormJcsError>()));
      expect(
        () => canonicalJson(double.infinity),
        throwsA(isA<FormJcsError>()),
      );
      expect(() => canonicalJson({'a': 2.5}), throwsA(isA<FormJcsError>()));
      // A whole number written as 1.0 is the integer 1 in a browser (there is one number
      // type there) and a double on the VM; the canonical text is "1" for the first and a
      // refusal for the second, and a bundle field is never written with a point.
      if (1.0 is int) {
        expect(canonicalJson(1.0), '1');
      } else {
        expect(() => canonicalJson(1.0), throwsA(isA<FormJcsError>()));
      }
    });

    test('an integer a browser would round', () {
      const limit = 9007199254740991;
      expect(canonicalJson(limit), '$limit');
      expect(canonicalJson(-limit), '-$limit');
      expect(() => canonicalJson(limit + 1), throwsA(isA<FormJcsError>()));
      expect(() => canonicalJson(-limit - 1), throwsA(isA<FormJcsError>()));
    });

    test('a key that is not a string, a value that is not JSON', () {
      expect(() => canonicalJson({1: 'a'}), throwsA(isA<FormJcsError>()));
      expect(() => canonicalJson(DateTime(2026)), throwsA(isA<FormJcsError>()));
      expect(() => canonicalJson([Object()]), throwsA(isA<FormJcsError>()));
    });

    test('the error says what it is', () {
      try {
        canonicalJson(1.5);
        fail('should throw');
      } on FormJcsError catch (e) {
        expect(e.toString(), contains('FormJcsError'));
        expect(e.message, contains('fraction'));
      }
    });
  });
}
