import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

void main() {
  group('supportsFormRules', () {
    test('accepts exactly the versions this engine implements', () {
      expect(supportsFormRules(1), isTrue);
      expect(supportsFormRules(kFormRulesVersion), isTrue);
    });

    test('refuses a form that needs a newer client', () {
      expect(supportsFormRules(kFormRulesVersion + 1), isFalse);
    });

    test('refuses a malformed declaration', () {
      expect(supportsFormRules(0), isFalse);
      expect(supportsFormRules(-1), isFalse);
    });
  });
}
