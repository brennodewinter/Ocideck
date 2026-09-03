import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zoeken door de instellingen. De echte waarde zit in de sprong: typ "youtube"
/// en je staat bij "Online media" — zonder te weten dat die onder Beveiliging
/// hangt.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              // Bewust een `watch`: het venster leest de instellingen één keer
              // in `initState`, en die komen asynchroon uit de prefs. Zonder
              // deze lezer staat de provider er nog niet als het venster
              // opengaat, en zoekt de gebruiker door de standaardwaarden.
              builder: (context, ref, _) {
                ref.watch(settingsProvider);
                return ElevatedButton(
                  onPressed: () => SettingsDialog.show(context),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pumpAndSettle();
  }

  // De tabbladen blijven achter de resultatenlijst in de boom staan (de
  // IndexedStack bouwt ze alle twaalf — dát is wat de ankers laat werken), dus
  // een label komt twee keer voor. Het kruimelpad onder een treffer bestaat
  // alleen in de resultatenlijst: dáár toetsen we op.
  testWidgets('a synonym finds the setting it belongs to', (tester) async {
    await openSettings(tester);
    // "youtube" staat nergens op het scherm — het is een keyword.
    await search(tester, 'youtube');

    expect(find.text('Beveiliging › Online media'), findsOneWidget);
    expect(find.text('Geen instelling gevonden'), findsNothing);
  });

  testWidgets('search matches on the visible label too', (tester) async {
    await openSettings(tester);
    await search(tester, 'contrastverhouding');
    expect(find.textContaining('› Toegankelijkheid'), findsOneWidget);
  });

  testWidgets('een stijlprofiel delen is vindbaar zonder de term te kennen', (
    tester,
  ) async {
    await openSettings(tester);
    // "downloaden" staat nergens op het scherm; de knop heet "exporteren".
    await search(tester, 'downloaden');
    expect(find.text('Profiel exporteren'), findsOneWidget);
    expect(find.text('Geen instelling gevonden'), findsNothing);

    await search(tester, 'inladen');
    expect(find.text('Profiel importeren'), findsOneWidget);
  });

  testWidgets('a query that matches nothing says so', (tester) async {
    await openSettings(tester);
    await search(tester, 'zoiets bestaat niet');
    expect(find.text('Geen instelling gevonden'), findsOneWidget);
  });

  testWidgets('tapping a hit jumps to the tab holding that setting', (
    tester,
  ) async {
    await openSettings(tester);
    await search(tester, 'youtube');

    await tester.tap(find.text('Beveiliging › Online media'));
    await tester.pumpAndSettle();
    // De oplichting van de sectie dooft na 3 seconden; laat die timer aflopen.
    await tester.pump(const Duration(seconds: 4));

    // De resultatenlijst is weg (geen kruimelpad meer) en het Beveiliging-
    // tabblad staat open, met zijn eigen schakelaars in beeld.
    expect(find.text('Beveiliging › Online media'), findsNothing);
    // Een baken uit een sectie die er altijd staat. Hier stond 'CVE opzoeken
    // (online)', en dat blok hoort sinds #648 bij de module Informatieveiligheid
    // — met de module uit staat het er niet, en dan toetste dit baken de
    // module in plaats van de sprong.
    expect(find.text('Herstelbestanden nu wissen'), findsOneWidget);
  });

  // De koppeling tussen een zoekingang en het tabblad waar de instelling staat.
  //
  // Dit stond ooit in een kale `int`, en niets in de taal koppelde dat getal aan
  // het juiste tabblad: toen Git-repository op index 8 werd ingevoegd schoven
  // Checklists en Uitbreidingen een plek op en de registry niet, waarna
  // "checklist sjabloon" de gebruiker naar Git-repository stuurde. Sinds
  // SettingsSection wijst een ingang op naam en kán die fout niet meer ontstaan.
  //
  // De tests hieronder blijven staan omdat ze iets anders bewaken dan de
  // nummering: dat een ingang naar het tabblad wijst dat zijn sectiekop
  // daadwerkelijk rendert. Een sectie die naar een ander tabblad verhuist is
  // nog steeds stil fout — je landt gewoon ergens anders, zonder melding.

  /// De gezaghebbende koppeling tabblad → bouwer: de switch in
  /// settings_dialog.dart die per SettingsSection zijn body kiest.
  Map<String, String> sectionBuilders() {
    final src = File(
      'lib/widgets/dialogs/settings_dialog.dart',
    ).readAsStringSync();
    // Een body is een `_xxx()`-bouwer in de part-scope óf een losse widget
    // (`const IntegrationsPanel()`). Dat tweede bestaat sinds #631 de
    // panelen uit de gedeelde part-scope trekt en de dialoogklasse tegen haar
    // plafond zit; alleen `_`-bouwers herkennen zou zo'n tabblad stil buiten
    // deze telling laten vallen.
    final matches = RegExp(
      r'SettingsSection\.(\w+) => (?:const )?(_?\w+)\(',
    ).allMatches(src);
    final out = <String, String>{
      for (final m in matches) m.group(1)!: m.group(2)!,
    };
    expect(
      out,
      isNotEmpty,
      reason: 'de switch over SettingsSection is hernoemd of verplaatst',
    );
    return out;
  }

  test('elk tabblad heeft precies één body, in de volgorde van de enum', () {
    expect(
      sectionBuilders().keys.toList(),
      SettingsSection.values.map((s) => s.name).toList(),
      reason:
          'Tabblad toegevoegd, verwijderd of verplaatst? De switch in '
          'settings_dialog.dart moet elke SettingsSection precies één keer '
          'dekken, in de volgorde van de enum.',
    );
  });

  // De test hierboven slaat sectieloze ingangen over: zonder sectiekop valt er
  // niets te herleiden. Daardoor zouden juist Documentatie en Over OciDeck —
  // die per se geen `_sectionTitle` gebruiken — ongedekt blijven.
  test('sectieloze ingangen staan alleen op tabbladen zonder bruikbaar anker', () {
    // Zonder `section` landt een treffer bovenaan het tabblad in plaats van bij
    // de instelling zelf. Dat mag alleen waar er niets is om naartoe te scrollen:
    //   ai            — op desktop geen sectiekoppen (alleen de web-variant
    //                   toont er één, met de "niet beschikbaar"-melding);
    //   documentation — werkt met DocSection in plaats van _sectionTitle;
    //   about         — werkt met _aboutHeading.
    // Komt hier een tabblad bij, vraag je dan af of de instelling niet gewoon
    // een sectie verdient.
    const allowed = {
      SettingsSection.ai,
      SettingsSection.documentation,
      SettingsSection.about,
    };

    final sectionless = kSettingsSearchIndex
        .where((e) => e.section == null && e.sectionKey == null)
        .toList();
    expect(
      sectionless,
      isNotEmpty,
      reason: 'de sectieloze ingangen zijn verdwenen; dan mag deze test weg',
    );

    final misplaced = sectionless
        .where((e) => !allowed.contains(e.tab))
        .map(
          (e) =>
              '"${e.label ?? e.labelKey}" wijst zonder sectie naar '
              '${e.tab.name}, en dát tabblad heeft wél ankers — geef de ingang '
              'een `section`, anders landt de gebruiker bovenaan in plaats van '
              'bij de instelling zelf',
        )
        .toList();
    expect(misplaced, isEmpty, reason: misplaced.join('\n'));
  });

  testWidgets('een treffer zonder sectie opent het tabblad zelf', (
    tester,
  ) async {
    await openSettings(tester);
    await search(tester, 'sneltoets');

    // Treffers herken je aan hun pijl. De labels zelf staan óók in de
    // (mee-opgebouwde) tabbladen, dus scopen we strak op de resultatenlijst.
    final hits = find.ancestor(
      of: find.byIcon(Icons.arrow_forward),
      matching: find.byType(ListTile),
    );
    expect(hits, findsOneWidget);

    // Zonder sectie is het kruimelpad alleen het tabblad — geen '›'.
    expect(
      find.descendant(of: hits, matching: find.text('Documentatie')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: hits, matching: find.text('Sneltoetsen')),
    );
    await tester.pumpAndSettle();

    // De kop van het contentvlak toont het geselecteerde tabblad; die Text is
    // aan zijn corpsgrootte te onderscheiden van het zijbalklabel.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == 'Documentatie' && w.style?.fontSize == 18,
      ),
      findsOneWidget,
    );
    // En de resultatenlijst is opgeruimd — de sprong liep niet vast op het
    // ontbrekende anker.
    expect(hits, findsNothing);
  });

  test('elke zoekterm wijst naar het tabblad dat zijn sectie rendert', () {
    final builders = sectionBuilders();

    // De opslagwijzen renderen hun sectiekop in een eigen paneel in plaats van
    // in de body van het tabblad, dus de scan hieronder vindt ze niet vanzelf.
    // Ze horen wél bij Opslag: het paneel klapt binnen dat tabblad open.
    const extraOwners = {
      '_webdavPanel': 'storage',
      '_gitPanel': 'storage',
      // _cockpitTab wordt sinds #1957 ingeklapt aangeroepen vanuit
      // _presentationStyleTab, dus zijn secties horen bij presentatie.
      '_cockpitTab': 'presentation',
    };
    final ownerOf = <String, String>{
      for (final e in builders.entries) e.value: e.key,
      ...extraOwners,
    };

    // Elke bouwer is één `Widget _xxx(`; zijn body loopt tot de volgende
    // top-level Widget in hetzelfde bestand.
    final sources = Directory('lib/widgets/dialogs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .toList();
    final spans = <String, String>{};
    for (final builder in ownerOf.keys) {
      for (final src in sources) {
        final start = RegExp('\\n  Widget $builder\\(').firstMatch(src);
        if (start != null) {
          final rest = src.substring(start.end);
          final next = RegExp(r'\n  Widget _\w+\(').firstMatch(rest);
          spans[builder] = next == null ? rest : rest.substring(0, next.start);
          break;
        }
        // Een losse widget als tabbladinhoud: zijn body loopt tot de volgende
        // top-level klasse in hetzelfde bestand.
        final widget = RegExp('\\nclass $builder extends').firstMatch(src);
        if (widget == null) continue;
        final rest = src.substring(widget.end);
        final next = RegExp(r'\nclass \w+ extends').firstMatch(rest);
        spans[builder] = next == null ? rest : rest.substring(0, next.start);
        break;
      }
    }

    final wrong = <String>[];
    var resolved = 0;
    for (final entry in kSettingsSearchIndex) {
      final section = entry.section;
      if (section == null) continue;
      final escaped = section.replaceAll("'", r"\'");
      final owners = ownerOf.keys
          .where(
            (b) =>
                (spans[b] ?? '').contains("_sectionTitle(l10n.d('$escaped')") ||
                (spans[b] ?? '').contains("_sectionTitle('$escaped')") ||
                // Een losse widget roept SettingsSectionTitle rechtstreeks aan;
                // `_sectionTitle` is de helper die daarnaar doorgeeft.
                (spans[b] ?? '').contains(
                  "SettingsSectionTitle(l10n.d('$escaped')",
                ) ||
                (spans[b] ?? '').contains(
                  "_presentationStyleDivider(l10n.d('$escaped')",
                ),
          )
          .toList();
      // Secties die een hulpmethode buiten de body rendert, zijn hier niet toe
      // te wijzen; die slaan we over in plaats van vals alarm te slaan.
      if (owners.length != 1) continue;
      resolved++;
      final expected = ownerOf[owners.single];
      if (entry.tab.name != expected) {
        wrong.add(
          '"${entry.label ?? entry.labelKey}" (sectie "$section") wijst naar '
          '${entry.tab.name} maar staat in ${owners.single} = $expected',
        );
      }
    }

    expect(
      wrong,
      isEmpty,
      reason:
          'Zoekresultaten springen naar het verkeerde tabblad:\n'
          '${wrong.join('\n')}',
    );
    // Vangnet: zou de afleiding ooit stuklopen, dan mag deze test niet stil
    // verworden tot een test die niets meer controleert.
    expect(
      resolved,
      greaterThanOrEqualTo(20),
      reason: 'te weinig secties toewijsbaar — is _sectionTitle hernoemd?',
    );
  });

  // De registry dupliceert de bronstrings van de tabbladen. Dat mag, maar dan
  // moet hij ook meebewegen: een sectiekop die nergens meer door _sectionTitle
  // gaat, is een anker dat nooit meer aanslaat — en dat merk je anders pas als
  // een gebruiker op een treffer klikt en er niets gebeurt.
  test('every indexed section title still exists in the settings parts', () {
    final sources = Directory('lib/widgets/dialogs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    // Een sectiekop komt binnen via de widget [SettingsSectionTitle], via de
    // helper `_sectionTitle` die daarnaar doorgeeft (de panelen die nog in de
    // gedeelde part-scope leven), of via _presentationStyleDivider — die zijn
    // titel doorgeeft en dus hetzelfde anker registreert. Alle drie registreren
    // hetzelfde anker; het gaat erom dát de kop nog getekend wordt.
    final missing = <String>[];
    for (final entry in kSettingsSearchIndex) {
      final section = entry.section;
      if (section == null) continue;
      final escaped = section.replaceAll("'", r"\'");
      final rendered = [
        "_sectionTitle(l10n.d('$escaped')",
        "_sectionTitle('$escaped')",
        "SettingsSectionTitle(l10n.d('$escaped')",
        "SettingsSectionTitle('$escaped')",
        "_presentationStyleDivider(l10n.d('$escaped')",
      ];
      if (!rendered.any(sources.contains)) missing.add(section);
    }

    expect(
      missing,
      isEmpty,
      reason:
          'Deze sectiekoppen staan in kSettingsSearchIndex maar worden nergens '
          'meer door _sectionTitle gerenderd, dus hun anker grijpt mis: '
          '${missing.join(', ')}',
    );
  });

  // ── AI-assistentie: de zoekingangen volgen het tabblad (#731) ──────────────
  //
  // Sinds AI een module is, bestaat zijn tabblad niet meer met verse
  // voorkeuren. Een treffer die daarheen springt komt dan op niets uit —
  // dezelfde fout die #648 voor Informatieveiligheid repareerde. De `aiOnly`-
  // vlag op de ingangen is de reparatie; dit is wat haar bewaakt.

  testWidgets(
    'met de module uit vindt "ai" alleen de plek om hem aan te zetten',
    (tester) async {
      await openSettings(tester);
      await search(tester, 'ai');

      // Treffers herken je aan hun pijl; de labels staan óók in de
      // mee-opgebouwde tabbladen, dus scopen we strak op de resultatenlijst.
      final hits = find.ancestor(
        of: find.byIcon(Icons.arrow_forward),
        matching: find.byType(ListTile),
      );

      // Wat je wél vindt: de modulekaart. Zoeken naar een functie die de app
      // heeft, mag nooit "geen instelling gevonden" opleveren.
      expect(
        find.descendant(of: hits, matching: find.text('AI-assistentie')),
        findsOneWidget,
      );
      expect(find.text('Geen instelling gevonden'), findsNothing);

      // Wat je niet vindt: de configuratie, want dat tabblad is er niet.
      for (final label in const ['AI-backend', 'Modelnaam']) {
        expect(
          find.descendant(of: hits, matching: find.text(label)),
          findsNothing,
          reason: '"$label" springt naar een tabblad dat niet bestaat',
        );
      }
    },
  );

  testWidgets('een ingestelde backend maakt de configuratie weer vindbaar', (
    tester,
  ) async {
    // Spiegelt de zichtbaarheid van het tabblad zelf: tonen zodra de inhoud er
    // is, ook met de schakelaar uit — anders is de sleutel niet meer op te
    // ruimen én niet meer te vinden.
    SharedPreferences.setMockInitialValues({
      'aiSettings': jsonEncode(const {
        'enabled': false,
        'mode': 'local',
        'baseUrl': 'http://127.0.0.1:11434/v1',
      }),
    });
    await openSettings(tester);
    await search(tester, 'backend');

    expect(find.text('AI-backend'), findsWidgets);
    expect(find.text('Geen instelling gevonden'), findsNothing);
  });
}
