import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/document_style.dart';

void main() {
  // A settings object with the three built-in style profiles.
  AppSettings settingsWith({String? defaultStyle, bool enforced = false}) =>
      AppSettings(
        documentDefaultStyle: defaultStyle,
        documentStyleEnforced: enforced,
      );

  group('resolveDocumentStyleProfile', () {
    test('null when the document has no style and there is no default', () {
      expect(resolveDocumentStyleProfile(settingsWith(), null), isNull);
    });

    test("the document's own style wins by name", () {
      final p = resolveDocumentStyleProfile(settingsWith(), 'Security');
      expect(p?.name, 'Security');
    });

    test('the settings default applies when the document has none', () {
      final p = resolveDocumentStyleProfile(
        settingsWith(defaultStyle: 'LibreKAT'),
        null,
      );
      expect(p?.name, 'LibreKAT');
    });

    test('an enforced house style overrides the per-document choice', () {
      final p = resolveDocumentStyleProfile(
        settingsWith(defaultStyle: 'LibreKAT', enforced: true),
        'Security',
      );
      expect(p?.name, 'LibreKAT');
    });

    test('enforce with no default falls back to the document style', () {
      final p = resolveDocumentStyleProfile(
        settingsWith(enforced: true),
        'Security',
      );
      expect(p?.name, 'Security');
    });

    test('an unknown name falls through, never throws', () {
      expect(
        resolveDocumentStyleProfile(settingsWith(), 'Bestaat niet'),
        isNull,
      );
      final p = resolveDocumentStyleProfile(
        settingsWith(defaultStyle: 'Security'),
        'Bestaat niet',
      );
      expect(p?.name, 'Security');
    });
  });

  group('effectiveDocumentStyleName', () {
    test('the document choice when not enforced', () {
      expect(
        effectiveDocumentStyleName(settingsWith(), 'Security'),
        'Security',
      );
      expect(effectiveDocumentStyleName(settingsWith(), null), isNull);
    });

    test('the enforced default when enforced', () {
      expect(
        effectiveDocumentStyleName(
          settingsWith(defaultStyle: 'LibreKAT', enforced: true),
          'Security',
        ),
        'LibreKAT',
      );
    });
  });
}
