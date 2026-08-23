// Wat de gebruiker te horen krijgt vóórdat een afbeelding het apparaat verlaat.
//
// Voor tekst bestaat een projectiegrens; voor een afbeelding niet, en dat kán
// ook niet — de projectie vervangt tekens en in een JPEG staan er geen. Wat er
// in de plaats van staat is deze dialoog, en dus is de bewóórding hier de
// waarborg. Als die stilvalt, valt de waarborg stil.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/widgets/dialogs/ai_image_outbound_dialog.dart';

import 'support/pump_until.dart';

const _cloud = AiSettings(
  enabled: true,
  mode: AiBackendMode.cloud,
  baseUrl: 'https://model.voorbeeld.example/v1',
  model: 'iets',
);

const _lokaal = AiSettings(
  enabled: true,
  mode: AiBackendMode.local,
  baseUrl: 'http://127.0.0.1:11434/v1',
  model: 'iets',
);

void main() {
  // Een gemiste tik telt hier als een fout, niet als een waarschuwing. Meerdere
  // scenario's in dit bestand openen de dialoog zonder hem te sluiten, en een
  // niet-opgeruimde dialoog laat zijn modale barrière over de knop van de
  // volgende `toon()` liggen (zie de uitleg daar). Tikken op 'open' landt dan op
  // die barrière in plaats van op de knop: de nieuwe dialoog gaat niet open en
  // de oude blijft staan. Geïsoleerd bleef dat een stille waarschuwing (de test
  // slaagde toevallig toch); onder de volle `make check` viel hij om. Fataal
  // maken maakt die misser hier deterministisch zichtbaar, zodat de opruiming in
  // `toon()` echt nodig is en de flake niet terug kan sluipen.
  WidgetController.hitTestWarningShouldBeFatal = true;

  /// Toont de dialoog. De teruggegeven functie leest het antwoord zodra de
  /// dialoog gesloten is — bij terugkeer staat hij nog open, dus een directe
  /// returnwaarde zou altijd `null` zijn.
  Future<bool? Function()> toon(
    WidgetTester tester, {
    AiSettings settings = _cloud,
    int imageCount = 1,
    int faceCount = 0,
  }) async {
    bool? antwoord;
    // pumpWidget met opnieuw een MaterialApp *reconcilieert* met de bestaande:
    // dezelfde Navigator eronder blijft, dus een dialoog uit een vorige
    // toon()-aanroep blijft op de route-stack staan en zijn barrière ligt over
    // de knop. Ruim daarom eerst met een boom van een ander type op, zodat de
    // oude MaterialApp — en daarmee de Navigator en de dialoog — echt wordt
    // afgebroken en elke aanroep bij een schone lei begint.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => antwoord = await confirmAiImageOutbound(
                context,
                title: 'Versturen?',
                settings: settings,
                imageCount: imageCount,
                faceCount: faceCount,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Wacht tot de dialoog er echt is voordat de aanroeper hem leest.
    await pumpUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isNotEmpty,
      reason: 'de dialoog ging niet open',
    );
    return () => antwoord;
  }

  testWidgets('noemt de bestemming bij naam, niet "de cloud"', (tester) async {
    // De gebruiker moet kunnen zien of dat zijn eigen server is of die van
    // iemand anders. "Een clouddienst" laat dat verschil juist verdwijnen.
    await toon(tester);
    expect(find.textContaining(_cloud.baseUrl), findsOneWidget);
  });

  testWidgets('een model op dit apparaat heet geen URL', (tester) async {
    await toon(tester, settings: _lokaal);
    expect(find.textContaining('een model op dit apparaat'), findsOneWidget);
    expect(find.textContaining(_lokaal.baseUrl), findsNothing);
  });

  testWidgets('zegt dat er in een afbeelding niets wordt weggelakt', (
    tester,
  ) async {
    // Dit is de kern. Wie de rest van de app kent, verwacht dat de projectie
    // ook hier iets doet — en dat doet ze niet.
    await toon(tester);
    expect(
      find.textContaining('OciDeck lakt niets weg in een afbeelding'),
      findsOneWidget,
    );
  });

  testWidgets('meldt gevonden gezichten, en zwijgt bij nul', (tester) async {
    // Nul betekent hier óók "er is niet gekeken" (web, uitgezette controle,
    // HEIC). Dan mag er geen regel staan die als "er staat niemand op" leest.
    await toon(tester, faceCount: 2);
    expect(
      find.textContaining('herkenbare gezichten'),
      findsOneWidget,
      reason: 'een gevonden gezicht hoort in de vraag te staan',
    );

    await toon(tester, faceCount: 0);
    expect(find.textContaining('herkenbare gezichten'), findsNothing);
  });

  testWidgets('telt de afbeeldingen bij een bulkactie', (tester) async {
    await toon(tester, imageCount: 12);
    expect(find.textContaining('12'), findsOneWidget);
  });

  testWidgets('annuleren is nee', (tester) async {
    final antwoord = await toon(tester);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(antwoord(), isFalse);
  });

  testWidgets('doorgaan is ja', (tester) async {
    final antwoord = await toon(tester);
    await tester.tap(find.text('Doorgaan'));
    await tester.pumpAndSettle();
    expect(antwoord(), isTrue);
  });

  testWidgets('een weggeklikte dialoog leest nooit als toestemming', (
    tester,
  ) async {
    // `showDialog` geeft `null` bij een tik naast de dialoog. Zou dat als
    // toestemming doorgaan, dan verstuurt een misklik de afbeelding.
    final antwoord = await toon(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(antwoord(), isFalse);
  });
}
