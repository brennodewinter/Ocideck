import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/integration_registry.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/utils/color_contrast.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De zichtbaarheid van overloop in het instellingenvenster.
///
/// Met alle Uitbreidingen aan telt de zijbalk twaalf tabbladen, en op een
/// bescheiden venster past dat niet. Dat scrollde al — maar niets liet het
/// zien: de automatische scrollbalk verschijnt pas tíjdens het scrollen, en de
/// vaste merkvoet onder de lijst maskeerde de afsnijding, zodat de zijbalk er
/// compleet uitzag terwijl "Integraties" en "Documentatie" onvindbaar onder de
/// vouw lagen. Een navigatie-item dat je niet kunt zien is een functie die
/// niet bestaat.
///
/// Daarom twee blijvende signalen, en dit zijn hun waarheidsregels:
///
/// 1. de duim is er zodra er overloop is (en het framework tekent hem niet
///    wanneer alles past);
/// 2. de randvervaging vervaagt alléén de kant waar werkelijk meer inhoud
///    ligt, bouwt proportioneel af bij het naderen van het einde, en wie
///    onderaan staat ziet de lijst dus écht eindigen.
///
/// De vervagingsregel wordt hier tegen échte render-metrics gehouden — een
/// nagebouwde schatting van de lijsthoogte zou stil wegrotten van de widget
/// die hij voorspelt. Hoe het oogt, is een zaak voor de beeldkeuring.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Finder sidebar() => find.byKey(const Key('settings-sidebar'));

  /// Opent het venster op een bescheiden scherm, met de modules onthuld die
  /// de zijbalk naar zijn maximum duwen (Checklists en — op desktop —
  /// Integraties erbij).
  Future<void> openSettings(
    WidgetTester tester, {
    Size surface = const Size(1100, 640),
    bool allModulesRevealed = true,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (allModulesRevealed) ...[
            infoSafetyRevealProvider.overrideWithValue(true),
            anyIntegrationAvailableProvider.overrideWithValue(true),
          ],
        ],
        child: MaterialApp(
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

  /// De scrollpositie van de zijbalklijst, via de duim die eraan hangt.
  ScrollPosition sidebarPosition(WidgetTester tester) {
    final bar = tester.widget<RawScrollbar>(
      find.descendant(of: sidebar(), matching: find.byType(RawScrollbar)),
    );
    return bar.controller!.position;
  }

  testWidgets('overloop toont een duim en een eerlijke randvervaging', (
    tester,
  ) async {
    await openSettings(tester);

    final position = sidebarPosition(tester);
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason:
          'Deze toets bewijst alleen iets als de lijst werkelijk overloopt; '
          'past alles opeens, verklein dan het testvenster.',
    );

    // Vóór enig scrollen: het laatste tabblad is onbereikbaar…
    expect(find.text('Documentatie').hitTestable(), findsNothing);

    // …maar de signalen staan er al: de blijvende duim en een vervaagde
    // onderrand (en géén vervaagde bovenrand, want daarboven ligt niets).
    expect(
      find.descendant(of: sidebar(), matching: find.byType(RawScrollbar)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar(), matching: find.byType(ShaderMask)),
      findsOneWidget,
    );
    var fades = settingsScrollFadeExtents(position);
    expect(fades.top, 0, reason: 'boven de lijst ligt niets');
    expect(fades.bottom, greaterThan(0), reason: 'onder de vouw ligt meer');

    // Nadert het einde, dan bouwt de vervaging proportioneel af: wat er nog
    // ligt ís de vervaging.
    position.jumpTo(position.maxScrollExtent - 10);
    await tester.pump();
    fades = settingsScrollFadeExtents(position);
    expect(fades.bottom, moreOrLessEquals(10));

    // Onderaan draait het beeld om: de lijst eindigt daar écht, dus geen
    // ondervervaging meer — en het laatste tabblad is nu gewoon te openen.
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    fades = settingsScrollFadeExtents(position);
    expect(fades.top, greaterThan(0));
    expect(fades.bottom, 0, reason: 'een vervaagd einde zou liegen');

    await tester.tap(find.text('Documentatie').hitTestable());
    await tester.pumpAndSettle();
    final stack = tester.widget<IndexedStack>(
      find
          .descendant(
            of: find.byType(SettingsDialog),
            matching: find.byType(IndexedStack),
          )
          .first,
    );
    expect(stack.index, SettingsSection.documentation.index);
  });

  test('de vervaging volgt de scrollpositie, niet de gewoonte', () {
    ScrollMetrics at(double pixels, {double max = 400}) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: max,
      pixels: pixels,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    // Past alles, dan is er niets te vervagen.
    expect(settingsScrollFadeExtents(at(0, max: 0)), (top: 0.0, bottom: 0.0));
    // Bovenaan vervaagt alleen de onderrand, middenin allebei, onderaan
    // alleen de bovenrand.
    expect(settingsScrollFadeExtents(at(0)).top, 0);
    expect(settingsScrollFadeExtents(at(0)).bottom, greaterThan(0));
    expect(settingsScrollFadeExtents(at(200)).top, greaterThan(0));
    expect(settingsScrollFadeExtents(at(200)).bottom, greaterThan(0));
    expect(settingsScrollFadeExtents(at(400)).top, greaterThan(0));
    expect(settingsScrollFadeExtents(at(400)).bottom, 0);
    // En vlak bij een rand is de vervaging precies wat er nog ligt.
    expect(settingsScrollFadeExtents(at(7)).top, 7);
    expect(settingsScrollFadeExtents(at(393)).bottom, 7);
  });

  test('de duim haalt 3:1 op het hele zijbalkverloop (WCAG 1.4.11)', () {
    // De zijbalk is een verloop van navySoft naar navy; de duim moet op beide
    // uiteinden leesbaar zijn, anders is de affordance er alleen in theorie.
    for (final achtergrond in [AppTheme.navy, AppTheme.navySoft]) {
      final zichtbaar = Color.alphaBlend(
        settingsSidebarThumbColor,
        achtergrond,
      );
      expect(
        contrastRatio(zichtbaar, achtergrond),
        greaterThanOrEqualTo(3.0),
        reason: 'niet-tekstcontrast op $achtergrond',
      );
    }
  });
}
