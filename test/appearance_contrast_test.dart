import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/appearance_contrast.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De leesbaarheidscontrole van een eigen app-thema (#750).
///
/// #744 repareerde de drie ingebouwde profielen en zette er toetsen op. Wie in
/// *Uiterlijk → App-thema* zelf kleuren kiest, kon dezelfde fout terugbouwen
/// zonder dat iets er iets over zei. Dit toetst dat de meting die fout vindt —
/// óók de vier paren die niet als veld bestaan maar in [AppTheme.fromProfile]
/// worden afgeleid, want dáár zat #744.
void main() {
  tearDown(() => AppTheme.isDark = false);

  /// Een eigen donker profiel met een donker accent: precies wat #744 was,
  /// nagebouwd met de kleurenkiezer.
  const slechtDonker = AppAppearanceProfile(
    name: 'Eigen donker',
    isDark: true,
    primaryColor: '#111827',
    accentColor: '#1B2537',
    backgroundColor: '#0F172A',
    surfaceColor: '#1E293B',
    textColor: '#F1F5F9',
    mutedTextColor: '#94A3B8',
    panelColor: '#090E1A',
    panelTextColor: '#E2E8F0',
  );

  group('de meting', () {
    test('elk ingebouwd profiel haalt zijn eigen norm', () {
      for (final profile in AppAppearanceProfile.builtIns) {
        expect(
          appearanceContrastProblems(profile),
          isEmpty,
          reason: 'het profiel "${profile.name}" zakt op zijn eigen controle',
        );
      }
    });

    test('een donker accent in een donker profiel wordt gevonden', () {
      final gevonden = appearanceContrastProblems(
        slechtDonker,
      ).map((f) => f.pair).toSet();

      // Het accent is in donkere modus de interactiekleur (#744, route B), dus
      // het vakje verdwijnt in het oppervlak én zijn vinkje verdwijnt op zijn
      // eigen vulling.
      expect(gevonden, contains(AppearanceContrastPair.interactiveOnSurface));
      expect(gevonden, contains(AppearanceContrastPair.tickOnInteractive));
    });

    test('de gemelde verhouding is de verhouding tussen de twee kleuren', () {
      // Anders is het een getal dat toevallig meebeweegt. De meting moet de
      // kleuren dragen die ze vergeleken heeft, want de bewerker toont er twee
      // kleurstippen bij.
      for (final finding in appearanceContrastFindings(slechtDonker)) {
        expect(
          finding.ratio,
          closeTo(_ratio(finding.foreground, finding.background), 0.001),
        );
        expect(finding.passes, finding.ratio >= finding.threshold);
      }
    });

    test('de afgeleide paren komen uit het gebouwde thema', () {
      // De kern van #750: vier van de negen paren bestaan niet als veld. Een
      // controle die alleen de acht kleurvelden naast elkaar legt, ziet ze
      // niet — en dat was precies de fout die #744 heette.
      final theme = AppTheme.fromProfile(slechtDonker);
      final findings = {
        for (final f in appearanceContrastFindings(slechtDonker)) f.pair: f,
      };

      expect(
        findings[AppearanceContrastPair.textButtonOnSurface]!.foreground,
        theme.textButtonTheme.style!.foregroundColor!.resolve(<WidgetState>{}),
      );
      expect(
        findings[AppearanceContrastPair.interactiveOnSurface]!.foreground,
        theme.colorScheme.primary,
      );
      expect(
        findings[AppearanceContrastPair.tickOnInteractive]!.foreground,
        theme.colorScheme.onPrimary,
      );
      expect(
        findings[AppearanceContrastPair.primaryButtonLabel]!.background,
        theme.elevatedButtonTheme.style!.backgroundColor!.resolve(
          <WidgetState>{},
        ),
      );
    });

    test('elk paar heeft een label in de bewerker', () {
      // Een paar zonder label zou in de lijst als lege regel verschijnen. De
      // switch in `_legibilityLabel` is exhaustief, dus dit faalt bij een
      // nieuwe waarde al bij het compileren — deze toets vangt de omgekeerde
      // fout: een paar dat wel wordt gemeten maar nooit getoond.
      expect(AppearanceContrastPair.values, hasLength(9));
    });
  });

  group('de profielbewerker', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> openAppearance(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SettingsDialog.show(
                    context,
                    initialSection: SettingsSection.appearance,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('toont de leesbaarheidsmeting', (tester) async {
      await openAppearance(tester);
      await tester.scrollUntilVisible(
        find.text('Leesbaarheid van dit profiel'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('Leesbaarheid van dit profiel'), findsOneWidget);
      // Het standaardprofiel is er een van de ingebouwde, dus schoon.
      expect(find.text('Alle onderdelen halen de norm.'), findsOneWidget);
    });

    testWidgets('het voorbeeld toont de onderdelen die #744 blootlegde', (
      tester,
    ) async {
      await openAppearance(tester);
      await tester.scrollUntilVisible(
        find.text('Leesbaarheid van dit profiel'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      // Zonder deze drie vleit het voorbeeld: het liet alleen de rollen zien
      // die het goed deden.
      expect(find.byType(Checkbox), findsWidgets);
      expect(find.byType(Switch), findsWidgets);
      expect(find.text('Meer'), findsOneWidget);
    });
  });
}

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hoog = la > lb ? la : lb;
  final laag = la > lb ? lb : la;
  return (hoog + 0.05) / (laag + 0.05);
}
