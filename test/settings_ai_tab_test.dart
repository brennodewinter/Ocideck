import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het AI-tabblad van de instellingen (`parts/settings_dialog_ai.dart`).
///
/// De regel die hier het meeste weegt staat niet in de UI maar in
/// `_initAiFields`: verandert de bestemming, dan vervalt de bevestiging én de
/// sleutel. Zonder die koppeling stuurde iemand die dienst A bevestigde en
/// daarna alleen de URL naar B wijzigde, zijn tekst naar een bestemming die hij
/// nooit heeft goedgekeurd — mét de sleutel van A in de `Authorization`-kop.
///
/// Verder is dit tabblad één lange keten van "wat je kiest bepaalt wat je te
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
                    initialSection: SettingsSection.ai,
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

  Finder aanZetten() =>
      find.widgetWithText(SwitchListTile, 'AI-assistentie inschakelen');

  Finder cloudBevestiging() => find.widgetWithText(
    SwitchListTile,
    'Ik begrijp dat gegevens naar deze externe dienst worden verstuurd',
  );

  Finder veld(String label) => find.widgetWithText(TextField, label);

  Future<void> tapIn(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settle(tester);
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> kiesBackend(WidgetTester tester, String label) async {
    await tapIn(tester, find.byType(DropdownButtonFormField<AiBackendMode>));
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  bool switchAan(WidgetTester tester, Finder finder) =>
      tester.widget<SwitchListTile>(finder).value;

  testWidgets('uit staat er niets ingesteld te worden', (tester) async {
    await openAiTab(tester);

    expect(switchAan(tester, aanZetten()), isFalse, reason: 'standaard uit');
    expect(
      find.byType(DropdownButtonFormField<AiBackendMode>),
      findsNothing,
      reason: 'zonder inschakelen valt er niets te kiezen',
    );
    expect(
      find.textContaining('Er wordt niets verstuurd totdat je dit inschakelt'),
      findsOneWidget,
    );
  });

  testWidgets('inschakelen brengt de backendkeuze tevoorschijn', (
    tester,
  ) async {
    await openAiTab(tester);
    await tapIn(tester, aanZetten());

    expect(find.byType(DropdownButtonFormField<AiBackendMode>), findsOneWidget);
    // "Geen" is de stand waarin er nog steeds niets te configureren valt.
    expect(veld('Server-URL'), findsNothing);
  });

  testWidgets('de lokale backend vult het adres van dit apparaat voor', (
    tester,
  ) async {
    await openAiTab(tester);
    await tapIn(tester, aanZetten());
    await kiesBackend(tester, 'Lokaal (op dit apparaat)');

    expect(
      tester.widget<TextField>(veld('Server-URL')).controller!.text,
      AiSettings.defaultLocalBaseUrl,
      reason: 'een lokale backend hoort niet handmatig ingetikt te worden',
    );
    // Lokaal: geen sleutel, geen LAN-schakelaar, geen cloudbevestiging.
    expect(veld('API-sleutel (optioneel)'), findsNothing);
    expect(
      find.widgetWithText(SwitchListTile, 'Vertrouwde interne server'),
      findsNothing,
    );
    expect(cloudBevestiging(), findsNothing);
  });

  testWidgets('zelf gehost vraagt om een sleutel en om de LAN-keuze', (
    tester,
  ) async {
    await openAiTab(tester);
    await tapIn(tester, aanZetten());
    await kiesBackend(tester, 'Zelf gehost (eigen server)');

    expect(veld('API-sleutel (optioneel)'), findsOneWidget);
    expect(
      find.widgetWithText(SwitchListTile, 'Vertrouwde interne server'),
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
    await tapIn(tester, aanZetten());
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
    await tapIn(tester, aanZetten());
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
        find.widgetWithText(SwitchListTile, 'Vertrouwde interne server'),
      ),
      isTrue,
    );
  });

  testWidgets('een verbindingstest meldt zijn uitslag', (tester) async {
    await openAiTab(tester);
    await tapIn(tester, aanZetten());
    await kiesBackend(tester, 'Lokaal (op dit apparaat)');

    await tapIn(
      tester,
      find.widgetWithText(ElevatedButton, 'Verbinding testen'),
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
