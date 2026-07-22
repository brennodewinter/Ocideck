import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De zijbalk van het instellingenvenster bij grote tekst (#646).
///
/// OciDeck biedt tekstschaling tot 200% aan, uitdrukkelijk als
/// toegankelijkheidsinstelling (WCAG 1.4.4). Dan hoort de eigen interface daar
/// tegen te kunnen. Dat deed hij niet: de zijbalk had een vaste breedte van 234
/// pixels en elk label kapte af op één regel — "Einste…", "App-De…",
/// "Präsent…", "Lizenz u…". Een navigatie waarop je niet meer kunt navigeren,
/// precies voor de gebruiker die de instelling nodig had.
///
/// **Wat hier niet te meten valt, en waarom dat hier staat.** Onder
/// `flutter test` is het lettertype een testfont waarin élk teken even breed is
/// als hoog. "Lizenz und Datenschutz" is daar 22 vierkanten breed en past in
/// geen redelijke kolom, ook op 100% niet. Een toets "er kapt niets af" zou dus
/// rood staan op een interface die in het echt prima leest, en groen te maken
/// zijn door de kolom absurd breed te maken — een test die je naar het
/// verkeerde antwoord duwt.
///
/// Daarom meet dit drie dingen die het testfont overleven — de breedte groeit
/// mee, de labels krijgen twee regels, en de volledige naam blijft via een
/// tooltip bereikbaar — plus de eigenschap waar het werkelijk om gaat:
/// **grotere tekst mag niet méér informatie kosten dan kleine tekst.**
///
/// Hoe het er met een echt lettertype uitziet is een zaak voor de beeldkeuring.
/// Die vervangt deze test niet, en deze test vervangt haar niet.
void main() {
  setUp(() {
    // Duits, want daarin viel het op: lange samenstellingen als
    // "Abschnittsüberschrift" en "Lizenz und Datenschutz". Een taal met korte
    // woorden zou deze test laten slagen zonder dat er iets was opgelost.
    AppLocalizations.setActiveLanguageCode('de');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  Finder sidebar() => find.byKey(const Key('settings-sidebar'));

  Future<void> openSettings(WidgetTester tester, double scale) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        // Een eigen sleutel per schaal: zonder dat houdt de Navigator van de
        // vorige MaterialApp zijn dialoogroute vast en tikt de tweede tap op
        // een modale sluier in plaats van op de knop.
        child: MaterialApp(
          key: ValueKey(scale),
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
  }

  /// De labels in de zijbalk die niet volledig pasten. Alleen de zijbalk: de
  /// inhoudspanelen ernaast hebben hun eigen ruimteproblemen.
  List<String> truncated(WidgetTester tester) {
    final uit = <String>[];
    for (final element
        in find
            .descendant(of: sidebar(), matching: find.byType(RichText))
            .evaluate()) {
      final paragraaf = element.renderObject as RenderParagraph?;
      if (paragraaf != null && paragraaf.didExceedMaxLines) {
        uit.add(paragraaf.text.toPlainText());
      }
    }
    return uit;
  }

  testWidgets('de zijbalk groeit mee met de tekstschaal', (tester) async {
    await openSettings(tester, 1);
    expect(
      tester.getSize(sidebar()).width,
      234.0,
      reason: 'op 100% verandert er niets voor wie niets instelt',
    );

    await openSettings(tester, 2);
    final groot = tester.getSize(sidebar()).width;
    expect(groot, greaterThan(234.0), reason: 'de vaste breedte wás de fout');
    // Maar niet één-op-één: 468 px zou het venster opeten, en dan is de
    // navigatie leesbaar en de inhoud niet.
    expect(groot, lessThanOrEqualTo(234.0 * 1.5), reason: 'eet het venster op');
  });

  testWidgets('grotere tekst kost geen extra informatie', (tester) async {
    // De eigenschap waar het om gaat, en de enige die het testfont overleeft:
    // wie de tekst groter zet, mag daar geen navigatie voor inleveren.
    await openSettings(tester, 1);
    final bij100 = truncated(tester).length;

    await openSettings(tester, 2);
    final bij200 = truncated(tester).length;

    expect(
      bij200,
      lessThanOrEqualTo(bij100),
      reason:
          'Op 200% vallen er $bij200 labels weg tegen $bij100 op 100%. Dan '
          'maakt de toegankelijkheidsinstelling de interface slechter voor '
          'precies wie hem aanzet.',
    );
  });

  testWidgets('elk label mag twee regels gebruiken', (tester) async {
    // Verticale ruimte is hier goedkoper dan horizontale: de lijst scrolt toch
    // al. Eén regel was de andere helft van de fout.
    await openSettings(tester, 2);

    final regels = find
        .descendant(of: sidebar(), matching: find.byType(RichText))
        .evaluate()
        .map((e) => (e.renderObject as RenderParagraph).maxLines)
        .whereType<int>()
        .toList();

    expect(regels, isNotEmpty);
    expect(regels, everyElement(greaterThanOrEqualTo(2)));
  });

  testWidgets('en de volledige naam blijft bereikbaar', (tester) async {
    // Het vangnet voor wat ook met twee regels niet past. Een tooltip is niet
    // de oplossing — die moet je eerst ontdekken — maar hij is het verschil
    // tussen "onleesbaar" en "op te zoeken".
    await openSettings(tester, 2);

    final tooltips = tester
        .widgetList<Tooltip>(
          find.descendant(of: sidebar(), matching: find.byType(Tooltip)),
        )
        .map((t) => t.message)
        .whereType<String>()
        .toList();

    expect(tooltips, isNotEmpty);
    expect(
      tooltips,
      everyElement(isNotEmpty),
      reason: 'een lege tooltip is geen vangnet',
    );
  });
}
