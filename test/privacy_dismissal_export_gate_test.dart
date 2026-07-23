import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/dismissal_codec.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/privacy_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het paneel en de exportpoort horen hetzelfde te zien (#740).
///
/// Dat deden ze niet. Het filter voor terzijdegelegde bevindingen zat alleen in
/// de paneelprovider; de poort las diezelfde bevindingen langs een andere weg
/// en telde ze nog als onafgehandeld. De export onderbrak dus op iets dat het
/// paneel niet meer toonde — blokkeren zonder aanwijzing, en precies het soort
/// melding dat mensen leren wegklikken.
///
/// Deze toetsen zetten de twee naast elkaar. Geen van de bestaande tests deed
/// dat: de paneeltest keek of de melding verdween, de poorttests keken naar
/// disposities, en het gat lag er tussenin.
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

  DeckDismissals terzijde() => DeckDismissals(
    salt: zout,
    dismissals: [
      PrivacyDismissal(
        ruleId: 'contact.email',
        commitment: commitmentFor(zout, email),
        at: DateTime.utc(2026, 7, 23, 12),
      ),
    ],
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

  test(
    'zonder oordeel houdt de poort de export tegen, en het paneel meldt',
    () async {
      final c = await container(deckMetEmail());
      final samenvatting = c.read(privacyExportSummaryProvider);

      expect(c.read(privacyScanProvider).findings, hasLength(1));
      expect(samenvatting.unresolved, 1);
      expect(samenvatting.setAside, 0);
      expect(
        const PrivacyExportPolicy().evaluate(samenvatting).allowed,
        isFalse,
      );
    },
  );

  test('terzijdegelegd: het paneel zwijgt én de poort laat door', () async {
    // Dit is de bug. Vóór #740 stond hier `unresolved: 1` terwijl het paneel al
    // leeg was: de export vroeg om een bevestiging op iets onzichtbaars.
    final c = await container(deckMetEmail(terzijde: terzijde()));
    final samenvatting = c.read(privacyExportSummaryProvider);

    expect(c.read(privacyScanProvider).findings, isEmpty);
    expect(samenvatting.unresolved, 0);
    expect(
      const PrivacyExportPolicy().evaluate(samenvatting).allowed,
      isTrue,
      reason: 'de poort straft onopgemerkte gegevens af, en dit is opgemerkt',
    );
  });

  test('maar hij verdwijnt niet uit de telling', () async {
    // Doorlaten is niet hetzelfde als oplossen. De samenvatting noemt hem
    // apart, en de ruwe scan — die de nalevingsteller leest — ziet hem gewoon.
    final c = await container(deckMetEmail(terzijde: terzijde()));
    final samenvatting = c.read(privacyExportSummaryProvider);

    expect(samenvatting.setAside, 1);
    expect(samenvatting.total, 1);
    expect(samenvatting.isEmpty, isFalse);
    expect(samenvatting.accepted, 0, reason: 'geen dia-brede acceptatie');
    expect(
      c.read(privacyRawScanProvider).firedRules,
      contains('contact.email'),
    );
  });

  test(
    'paneel en poort zijn het altijd eens over wat er nog open staat',
    () async {
      // De eigenschap waar dit issue over gaat, als bewering: wat het paneel
      // toont is wat de poort tegenhoudt. Loopt dat uiteen, dan blokkeert de
      // export op iets dat de gebruiker niet kan vinden.
      for (final oordeel in [null, terzijde()]) {
        final c = await container(deckMetEmail(terzijde: oordeel));
        expect(
          c.read(privacyExportSummaryProvider).unresolved,
          c.read(privacyScanProvider).findings.length,
          reason: oordeel == null ? 'zonder oordeel' : 'met oordeel',
        );
      }
    },
  );
}
