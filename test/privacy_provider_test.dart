import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/privacy_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Deck deckMetEmail() => Deck(
    title: 'Briefing',
    slides: [
      Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: ['contact j.jansen@politie.nl']),
    ],
  );

  Future<ProviderContainer> container({required bool checksEnabled}) async {
    SharedPreferences.setMockInitialValues({
      'privacyChecksEnabled': checksEnabled,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // De notifier start een asynchrone load uit de prefs; laat die eerst rond
    // komen, anders lees je de defaults in plaats van de mock.
    c.read(settingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.read(deckProvider.notifier).loadDeck(deckMetEmail());
    return c;
  }

  test('de scan vindt de bevinding wanneer de controle aan staat', () async {
    final c = await container(checksEnabled: true);
    final result = c.read(privacyScanProvider);

    expect(result.firedRules, contains('contact.email'));
    expect(c.read(privacyQualityIssuesProvider), hasLength(1));
  });

  test(
    'uit betekent: de scan draait niet — niet: de melding is verborgen',
    () async {
      final c = await container(checksEnabled: false);

      expect(c.read(privacyScanProvider).isEmpty, isTrue);
      expect(c.read(privacyQualityIssuesProvider), isEmpty);
    },
  );

  test('de controle staat standaard aan', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(settingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(c.read(settingsProvider).privacyChecksEnabled, isTrue);
  });
}
