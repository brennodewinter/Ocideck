import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The style-profile editor must warn about exactly the colour pairings the
/// deck-level quality panel would flag — the editor runs the real
/// `SlideQualityAnalyzer`, so any low-contrast combination (title, body, accent,
/// table, code, checklist, section) surfaces inline. This guards the case that
/// started it all: a "De Winter Information Solutions" profile whose title text
/// and title background were both white, hiding the title-slide heading.
///
/// Since the style tab splits into three surfaces, a colour only renders on the
/// surface it belongs to: the title pair on **Presentatie**, the accent on
/// **Algemeen**, the heading, the header/footer band and the accent as it lands
/// on that band on **Document**. So each test opens the style tab and picks that
/// surface — a warning that only fires on a surface nobody opens is no warning
/// at all.
const _warning = 'Te weinig contrast met de achtergrond — mogelijk onleesbaar.';

/// A fully-specified, legible profile. Individual colours are overridden per
/// test so no *incidental* default (e.g. the faint unchecked-checklist grey)
/// clouds the pair under test.
Map<String, Object?> _profile({
  String slideBackground = '#FFFFFF',
  String text = '#222222',
  String accent = '#003399',
  String checklistChecked = '#003399',
  String checklistUnchecked = '#475569',
  String tableText = '#222222',
  String tableHeaderText = '#FFFFFF',
  String tableHeaderBackground = '#14213D',
  String titleBackground = '#14213D',
  String titleText = '#FFFFFF',
  String sectionBackground = '#14213D',
  String codeBackground = '#14213D',
  String codeText = '#FFFFFF',
  String? documentHeading,
  String? documentBandText,
  String? documentBandBackground,
}) => {
  'name': 'Test',
  'documentHeadingColor': ?documentHeading,
  'documentBandTextColor': ?documentBandText,
  'documentBandBackgroundColor': ?documentBandBackground,
  'slideBackgroundColor': slideBackground,
  'textColor': text,
  'accentColor': accent,
  'checklistCheckedColor': checklistChecked,
  'checklistUncheckedColor': checklistUnchecked,
  'tableTextColor': tableText,
  'tableHeaderTextColor': tableHeaderText,
  'tableHeaderBackgroundColor': tableHeaderBackground,
  'titleBackgroundColor': titleBackground,
  'titleTextColor': titleText,
  'sectionBackgroundColor': sectionBackground,
  'codeBackgroundColor': codeBackground,
  'codeTextColor': codeText,
};

Future<void> _openWith(
  WidgetTester tester,
  Map<String, Object?> profile, {
  String surface = 'general',
}) async {
  SharedPreferences.setMockInitialValues({'themeProfile': jsonEncode(profile)});
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
                initialSection: SettingsSection.presentation,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  // settingsProvider loads SharedPreferences asynchronously; force its
  // construction and let the load settle so the dialog reads the seeded profile
  // rather than the built-in defaults captured in initState.
  final container = ProviderScope.containerOf(
    tester.element(find.text('open')),
    listen: false,
  );
  container.read(settingsProvider);
  await tester.pumpAndSettle();

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(Key('style-surface-$surface')));
  await tester.pumpAndSettle();
}

/// Unmount the tree so the ProviderScope disposes its container and cancels the
/// tabs autosave timer before the test ends.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('white title text on a white title background warns', (
    tester,
  ) async {
    await _openWith(
      tester,
      _profile(titleBackground: '#FFFFFF', titleText: '#FFFFFF'),
      surface: 'presentation',
    );

    expect(find.text(_warning, skipOffstage: false), findsOneWidget);
    // The exact ratio is shown inline, as in the quality panel: white on white
    // is 1.0:1.
    expect(find.text('1.0:1', skipOffstage: false), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('a fully legible profile shows no warning', (tester) async {
    await _openWith(tester, _profile());

    expect(find.text(_warning, skipOffstage: false), findsNothing);

    await _teardown(tester);
  });

  testWidgets('a non-title pair the quality panel flags also warns', (
    tester,
  ) async {
    // A near-white accent on a white slide background is a body-level contrast
    // failure the quality panel raises — the editor must surface it too, proving
    // the warning is not limited to the title colours.
    await _openWith(tester, _profile(accent: '#F5F5F5'));

    expect(find.text(_warning, skipOffstage: false), findsOneWidget);

    await _teardown(tester);
  });

  // De drie paren die alléén op het documentvlak bestaan. Ze stonden buiten de
  // reeks van de analyzer, dus kon een stijl een kop, een band of een link in
  // die band onleesbaar zetten zonder dat hier iets verscheen — terwijl elke
  // dia-kleur wél een waarschuwing kreeg. Elke toets isoleert één paar: de
  // andere twee halen hun drempel, dus de waarschuwing die verschijnt kan maar
  // van één kant komen.
  testWidgets('een te bleke documentkop waarschuwt op het documentvlak', (
    tester,
  ) async {
    // 2,85:1 op wit: onder de drempel voor grote tekst, waar een documentkop op
    // staat.
    await _openWith(
      tester,
      _profile(documentHeading: '#999999'),
      surface: 'document',
    );

    expect(find.text(_warning, skipOffstage: false), findsOneWidget);
    expect(find.text('2.8:1', skipOffstage: false), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('een onleesbare kop-/voetband waarschuwt op het documentvlak', (
    tester,
  ) async {
    // Een lichte band met te bleke tekst erop (2,5:1). Bewust licht en niet
    // donker: op een donkere band zou het accent er óók op wegvallen, en dan
    // zou de toets twee waarschuwingen tellen in plaats van dit ene paar te
    // isoleren. Het accent haalt hier 9,5:1 en zwijgt dus.
    await _openWith(
      tester,
      _profile(documentBandText: '#999999', documentBandBackground: '#F0F0F0'),
      surface: 'document',
    );

    expect(find.text(_warning, skipOffstage: false), findsOneWidget);
    expect(find.text('2.5:1', skipOffstage: false), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('een link die wegvalt op zijn eigen band waarschuwt', (
    tester,
  ) async {
    // Het accent haalt 10,9:1 op het papier en de bandtekst 16,0:1 op de band —
    // beide bestaande toetsen zwijgen dus terecht. Alleen het accent zoals het
    // óp de band landt (een link in de kop- of voettekst) zakt eronderdoor,
    // naar 1,5:1.
    await _openWith(
      tester,
      _profile(
        accent: '#003399',
        documentBandText: '#FFFFFF',
        documentBandBackground: '#14213D',
      ),
      surface: 'document',
    );

    expect(find.text(_warning, skipOffstage: false), findsOneWidget);
    expect(find.text('1.5:1', skipOffstage: false), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('een leesbaar documentvlak toont geen waarschuwing', (
    tester,
  ) async {
    await _openWith(
      tester,
      _profile(
        documentHeading: '#003399',
        documentBandText: '#222222',
        documentBandBackground: '#FFFFFF',
      ),
      surface: 'document',
    );

    expect(find.text(_warning, skipOffstage: false), findsNothing);

    await _teardown(tester);
  });
}
