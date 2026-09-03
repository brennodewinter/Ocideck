import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/editors/expanded_markdown_dialog.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

/// Stresspoort tegen RenderFlex-overflows in de interface.
///
/// Waaróm deze test bestaat. Een overflow meldt zich in Flutter alleen als een
/// widget écht te klein wordt neergelegd; een scherm dat nooit bij een extreme
/// conditie gepompt wordt, glipt er ongezien langs. Precies zo kwam #1146 op
/// main: het welkom-merk-paneel liep 266px over bij 200% interface-tekst, maar
/// dat bleek pas toen een test het bij díe conditie rende. Een enkele
/// happy-path-grootte ziet zulke fouten niet.
///
/// Wat deze test doet. Elk geregistreerd top-level oppervlak wordt gerenderd
/// tegen een reeks veeleisende viewports — smal, kort, en het WCAG-plafond van
/// 200% interface-tekst — en faalt bij de éérste RenderFlex-overflow. Zo wordt
/// deze klasse fouten door de poort gevangen in plaats van via een directe push
/// op een rode main te ontsnappen.
///
/// EEN SCHERM TOEVOEGEN. Zet een [_Surface] in [_surfaces] met een pump-functie
/// die het oppervlak zichtbaar op [AppShell] achterlaat. Nieuwe schermen,
/// dialogen en panelen horen hier bij te komen; de kosten zijn één entry, de
/// winst is dat het scherm nooit stil kan gaan overlopen. Overweeg dit standaard
/// bij elk nieuw top-level oppervlak.

/// Viewports voor een oppervlak-op-schermgrootte (welkomscherm, een paneel):
/// breed-maar-kort en smal dwingen de verticale as het hardst, waar
/// Column/Spacer-overflows vandaan komen. Smal hoort erbij omdat zulke
/// oppervlakken ook op het web draaien, zonder minimum vensterbreedte.
/// 600×600 dekt de grens waar de instellingen-dialoog net de rail-layout
/// kiest en het zoekveld krap wordt (#1885); 320×568 is een telefoonbreedte
/// op het web.
const _fullViewportSizes = <(String, Size)>[
  ('breed 1200x800', Size(1200, 800)),
  ('breed-en-kort 1100x560', Size(1100, 560)),
  ('smal 600x600', Size(600, 600)),
  ('smal 440x760', Size(440, 760)),
  ('smal-en-kort 400x600', Size(400, 600)),
  ('telefoon 320x568', Size(320, 568)),
];

/// Viewports voor een modaal dialoog. Een dialoog rendert nooit smaller dan het
/// venster, en de app dwingt een minimum van 1000x650 af (zie
/// `lib/platform/native_window_io.dart`, `minimumWindowSize`). Toetsen onder die
/// grens zou een onbereikbare stand keuren; wél de korte- en hoge-inhoud-hoeken
/// binnen dat werkgebied, want 200% tekst dwingt vooral de verticale as.
/// 600×600 zit alleen in `_narrowSettingsViewports` (per-tabblad-lus), niet
/// hier: de markdown-tekstverwerker-dialoog deelt deze lijst en diens
/// Quill-toolbar loopt op die breedte bij 200% tekst — een apart probleem
/// buiten #1885. 320×568 zit in een aparte 100%-tekst-lus hieronder, want bij
/// 200% tekst is een telefoonbreedte een extreme stand die veel losse
/// overlopen opent buiten #1885.
const _dialogViewportSizes = <(String, Size)>[
  ('minimumvenster 1000x650', Size(1000, 650)),
  ('minimumbreedte, hoog 1000x900', Size(1000, 900)),
  ('breed-en-kort 1300x680', Size(1300, 680)),
  ('breed 1500x1000', Size(1500, 1000)),
];

/// De interface-tekstschaal waarop getoetst wordt: 200%, het plafond dat de
/// instelling toestaat (WCAG 1.4.4). Dit is de zwaarste stand voor de layout.
const _stressTextScale = 2.0;

/// Eén te bewaken oppervlak: een naam voor de foutmelding, een functie die het
/// oppervlak op het scherm zet en op [AppShell] laat staan, en de viewports
/// waartegen het getoetst wordt (een schermgroot oppervlak krijgt andere maten
/// dan een dialoog dat aan het minimumvenster gebonden is).
typedef _Surface = ({
  String name,
  Future<void> Function(WidgetTester) pump,
  List<(String, Size)> sizes,
});

final _surfaces = <_Surface>[
  // Het welkomscherm — het oppervlak waar #1146 overliep. Zonder open deck en
  // met geaccepteerde toestemming toont [OciDeckApp] dit scherm meteen.
  (
    name: 'welkomscherm',
    pump: (tester) async {
      SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();
    },
    sizes: _fullViewportSizes,
  ),
  // Het instellingen-dialoog op de dialoog-maten (binnen het bureaublad-
  // minimum), een klassieke overflow-kandidaat. Let op: dit toetst alleen het
  // actieve tabblad — de IndexedStack tékent de rest niet, en een overflow
  // meldt zich pas bij het tekenen. Alle tabbladen los komen in de per-sectie-
  // lus onderaan aan bod; deze entry bewaakt de dialoog-schil (zijbalk, kop,
  // voet) over de vier hoeken van het werkgebied.
  (
    name: 'instellingen-dialoog',
    pump: _pumpSettingsDialog,
    sizes: _dialogViewportSizes,
  ),
  // Het uitklap-tekstverwerker-dialoog voor een Markdown-veld. De kop draagt de
  // modus-schakelaar én de opmaakbalk; bij 200% tekst moeten die wikkelen in
  // plaats van overlopen. Rechtstreeks op [AppShell] geopend zodat het dialoog
  // de tekstschaal via dezelfde gedeelde MediaQuery erft.
  (
    name: 'markdown-tekstverwerker',
    pump: (tester) async {
      SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();
      final controller = TextEditingController(
        text:
            '# Een kop\n\nEen alinea met **vet** en *cursief* en een '
            'behoorlijk lange regel die de beschikbare breedte vult.',
      );
      addTearDown(controller.dispose);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(AppShell)),
          builder: (_) => ExpandedMarkdownDialog(
            label: 'Beschrijving',
            hint: 'Tekst',
            sourceController: controller,
            editorTheme: MarkdownEditorTheme.editorPanel(
              text: const Color(0xFF1E293B),
              link: const Color(0xFF003399),
              accent: const Color(0xFF003399),
              codeBackground: const Color(0xFFF1F5F9),
              border: const Color(0xFFCBD5E1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    },
    sizes: _dialogViewportSizes,
  ),
  // Het openen-dialoog met een selectie erin. Sinds #1928 draagt de voet drie
  // knoppen (Bladeren…, Annuleren, Openen (n)) plus de regel die de
  // meervoudige selectie uitlegt; bij 200% tekst moet die rij wikkelen in
  // plaats van overlopen. Mét selectie, want de derde knop bestaat pas dan —
  // en juist die maakt de rij te lang.
  (
    name: 'openen-dialoog met selectie',
    pump: _pumpOpenDialogWithSelection,
    sizes: _dialogViewportSizes,
  ),
];

/// Opent het openen-dialoog met twee aangewezen bestanden, zodat de voet zijn
/// zwaarste stand draagt. Schrijft twee echte decks: de dialoog leest zijn
/// lijst van schijf, en zonder rijen valt er niets aan te wijzen.
Future<void> _pumpOpenDialogWithSelection(WidgetTester tester) async {
  final dir = Directory.systemTemp.createTempSync('overflow_open_dialog');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  for (final name in ['Alfa', 'Bravo']) {
    File('${dir.path}/${name.toLowerCase()}.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: $name\n---\n\n# $name\n',
    );
  }
  SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  await container.read(settingsProvider.notifier).addLibrary('Test', dir.path);
  await tester.pumpAndSettle();

  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  // De mapscan leest écht van schijf; dat is geen microtask die pumpAndSettle
  // uitzit.
  await pumpUntil(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    reason: 'de mapscan bleef laden',
  );

  for (final title in ['Alfa', 'Bravo']) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text(title));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.pumpAndSettle();
}

/// Smalle web-viewports voor het instellingen-dialoog. Op het web is er geen
/// minimum vensterbreedte, dus de dialoogbreedte zakt naar zijn eigen vloer en
/// de zijbalk klapt in; het bureaublad-minimum (1000x650) geeft een ruimere
/// breedte, waardoor deze overflow alleen op het web bereikbaar is. Twee
/// breedtes omdat ze verschillende standen raken: 400 zakt onder de
/// zijbalk-inklapgrens, 440 zit er net boven. Deze worden in de per-sectie-lus
/// gebruikt (niet als `_Surface`-entry), zodat élk tabblad los getoetst wordt.
const _narrowSettingsViewports = <(String, Size)>[
  ('smal-en-kort 400x600', Size(400, 600)),
  ('smal 440x760', Size(440, 760)),
  ('smal web 600x600', Size(600, 600)),
];

/// Opent het instellingen-dialoog vanuit de echte app-context, die [AppShell]
/// heeft zodat de harness de tekstschaal langs dezelfde weg zet; het dialoog
/// erft die schaal via de gedeelde MediaQuery.
Future<void> _pumpSettingsDialog(WidgetTester tester) async {
  await _openSettingsDialog(tester);
}

/// Idem, maar met een gekozen begin-tabblad. Nodig voor de per-sectie-toets
/// hieronder: de [IndexedStack] in het dialoog tékent alleen het actieve
/// tabblad, en een RenderFlex-overflow meldt zich pas bij het tekenen — een
/// tabblad dat nooit actief is, glipt er ongezien langs. Door per sectie te
/// openen wordt élk tabblad daadwerkelijk gerenderd en getoetst.
Future<void> _openSettingsDialog(
  WidgetTester tester, {
  SettingsSection? section,
}) async {
  SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
  await tester.pumpAndSettle();
  unawaited(
    SettingsDialog.show(
      tester.element(find.byType(AppShell)),
      initialSection: section ?? SettingsSection.general,
    ),
  );
  await tester.pumpAndSettle();
}

/// Zet de tekstschaal langs de echte weg (de settings-provider die de app op
/// MediaQuery toepast), niet via een losse MediaQuery-override, zodat de conditie
/// exact overeenkomt met wat een gebruiker instelt.
Future<void> _applyStressTextScale(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  await container
      .read(settingsProvider.notifier)
      .setUiTextScale(_stressTextScale);
  await tester.pumpAndSettle();
}

/// Zet de venstermaat via `tester.view.physicalSize` (niet
/// `binding.setSurfaceSize`): `setSurfaceSize` verandert de rendersurface maar
/// `MediaQuery.sizeOf` leest de `FlutterView`, die de wijziging niet ziet —
/// breedte-afhankelijke takken bleven op 800 px draaien en de poort zag de
/// overlopen niet (#1884).
void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  for (final surface in _surfaces) {
    for (final (sizeLabel, size) in surface.sizes) {
      testWidgets(
        '${surface.name} loopt niet over bij 200% tekst op $sizeLabel',
        (tester) async {
          _setViewport(tester, size);

          await surface.pump(tester);
          await _applyStressTextScale(tester);

          expect(
            tester.takeException(),
            isNull,
            reason:
                '${surface.name} loopt over op $sizeLabel bij '
                '${(_stressTextScale * 100).round()}% interface-tekst',
          );
        },
      );
    }
  }

  // Elk instellingen-tabblad los, op de smalle web-viewports bij 200% tekst. Een
  // gewone `_Surface`-entry toetst maar het actieve tabblad (de IndexedStack
  // tekent de rest niet en een overflow meldt zich pas bij het tekenen); deze lus
  // opent élke sectie apart zodat een overflow in gelijk welk tabblad de poort
  // haalt. Zo staat de belofte "loopt niet over bij 200% tekst op smal web" voor
  // het hele dialoog, niet alleen voor het tabblad dat toevallig bovenop lag.
  for (final section in SettingsSection.values) {
    for (final (sizeLabel, size) in _narrowSettingsViewports) {
      testWidgets(
        'instellingen-tabblad ${section.name} loopt niet over bij 200% tekst '
        'op $sizeLabel',
        (tester) async {
          _setViewport(tester, size);

          await _openSettingsDialog(tester, section: section);
          await _applyStressTextScale(tester);
          // Nog een frame forceren: de overflow-indicator meldt zich bij het
          // tekenen, niet bij de layout, dus het actieve tabblad moet echt
          // geschilderd worden nadat de schaal gezet is.
          tester.binding.scheduleFrame();
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason:
                'instellingen-tabblad ${section.name} loopt over op $sizeLabel '
                'bij ${(_stressTextScale * 100).round()}% interface-tekst',
          );
        },
      );
    }
  }

  // 320×568 (telefoonbreedte op het web) bij standaardtekst — de maat waarop
  // #1885 de 54-px-overloop mat. Bij 200% tekst opent deze breedte veel losse
  // overlopen buiten dit issue; die zijn een aparte zorg. Hier gaat het erom
  // dat het zoekveld en de dialoog-schil op telefoonbreedte niet overlopen.
  for (final section in SettingsSection.values) {
    testWidgets(
      'instellingen-tabblad ${section.name} loopt niet over op telefoon web '
      '320x568 bij 100% tekst',
      (tester) async {
        _setViewport(tester, const Size(320, 568));

        await _openSettingsDialog(tester, section: section);
        // Geen _applyStressTextScale: 100% tekst, zoals het issue mat.
        tester.binding.scheduleFrame();
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'instellingen-tabblad ${section.name} loopt over op telefoon web '
              '320x568 bij 100% interface-tekst',
        );
      },
    );
  }
}
