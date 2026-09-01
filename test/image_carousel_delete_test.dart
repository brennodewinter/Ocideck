import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/caption_service.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

/// Het verwijderpad van de afbeeldingenbibliotheek
/// (`parts/image_carousel_picker_delete.dart`). Dat is de enige plek in OciDeck
/// waar een bestand onherroepelijk van schijf gaat, en het is bewust géén
/// prullenbak: wat hier weg is, is weg.
///
/// De waarschuwing eromheen is daarom het product. Ze moet twee dingen dekken
/// die elkaar niet vanzelf aanvullen: de dia's van de geopende presentaties
/// (die kent de aanroeper) én de presentaties die alleen op schijf staan (die
/// worden hier gescand). Telt de tweede helft niet mee, dan verwijdert iemand
/// een afbeelding "die nergens gebruikt wordt" en staat er in drie oude
/// rapporten een gat.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

/// Wachtbudget voor de `pumpUntil`-punten hieronder. Ruim, want de linux-gate
/// draait deze suite op vier kernen onder `--concurrency=14`: "klaar" kan daar
/// seconden duren waar het hier milliseconden is. `pumpUntil` breekt af zodra
/// de voorwaarde waar is, dus op een snelle machine kost die ruimte niets.
const _budget = Duration(seconds: 20);

void main() {
  late Directory tmp;
  late String alpha;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('carousel_delete');
    alpha = p.join(tmp.path, 'alpha.png');
    File(alpha).writeAsBytesSync(_onePixelPng);
  });

  tearDown(() {
    // Windows houdt een net via de beeld-cache ingelezen bestand soms nog kort
    // vast (errno 32); OS-temp wordt sowieso opgeruimd, de test is dan al klaar.
    if (!tmp.existsSync()) return;
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // opzettelijk genegeerd: zie hierboven
    }
  });

  /// Schrijft een presentatie op schijf die [imageName] [times] keer gebruikt.
  String deckOnDisk(String name, String imageName, {int times = 1}) {
    final path = p.join(tmp.path, name);
    File(path).writeAsStringSync(
      [
        '---',
        'marp: true',
        '---',
        '',
        for (var i = 0; i < times; i++) ...[
          '# Dia ${i + 1}',
          '',
          '![]($imageName)',
          '',
          '---',
          '',
        ],
      ].join('\n'),
    );
    return path;
  }

  /// Het venster laat zijn beeld pas zien nadat de schijfscan klaar is, en die
  /// vordert alleen in de echte zone. Zie `image_carousel_picker_smoke_test`,
  /// waar dit patroon vandaan komt; de opmaakruis van het testlettertype wordt
  /// daar om dezelfde reden weggehaald.
  void clearLayoutNoise(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  Future<void> pumpPicker(
    WidgetTester tester, {
    List<String> Function(String)? usageOf,
    List<String> openDeckFiles = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageCarouselPicker(
              searchPaths: [tmp.path],
              initialPath: alpha,
              captionService: CaptionService(),
              descriptionService: DescriptionService(),
              usageOf: usageOf,
              openDeckFiles: openDeckFiles,
            ),
          ),
        ),
      );
    });
    // Hier stond 300 ms wandelklok plus twee pumps — een gok op hoe lang de
    // mapscan duurt. Op de belaste Linux-runner bleek die gok negen keer te
    // krap, en dan viel telkens een andere test uit dit bestand om op een
    // ontbrekende Verwijderen-knop. Wacht daarom op de knop zelf: die staat er
    // pas als de scan de laadindicator heeft weggehaald én de beginselectie is
    // gezet, en dat is precies wat elke test hierna aantikt.
    await pumpUntil(
      tester,
      () =>
          find.widgetWithText(TextButton, 'Verwijderen').evaluate().isNotEmpty,
      timeout: _budget,
      reason: 'de mapscan van de afbeeldingkiezer bleef laden',
    );
    clearLayoutNoise(tester);
  }

  /// Tikt op Verwijderen in de werkbalk en wacht tot het venster met de vraag
  /// er staat — dat komt pas ná de schijfscan.
  Future<void> openDeleteDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Verwijderen'));
    await pumpUntil(
      tester,
      () => find.text('Afbeelding verwijderen?').evaluate().isNotEmpty,
      timeout: _budget,
      reason: 'de bevestigingsvraag kwam niet op',
    );
    clearLayoutNoise(tester);
  }

  /// Bevestigt (of annuleert) en laat het verwijderen afmaken.
  Future<void> answer(WidgetTester tester, {required bool confirm}) async {
    // Gescoopt op het venster: de bibliotheek eronder heeft zelf ook een
    // Annuleren-knop.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: confirm
            ? find.widgetWithText(ElevatedButton, 'Verwijderen')
            : find.widgetWithText(TextButton, 'Annuleren'),
      ),
    );
    // Het venster sluiten is het enige wat dit antwoord zelf oplevert; wat er
    // daarna gebeurt (het bestand wissen, de bibliotheek herscannen) is aan de
    // aanroeper om af te wachten — die weet welke uitkomst hij bewéért.
    await pumpUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
      timeout: _budget,
      reason: 'het bevestigingsvenster bleef staan',
    );
    clearLayoutNoise(tester);
  }

  testWidgets(
    'een ongebruikte afbeelding gaat na bevestiging echt van schijf',
    (tester) async {
      await pumpPicker(tester);
      await openDeleteDialog(tester);

      expect(find.text('alpha.png'), findsWidgets);
      expect(
        find.textContaining('permanent van schijf verwijderd'),
        findsOneWidget,
        reason: 'de gebruiker moet weten dat er geen prullenbak is',
      );
      expect(File(alpha).existsSync(), isTrue, reason: 'nog niets gebeurd');

      await answer(tester, confirm: true);

      // Het wissen loopt op echte file-IO ná het sluiten van het venster.
      await pumpUntil(
        tester,
        () => !File(alpha).existsSync(),
        timeout: _budget,
        reason: 'alpha.png stond na bevestiging nog op schijf',
      );
      expect(File(alpha).existsSync(), isFalse);
    },
  );

  testWidgets('annuleren laat het bestand staan', (tester) async {
    await pumpPicker(tester);
    await openDeleteDialog(tester);

    await answer(tester, confirm: false);

    expect(File(alpha).existsSync(), isTrue);
  });

  testWidgets('dia\'s uit de geopende presentaties staan in de waarschuwing', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      usageOf: (path) => path == alpha
          ? const ['Rapport · dia 3', 'Rapport · dia 7']
          : const [],
    );
    await openDeleteDialog(tester);

    expect(
      find.textContaining('nog gebruikt in 2 slides'),
      findsOneWidget,
      reason: 'het aantal dia\'s hoort in de vraag te staan',
    );
    expect(find.text('•  Rapport · dia 3'), findsOneWidget);
    expect(find.text('•  Rapport · dia 7'), findsOneWidget);
    expect(
      find.textContaining('maakt die slides leeg'),
      findsOneWidget,
      reason: 'de gevolgen voor de dia\'s horen erbij te staan',
    );
  });

  testWidgets('een presentatie die alleen op schijf staat telt mee', (
    tester,
  ) async {
    deckOnDisk('oud-rapport.md', 'alpha.png', times: 2);
    await pumpPicker(tester);
    await openDeleteDialog(tester);

    // Twee dia's in één niet-geopend deck: het aantal én de bron staan er.
    expect(
      find.textContaining('nog gebruikt in 2 slides'),
      findsOneWidget,
      reason: 'de dia\'s op schijf moeten meetellen in het aantal',
    );
    expect(
      find.text('•  oud-rapport.md · 2× · niet geopend'),
      findsOneWidget,
      reason: 'zonder dit lijkt de afbeelding ongebruikt',
    );
  });

  testWidgets('een geopende presentatie wordt niet dubbel geteld', (
    tester,
  ) async {
    final open = deckOnDisk('rapport.md', 'alpha.png');
    await pumpPicker(
      tester,
      usageOf: (path) => path == alpha ? const ['rapport · dia 1'] : const [],
      openDeckFiles: [open],
    );
    await openDeleteDialog(tester);

    expect(find.text('•  rapport · dia 1'), findsOneWidget);
    expect(
      find.textContaining('niet geopend'),
      findsNothing,
      reason: 'het geopende deck is al door usageOf geteld',
    );
    expect(
      find.textContaining('nog gebruikt in 1 slide'),
      findsOneWidget,
      reason: 'één keer geteld, en dan ook in enkelvoud',
    );
  });

  testWidgets('geopende en niet-geopende presentaties tellen bij elkaar op', (
    tester,
  ) async {
    deckOnDisk('oud-rapport.md', 'alpha.png', times: 2);
    await pumpPicker(
      tester,
      usageOf: (path) => path == alpha ? const ['rapport · dia 1'] : const [],
    );
    await openDeleteDialog(tester);

    expect(
      find.textContaining('nog gebruikt in 3 slides'),
      findsOneWidget,
      reason: 'één uit de geopende presentatie plus twee van schijf',
    );
  });

  testWidgets('een verwijderde afbeelding verdwijnt uit de bibliotheek', (
    tester,
  ) async {
    final beta = p.join(tmp.path, 'beta.png');
    File(beta).writeAsBytesSync(_onePixelPng);
    await pumpPicker(tester);
    await openDeleteDialog(tester);
    await answer(tester, confirm: true);

    // Na de verwijdering herstelt de bibliotheek zich door opnieuw te scannen;
    // pas daarna is de naam uit de boom.
    await pumpUntil(
      tester,
      () => find.textContaining('alpha.png').evaluate().isEmpty,
      timeout: _budget,
      reason: 'alpha.png staat nog in de bibliotheek',
    );
    clearLayoutNoise(tester);
    // De naam van het verwijderde bestand staat nergens meer; de andere wel.
    expect(find.textContaining('alpha.png'), findsNothing);
    expect(find.textContaining('beta.png'), findsWidgets);
  });
}
