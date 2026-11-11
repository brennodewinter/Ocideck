import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bouw een notifier op gemockte prefs en wacht tot de async [_load] klaar is.
/// Keert ook de prefs zelf terug zodat een test de quarantainesleutels kan
/// lezen.
Future<(SettingsNotifier, SharedPreferences)> _loadWith(
  Map<String, Object> values,
) async {
  SharedPreferences.setMockInitialValues(values);
  final notifier = SettingsNotifier();
  await Future<void>.delayed(const Duration(milliseconds: 60));
  return (notifier, await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // #2888: één rot voorkeursonderdeel mag de rest van de lading niet kosten.
  group('laad-isolatie per voorkeuronderdeel', () {
    test(
      'een verkeerd topniveau kost alleen de profielen, niet de rest',
      () async {
        const raw = '{"geen":"lijst"}';
        final (n, prefs) = await _loadWith({
          'themeProfiles': raw,
          'languageCode': 'en',
        });
        expect(n.currentState.languageCode, 'en');
        // De lijst degradeert naar de bestaande leeg-vloer (één default
        // profiel, _uniqueProfiles), niet naar een crash of een half beeld.
        expect(n.currentState.themeProfiles, isNotEmpty);
        // ...en de oorspronkelijke bytes blijven als herstelkopie staan.
        expect(prefs.getString('themeProfiles.refused'), raw);
      },
    );

    test('een kapot profiel kost zijn geldige buren niet', () async {
      const raw =
          '[{"name":"Bewaard","isBuiltIn":false},'
          '"geen-map",'
          '{"name":"OokBewaard","isBuiltIn":false}]';
      final (n, prefs) = await _loadWith({'themeProfiles': raw});
      final names = n.currentState.themeProfiles.map((p) => p.name).toList();
      expect(names, containsAll(['Bewaard', 'OokBewaard']));
      expect(prefs.getString('themeProfiles.refused'), raw);
    });

    test('verkeerde veldtypen vallen per veld terug, geen weigering', () async {
      final (n, prefs) = await _loadWith({
        'themeProfiles': '[{"name":"VeldFout","logoSize":"96"}]',
      });
      final profile = n.currentState.themeProfiles.firstWhere(
        (p) => p.name == 'VeldFout',
      );
      expect(profile.logoSize, 96);
      expect(prefs.getString('themeProfiles.refused'), isNull);
    });

    test('een kapot legacy thema-profiel gaat in quarantaine', () async {
      const raw = 'dit is geen json';
      final (n, prefs) = await _loadWith({'themeProfile': raw});
      expect(n.currentState.themeProfiles, isNotEmpty);
      expect(prefs.getString('themeProfile.refused'), raw);
    });

    test('ongeldige appearance-data laat de rest laden', () async {
      const raw = '[{"name":"Kapot","isDark":"ja"}]';
      final (n, prefs) = await _loadWith({
        'appAppearanceProfiles': raw,
        'languageCode': 'en',
      });
      expect(n.currentState.languageCode, 'en');
      // Geen kapot custom-profiel: alleen de ingebouwde verschijningsvormen.
      expect(
        n.currentState.appAppearanceProfiles.every((p) => p.isBuiltIn),
        isTrue,
      );
      expect(prefs.getString('appAppearanceProfiles.refused'), raw);
    });

    test(
      'een voorkeurswaarde met verkeerd type valt terug op de default',
      () async {
        final (n, _) = await _loadWith({
          'privacyChecksEnabled': 'ja', // String waar een bool hoort
          'languageCode': 'en',
        });
        expect(n.currentState.privacyChecksEnabled, isTrue);
        expect(n.currentState.languageCode, 'en');
      },
    );

    test('opslaan houdt de geweigerde bytes als quarantaine-kopie', () async {
      const raw = '[{"name":"Bewaard"},null]';
      final (n, prefs) = await _loadWith({'themeProfiles': raw});
      await n.persistThemeProfiles();
      // De gewone sleutel is weer schoon geschreven...
      final stored = jsonDecode(prefs.getString('themeProfiles')!) as List;
      expect(stored, isNotEmpty);
      // ...en de oorspronkelijke bytes zijn onveranderd bewaard.
      expect(prefs.getString('themeProfiles.refused'), raw);
    });

    test('weigeringen zijn observeerbaar via loadIssues', () async {
      SharedPreferences.setMockInitialValues({'themeProfiles': '{"x":1}'});
      // Gelijk na constructie abonneren: _load wacht zelf eerst async op de
      // store, dus de events komen pas ná deze subscription binnen.
      final n = SettingsNotifier();
      final seen = <String>[];
      final sub = n.loadIssues.listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(seen, contains('themeProfiles'));
      await sub.cancel();
      n.dispose();
    });
  });
}
