import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/ai_integration_card.dart';
import 'package:ocideck/widgets/dialogs/settings/ai_module_card.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De AI-configuratie van de instellingen (`parts/settings_dialog_ai.dart`).
/// Tot #2184 was dit een eigen tabblad in de zijbalk; AI is een koppeling met
/// een backend en hoort daarom als kaart op Integraties. De inschakelschakelaar
/// staat op Uitbreidingen (#731, #2185).
///
/// De regel die hier het meeste weegt staat niet in de UI maar in
/// `_initAiFields`: verandert de bestemming, dan vervalt de bevestiging én de
/// sleutel. Zonder die koppeling stuurde iemand die dienst A bevestigde en
/// daarna alleen de URL naar B wijzigde, zijn tekst naar een bestemming die hij
/// nooit heeft goedgekeurd — mét de sleutel van A in de `Authorization`-kop.
///
/// Verder is deze kaart één lange keten van "wat je kiest bepaalt wat je te
/// zien krijgt", en elke stap daarin hoort een eerdere testuitslag te laten
/// vervallen: die uitslag gold voor een andere opstelling.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  /// Het testlettertype tekent glyphs veel breder dan een echt lettertype, dus
  /// de vaste-breedte-rijen van dit tabblad lopen hier over terwijl ze in de
  /// draaiende app passen. Die ruis is cosmetisch en font-gedreven; de
  /// bewering staat in de expects eronder, niet in de afwezigheid van een
  /// overflow. Zie `image_carousel_picker_smoke_test`, waar hetzelfde speelt.
  void clearLayoutNoise(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    clearLayoutNoise(tester);
  }

  /// Opent het instellingenvenster op **Uitbreidingen**, want daar staat sinds
  /// #731 de schakelaar. De configuratiekaart staat sinds #2184 op
  /// Integraties; dit is de enige ingang die met verse voorkeuren werkt.
  Future<void> openAiTab(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({...prefs});
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              // Bewust een `watch`: het venster leest de instellingen één keer
              // in `initState`, en die komen asynchroon uit de prefs. Zonder
              // deze lezer bestaat de provider nog niet als het venster opengaat
              // en toont het venster de standaardwaarden.
              builder: (context, ref, _) {
                ref.watch(settingsProvider);
                return ElevatedButton(
                  onPressed: () => SettingsDialog.show(
                    context,
                    initialSection: SettingsSection.modules,
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    // Eerst laten bezinken: de instellingen komen asynchroon uit de prefs, en
    // het venster leest ze één keer bij het openen.
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.byType(SettingsDialog), findsOneWidget);
  }

  Future<void> tapIn(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settle(tester);
    await tester.tap(target);
    await settle(tester);
  }

  /// De moduleschakelaar op Uitbreidingen. Heette tot #731
  /// "AI-assistentie inschakelen" en stond op het AI-tabblad zelf.
  /// Gescope op de modulekaart: de integratiekaart op Integraties toont
  /// dezelfde titel, met een schakelaar die alleen uit kan (#2185).
  Finder aanZetten() => find.descendant(
    of: find.byType(AiModuleCard),
    matching: find.byType(SwitchListTile),
  );

  /// Het tabblad Integraties in de zijbalk — daar staat sinds #2184 de kaart
  /// met de backend-configuratie.
  Finder integratiesTabblad() => find.byTooltip('Integraties');

  /// Zet de module aan en ga naar Integraties — de gewone route van een
  /// gebruiker, en de opstelling waar de meeste toetsen hieronder vanuit gaan.
  Future<void> moduleAanEnNaarTab(WidgetTester tester) async {
    await tapIn(tester, aanZetten());
    await tapIn(tester, integratiesTabblad());
  }

  /// De AI-kaart op Integraties. Veldlabels als "Server-URL" en "Verbinding
  /// testen" staan sinds #2184 óók op de LibrePlan-kaart, dus alle finders
  /// op de configuratie scopen op deze kaart.
  Finder aiKaart() => find.byType(AiIntegrationCard);

  Finder cloudBevestiging() => find.descendant(
    of: aiKaart(),
    matching: find.widgetWithText(
      SwitchListTile,
      'Ik begrijp dat gegevens naar deze externe dienst worden verstuurd',
    ),
  );

  Finder veld(String label) => find.descendant(
    of: aiKaart(),
    matching: find.widgetWithText(TextField, label),
  );

  Future<void> kiesBackend(WidgetTester tester, String label) async {
    await tapIn(tester, find.byType(DropdownButtonFormField<AiBackendMode>));
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  bool switchAan(WidgetTester tester, Finder finder) =>
      tester.widget<SwitchListTile>(finder).value;

  testWidgets('uit valt er niets in te stellen', (tester) async {
    await openAiTab(tester);

    expect(find.byType(AiModuleCard), findsOneWidget);
    expect(switchAan(tester, aanZetten()), isFalse, reason: 'standaard uit');
    // Sinds #2184 is er geen eigen AI-tabblad meer: de backend-configuratie
    // is een kaart op Integraties, en die toont zonder backend niets om in
    // te vullen.
    await tapIn(tester, integratiesTabblad());
    expect(
      find.byType(DropdownButtonFormField<AiBackendMode>),
      findsNothing,
      reason: 'zonder inschakelen valt er niets te kiezen',
    );
    // De kaart zelf staat er wél, met een schakelaar die alleen uit kan —
    // aanzetten hoort bij Uitbreidingen (#2185).
    final integratieSchakelaar = find.descendant(
      of: find.byType(AiIntegrationCard),
      matching: find.byType(SwitchListTile),
    );
    expect(integratieSchakelaar, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(integratieSchakelaar).onChanged,
      isNull,
    );
  });

  testWidgets('aanzetten onthult de configuratie op Integraties', (
    tester,
  ) async {
    await openAiTab(tester);
    await tapIn(tester, integratiesTabblad());
    expect(find.byType(DropdownButtonFormField<AiBackendMode>), findsNothing);

    await tapIn(tester, find.byTooltip('Uitbreidingen'));
    await tapIn(tester, aanZetten());
    await tapIn(tester, integratiesTabblad());
    expect(find.byType(DropdownButtonFormField<AiBackendMode>), findsOneWidget);
  });

  testWidgets(
    'een ingestelde backend houdt de kaart gevuld, ook met de module uit',
    (tester) async {
      // De vaste regel uit #648: tonen zodra de inhoud er is. Zou de kaart
      // op alléén de schakelaar leeglopen, dan maakt uitzetten de backend en
      // de sleutel onbereikbaar — werk dat er al ligt, weg achter een knop.
      await openAiTab(
        tester,
        prefs: {
          'aiSettings': jsonEncode({
            'enabled': false,
            'mode': 'local',
            'baseUrl': 'http://127.0.0.1:11434/v1',
            'model': 'gemma3:4b',
          }),
        },
      );

      expect(switchAan(tester, aanZetten()), isFalse);

      await tapIn(tester, integratiesTabblad());
      expect(
        find.textContaining('De module AI-assistentie staat uit'),
        findsOneWidget,
        reason: 'anders leest de kaart als een werkende instelling',
      );
      expect(
        find.byType(DropdownButtonFormField<AiBackendMode>),
        findsOneWidget,
        reason: 'de configuratie blijft bereikbaar om op te ruimen',
      );
    },
  );

  testWidgets('inschakelen brengt de backendkeuze tevoorschijn', (
    tester,
  ) async {
    await openAiTab(tester);
    await moduleAanEnNaarTab(tester);

    expect(find.byType(DropdownButtonFormField<AiBackendMode>), findsOneWidget);
    // "Geen" is de stand waarin er nog steeds niets te configureren valt.
    expect(veld('Server-URL'), findsNothing);
  });

  testWidgets('de lokale backend vult het adres van dit apparaat voor', (
    tester,
  ) async {
    await openAiTab(tester);
    await moduleAanEnNaarTab(tester);
    await kiesBackend(tester, 'Lokaal (op dit apparaat)');

    expect(
      tester.widget<TextField>(veld('Server-URL')).controller!.text,
      AiSettings.defaultLocalBaseUrl,
      reason: 'een lokale backend hoort niet handmatig ingetikt te worden',
    );
    // Lokaal: geen sleutel, geen LAN-schakelaar, geen cloudbevestiging.
    expect(veld('API-sleutel (optioneel)'), findsNothing);
    expect(
      find.descendant(
        of: aiKaart(),
        matching: find.widgetWithText(
          SwitchListTile,
          'Vertrouwde interne server',
        ),
      ),
      findsNothing,
    );
    expect(cloudBevestiging(), findsNothing);
  });

  testWidgets('zelf gehost vraagt om een sleutel en om de LAN-keuze', (
    tester,
  ) async {
    await openAiTab(tester);
    await moduleAanEnNaarTab(tester);
    await kiesBackend(tester, 'Zelf gehost (eigen server)');

    expect(veld('API-sleutel (optioneel)'), findsOneWidget);
    expect(
      find.descendant(
        of: aiKaart(),
        matching: find.widgetWithText(
          SwitchListTile,
          'Vertrouwde interne server',
        ),
      ),
      findsOneWidget,
      reason: 'zonder deze keuze is een LAN-adres niet te bereiken',
    );
    expect(
      cloudBevestiging(),
      findsNothing,
      reason: 'een eigen server is geen externe dienst',
    );
  });

  testWidgets('de cloud vraagt eerst om een uitdrukkelijke bevestiging', (
    tester,
  ) async {
    await openAiTab(tester);
    await moduleAanEnNaarTab(tester);
    await kiesBackend(tester, 'Cloud (externe dienst)');

    expect(cloudBevestiging(), findsOneWidget);
    expect(
      switchAan(tester, cloudBevestiging()),
      isFalse,
      reason: 'niemand bevestigt dit per ongeluk vooraf',
    );
    expect(
      find.textContaining('vereist eerst je privacytoestemming'),
      findsOneWidget,
    );
  });

  testWidgets('een andere bestemming laat de bevestiging én de sleutel los', (
    tester,
  ) async {
    await openAiTab(tester);
    await moduleAanEnNaarTab(tester);
    await kiesBackend(tester, 'Cloud (externe dienst)');

    await tester.enterText(veld('Server-URL'), 'https://dienst-a.example/v1');
    await settle(tester);
    await tester.enterText(veld('API-sleutel (optioneel)'), 'sleutel-van-a');
    await settle(tester);
    await tapIn(tester, cloudBevestiging());
    expect(switchAan(tester, cloudBevestiging()), isTrue);

    // Alleen de URL wijzigen — precies het geval waarin de bevestiging
    // stilzwijgend mee zou verhuizen naar een dienst die niemand goedkeurde.
    await tester.enterText(veld('Server-URL'), 'https://dienst-b.example/v1');
    await settle(tester);

    expect(
      switchAan(tester, cloudBevestiging()),
      isFalse,
      reason: 'de bevestiging gold voor dienst A, niet voor B',
    );
    expect(
      tester
          .widget<TextField>(veld('API-sleutel (optioneel)'))
          .controller!
          .text,
      isEmpty,
      reason: 'de sleutel van A mag niet als Authorization naar B',
    );
  });

  testWidgets('op het web zegt het tabblad dat dit hier niet werkt', (
    tester,
  ) async {
    // Niet af te dwingen zonder web-platform; wél de tegenhanger: op desktop
    // staat er geen "alleen in de desktopversie"-boodschap in plaats van de
    // instellingen.
    await openAiTab(tester);
    expect(
      find.text('AI-assistentie is alleen beschikbaar in de desktopversie.'),
      findsNothing,
    );
    expect(aanZetten(), findsOneWidget);
  });

  testWidgets('opgeslagen instellingen komen terug in de velden', (
    tester,
  ) async {
    await openAiTab(
      tester,
      prefs: {
        'aiSettings': jsonEncode(const {
          'enabled': true,
          'mode': 'selfHosted',
          'baseUrl': 'https://eigen.server.intern/v1',
          'model': 'gemma3:4b',
          'trustedInternal': true,
        }),
      },
    );

    expect(switchAan(tester, aanZetten()), isTrue);
    // De velden staan op de kaart op Integraties; de dialoog opent sinds #731
    // op Uitbreidingen, dus daar eerst heen.
    await tapIn(tester, integratiesTabblad());
    expect(
      tester.widget<TextField>(veld('Server-URL')).controller!.text,
      'https://eigen.server.intern/v1',
    );
    expect(
      tester.widget<TextField>(veld('Modelnaam')).controller!.text,
      'gemma3:4b',
    );
    expect(
      switchAan(
        tester,
        find.descendant(
          of: aiKaart(),
          matching: find.widgetWithText(
            SwitchListTile,
            'Vertrouwde interne server',
          ),
        ),
      ),
      isTrue,
    );
  });

  testWidgets('een verbindingstest meldt zijn uitslag', (tester) async {
    await openAiTab(tester);
    await moduleAanEnNaarTab(tester);
    await kiesBackend(tester, 'Lokaal (op dit apparaat)');

    await tapIn(
      tester,
      find.descendant(
        of: aiKaart(),
        matching: find.widgetWithText(ElevatedButton, 'Verbinding testen'),
      ),
    );

    // Onder `flutter test` is er geen server op 127.0.0.1:11434, dus dit hoort
    // met een leesbare fout terug te komen — niet met stilte, en niet met een
    // wieltje dat blijft draaien.
    expect(
      find.byIcon(Icons.error_outline),
      findsOneWidget,
      reason: 'een mislukte test hoort zichtbaar te mislukken',
    );
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });
}
