import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/dismissal_codec.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/privacy_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een terzijdegelegde bevinding verdwijnt uit het paneel, en **nergens
/// anders** (#651, FILE_FORMAT §6.7).
///
/// Dat onderscheid is de hele reden dat de ruwe scan bestaat. Zou een
/// terzijdelegging ook daar wegvallen, dan begon de nalevingstelling die MIAUW
/// EIS 1.1 leest een schoonheid te melden die het deck niet heeft — en dan is
/// het verschil tussen "beoordeeld en akkoord" en "opgelost" weg.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const email = 'j.jansen@andersbureau.nl';
  const zout = '0123456789abcdef0123456789abcdef';

  Deck deckMetEmail({DeckDismissals? terzijde}) => Deck(
    title: 'Briefing',
    slides: [
      Slide.create(SlideType.bullets).copyWith(bullets: ['contact $email']),
    ],
    dismissals: terzijde,
  );

  Future<ProviderContainer> container(Deck deck) async {
    SharedPreferences.setMockInitialValues({'privacyChecksEnabled': true});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(settingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.read(deckProvider.notifier).loadDeck(deck);
    return c;
  }

  DeckDismissals terzijde({DateTime? herroepenOp}) => DeckDismissals(
    salt: zout,
    dismissals: [
      PrivacyDismissal(
        ruleId: 'contact.email',
        commitment: commitmentFor(zout, email),
        at: DateTime.utc(2026, 7, 23, 12),
      ),
    ],
    revocations: [
      if (herroepenOp != null)
        PrivacyDismissal(
          ruleId: 'contact.email',
          commitment: commitmentFor(zout, email),
          at: herroepenOp,
        ),
    ],
  );

  test(
    'zonder terzijdelegging staat de bevinding gewoon in het paneel',
    () async {
      final c = await container(deckMetEmail());
      expect(c.read(privacyScanProvider).firedRules, contains('contact.email'));
      expect(c.read(privacyQualityIssuesProvider), hasLength(1));
    },
  );

  test('terzijdegelegd verdwijnt uit het paneel', () async {
    final c = await container(deckMetEmail(terzijde: terzijde()));
    expect(c.read(privacyScanProvider).isEmpty, isTrue);
    expect(c.read(privacyQualityIssuesProvider), isEmpty);
  });

  test('maar de ruwe scan blijft hem zien', () async {
    // Verbergen is geen wegscannen. Hier hangt de telling aan die MIAUW EIS 1.1
    // leest; die mag niet meebewegen met een oordeel van de auteur.
    final c = await container(deckMetEmail(terzijde: terzijde()));
    expect(
      c.read(privacyRawScanProvider).firedRules,
      contains('contact.email'),
    );
  });

  test('een herroeping brengt hem terug', () async {
    final c = await container(
      deckMetEmail(
        terzijde: terzijde(herroepenOp: DateTime.utc(2026, 7, 23, 13)),
      ),
    );
    expect(c.read(privacyScanProvider).firedRules, contains('contact.email'));
  });

  test('een oordeel over een ándere waarde verbergt niets', () async {
    final c = await container(
      deckMetEmail(
        terzijde: DeckDismissals(
          salt: zout,
          dismissals: [
            PrivacyDismissal(
              ruleId: 'contact.email',
              commitment: commitmentFor(zout, 'iemand.anders@voorbeeld.nl'),
              at: DateTime.utc(2026, 7, 23, 12),
            ),
          ],
        ),
      ),
    );
    expect(c.read(privacyScanProvider).firedRules, contains('contact.email'));
  });

  test('een oordeel onder een ánder zout verbergt niets', () async {
    // Het zout hoort bij het deck. Komt de sidecar van elders, dan slaan zijn
    // commitments hier nergens op, en dan moet er niets verdwijnen.
    final c = await container(
      deckMetEmail(
        terzijde: DeckDismissals(
          salt: 'ffffffffffffffffffffffffffffffff',
          dismissals: [
            PrivacyDismissal(
              ruleId: 'contact.email',
              commitment: commitmentFor(zout, email),
              at: DateTime.utc(2026, 7, 23, 12),
            ),
          ],
        ),
      ),
    );
    expect(c.read(privacyScanProvider).firedRules, contains('contact.email'));
  });
}
