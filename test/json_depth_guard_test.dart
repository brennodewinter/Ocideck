import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/json_depth_guard.dart';

void main() {
  group('jsonDecodeGuarded', () {
    test('gewone JSON decodeert normaal', () {
      expect(jsonDecodeGuarded('{"a": 1}'), {'a': 1});
      expect(jsonDecodeGuarded('[1, 2, 3]'), [1, 2, 3]);
    });

    test('JSON met brackets in string-waarden telt niet mee', () {
      // Een string die "[{" bevat mag geen vals alarm geven.
      final result = jsonDecodeGuarded('{"text": "hello [world] {test}"}');
      expect(result, {'text': 'hello [world] {test}'});
    });

    test('een string met escaped quotes wordt correct geparseerd', () {
      final result = jsonDecodeGuarded(r'{"text": "say \"hello\" [bracket]"}');
      expect(result, {'text': 'say "hello" [bracket]'});
    });

    test('diep geneste input wordt geweigerd vóór jsonDecode', () {
      // Bouw een string die dieper nest dan de limiet — dit zou jsonDecode
      // laten crashen met een StackOverflowError, maar de guard vangt hem
      // vóór die aanroep.
      final deep =
          '[' * (kMaxJsonNestingDepth + 10) + ']' * (kMaxJsonNestingDepth + 10);
      expect(() => jsonDecodeGuarded(deep), throwsA(isA<FormatException>()));
    });

    test('geneste input binnen de limiet decodeert normaal', () {
      final nested = '${'[' * 10}1${']' * 10}';
      expect(jsonDecodeGuarded(nested), isNotNull);
    });

    test('een syntax-fout geeft nog steeds een FormatException', () {
      expect(
        () => jsonDecodeGuarded('{invalid}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('de pre-scan is string-aware: een [ in een string verhoogt niet', () {
      // Dit zou een vals alarm zijn als de scan string-literalen negeerde.
      final json = '{"key": "${'[' * 1000}"}';
      expect(jsonDecodeGuarded(json), {'key': '[' * 1000});
    });
  });
}
