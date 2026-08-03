import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/editors/expanded_markdown_dialog.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
const _fullViewportSizes = <(String, Size)>[
  ('breed 1200x800', Size(1200, 800)),
  ('breed-en-kort 1100x560', Size(1100, 560)),
  ('smal 440x760', Size(440, 760)),
  ('smal-en-kort 400x600', Size(400, 600)),
];

/// Viewports voor een modaal dialoog. Een dialoog rendert nooit smaller dan het
/// venster, en de app dwingt een minimum van 1000x650 af (zie
/// `lib/platform/native_window_io.dart`, `minimumWindowSize`). Toetsen onder die
/// grens zou een onbereikbare stand keuren; wél de korte- en hoge-inhoud-hoeken
/// binnen dat werkgebied, want 200% tekst dwingt vooral de verticale as.
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
  // Het instellingen-dialoog — veel velden over acht tabbladen (in een
  // IndexedStack, dus één render raakt ze allemaal), een klassieke overflow-
  // kandidaat. Geopend vanuit de echte app-context, die [AppShell] heeft zodat
  // de harness de tekstschaal langs dezelfde weg zet; het dialoog erft die
  // schaal via de gedeelde MediaQuery.
  (
    name: 'instellingen-dialoog',
    pump: (tester) async {
      SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();
      unawaited(SettingsDialog.show(tester.element(find.byType(AppShell))));
      await tester.pumpAndSettle();
    },
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
];

void main() {
  for (final surface in _surfaces) {
    for (final (sizeLabel, size) in surface.sizes) {
      testWidgets(
        '${surface.name} loopt niet over bij 200% tekst op $sizeLabel',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await surface.pump(tester);

          // De tekstschaal langs de echte weg zetten (de settings-provider die de
          // app op MediaQuery toepast), niet via een losse MediaQuery-override,
          // zodat de conditie exact overeenkomt met wat een gebruiker instelt.
          final container = ProviderScope.containerOf(
            tester.element(find.byType(AppShell)),
          );
          await container
              .read(settingsProvider.notifier)
              .setUiTextScale(_stressTextScale);
          await tester.pumpAndSettle();

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
}
