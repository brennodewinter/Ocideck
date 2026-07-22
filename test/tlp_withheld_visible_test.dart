// Een dia die door haar TLP-classificatie wordt achtergehouden, moet zichtbaar
// achtergehouden zijn.
//
// De valkuil: `deck.tlp` en `slide.tlp` staan allebei standaard op
// `TlpLevel.none`. Wie één dia op AMBER zet in een deck waarvan het deckniveau
// nooit is gezet, raakt die dia kwijt bij presenteren, exporteren én in het
// pakket — zonder teller, plaatshouder of melding. En de "niets te tonen"-tekst
// wees naar *overslaan*, een andere functie met een eigen badge en een eigen
// knop.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Slide slide({TlpLevel tlp = TlpLevel.none, bool skipped = false}) =>
      Slide.create(SlideType.bullets).copyWith(
        title: 'Bevinding',
        bullets: const ['Een'],
        tlp: tlp,
        skipped: skipped,
      );

  group('slideWithheldByTlp', () {
    test('een strengere slide dan het deck wordt achtergehouden', () {
      expect(
        slideWithheldByTlp(slide(tlp: TlpLevel.amber), TlpLevel.none),
        isTrue,
      );
    });

    test('een slide op het deckniveau blijft gewoon zichtbaar', () {
      expect(
        slideWithheldByTlp(slide(tlp: TlpLevel.amber), TlpLevel.amber),
        isFalse,
      );
    });

    test('withheldSlideCount telt tegen het deckniveau', () {
      final deck = Deck(
        title: 'Rapport',
        slides: [
          slide(),
          slide(tlp: TlpLevel.amber),
          slide(tlp: TlpLevel.red),
        ],
      );
      expect(withheldSlideCount(deck), 2);
      expect(withheldSlideCount(deck.copyWith(tlp: TlpLevel.red)), 0);
    });
  });

  group('emptyAudienceReason', () {
    // De tekst moet de échte oorzaak noemen: naar "overslaan" wijzen terwijl het
    // om classificatie gaat, stuurt de gebruiker naar de verkeerde knop.
    const l10n = AppLocalizations(Locale('nl'));

    Deck deckOf(List<Slide> slides) => Deck(title: 'R', slides: slides);

    test('alleen achtergehouden: de tekst noemt TLP, niet overslaan', () {
      final text = emptyAudienceReason(
        l10n,
        deckOf([slide(tlp: TlpLevel.amber)]),
        forExport: false,
      );
      expect(text, contains('achtergehouden'));
      expect(text, contains('TLP'));
      expect(text, isNot(contains('overgeslagen')));
    });

    test('alleen overgeslagen: de oude tekst blijft staan', () {
      final text = emptyAudienceReason(
        l10n,
        deckOf([slide(skipped: true)]),
        forExport: false,
      );
      expect(text, 'Alle slides zijn overgeslagen — niets om te tonen.');
    });

    test('allebei: de tekst houdt de twee uit elkaar', () {
      final text = emptyAudienceReason(
        l10n,
        deckOf([slide(skipped: true), slide(tlp: TlpLevel.amber)]),
        forExport: false,
      );
      expect(text, contains('overgeslagen'));
      expect(text, contains('achtergehouden'));
    });

    test('exporteren krijgt zijn eigen werkwoord', () {
      final text = emptyAudienceReason(
        l10n,
        deckOf([slide(tlp: TlpLevel.amber)]),
        forExport: true,
      );
      expect(text, contains('exporteren'));
    });
  });

  testWidgets('de diastrook markeert een achtergehouden slide', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(deckProvider.notifier)
        .loadDeck(
          Deck(
            title: 'Rapport',
            slides: [
              slide(),
              slide(tlp: TlpLevel.amber),
            ],
          ),
        );

    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              height: 720,
              child: SlideListPanel(railWidth: 320),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Het vlaggetje op de dia zelf...
    expect(find.text('Achtergehouden'), findsOneWidget);
    // ...én de balk bovenaan, zodat het ook opvalt zonder scrollen.
    expect(find.text('1 slide achtergehouden door haar TLP'), findsOneWidget);
    // En het blijft onderscheiden van overslaan: die badge staat er niet.
    expect(find.text('Overgeslagen'), findsNothing);
  });
}
