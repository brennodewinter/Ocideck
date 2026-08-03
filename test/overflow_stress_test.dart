import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
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

/// De viewports waartegen elk oppervlak getoetst wordt. Bewust uiteenlopend:
/// breed-maar-kort en smal dwingen de verticale as het hardst, waar
/// Column/Spacer-overflows vandaan komen.
const _stressSizes = <(String, Size)>[
  ('breed 1200x800', Size(1200, 800)),
  ('breed-en-kort 1100x560', Size(1100, 560)),
  ('smal 440x760', Size(440, 760)),
  ('smal-en-kort 400x600', Size(400, 600)),
];

/// De interface-tekstschaal waarop getoetst wordt: 200%, het plafond dat de
/// instelling toestaat (WCAG 1.4.4). Dit is de zwaarste stand voor de layout.
const _stressTextScale = 2.0;

/// Eén te bewaken oppervlak: een naam voor de foutmelding en een functie die het
/// oppervlak op het scherm zet en op [AppShell] laat staan.
typedef _Surface = ({String name, Future<void> Function(WidgetTester) pump});

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
  ),
];

void main() {
  for (final surface in _surfaces) {
    for (final (sizeLabel, size) in _stressSizes) {
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
