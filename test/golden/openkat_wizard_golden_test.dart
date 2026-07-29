@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_wizard_models.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/state/openkat_wizard_controller.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_wizard_steps.dart';

import '../openkat_wizard_test_fakes.dart';

const _surfaceKey = ValueKey('openkat-golden-surface');

Future<void> _match(
  WidgetTester tester, {
  required String name,
  required Widget child,
  bool dark = false,
  Size size = const Size(1000, 720),
  Locale locale = const Locale('nl'),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  AppTheme.isDark = dark;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => AppTheme.isDark = false);

  final baseTheme = AppTheme.fromProfile(
    dark ? AppAppearanceProfile.dark : AppAppearanceProfile.basic,
  );
  final theme = baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(fontFamily: 'Ahem'),
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: true,
          textScaler: textScaler,
        ),
        child: Scaffold(
          backgroundColor: AppTheme.slate100,
          body: RepaintBoundary(
            key: _surfaceKey,
            child: ColoredBox(
              color: AppTheme.slate100,
              child: Padding(padding: const EdgeInsets.all(24), child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await expectLater(
    find.byKey(_surfaceKey),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Future<OpenKatWizardController> _preparedController({
  Deck? existingDeck,
}) async {
  final controller = OpenKatWizardController(
    gateway: FakeOpenKatWizardGateway(),
    existingDeck: existingDeck,
  );
  await controller.prepare('/rapportages');
  return controller;
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('vraagfamilie licht met aanbevolen en meer recepten', (
    tester,
  ) async {
    final controller = await _preparedController();
    addTearDown(controller.dispose);
    controller.toggleMoreRecipes();
    await _match(
      tester,
      name: 'openkat_scenario_states_light',
      size: const Size(1000, 1200),
      child: SingleChildScrollView(
        child: OpenKatScenarioStep(controller: controller),
      ),
    );
  });

  testWidgets('grootste vraagfamilie donker toont alle recepten', (
    tester,
  ) async {
    final controller = await _preparedController();
    addTearDown(controller.dispose);
    controller.chooseFamily(OpenKatReportFamilyId.organizationProgress);
    controller.toggleMoreRecipes();
    await _match(
      tester,
      name: 'openkat_scenario_states_dark',
      child: SingleChildScrollView(
        child: OpenKatScenarioStep(controller: controller),
      ),
      dark: true,
      size: const Size(1000, 1700),
    );
  });

  testWidgets('lange vertaling op tweehonderd procent blijft leesbaar', (
    tester,
  ) async {
    AppLocalizations.setActiveLanguageCode('de');
    final controller = await _preparedController();
    addTearDown(controller.dispose);
    addTearDown(() => AppLocalizations.setActiveLanguageCode('nl'));
    controller.chooseFamily(OpenKatReportFamilyId.organizationProgress);
    controller.toggleMoreRecipes();
    await _match(
      tester,
      name: 'openkat_scenario_long_200',
      child: SingleChildScrollView(
        child: OpenKatScenarioStep(controller: controller),
      ),
      locale: const Locale('de'),
      textScaler: const TextScaler.linear(2),
      size: const Size(1200, 3600),
    );
  });

  testWidgets('scanresultaat en scenariokeuze', (tester) async {
    final controller = await _preparedController();
    addTearDown(controller.dispose);
    await _match(
      tester,
      name: 'openkat_scan_result',
      child: SingleChildScrollView(
        child: OpenKatScenarioStep(controller: controller),
      ),
    );
  });

  testWidgets('controlescherm voor generatie', (tester) async {
    final controller = await _preparedController();
    addTearDown(controller.dispose);
    controller.chooseScenario(OpenKatWizardScenarioId.dataQuality);
    controller.next();
    await _match(
      tester,
      name: 'openkat_review',
      child: SingleChildScrollView(
        child: OpenKatReviewStep(controller: controller),
      ),
    );
  });

  testWidgets('bijwerkbevestiging met behoudsbelofte', (tester) async {
    final controller = await _preparedController(
      existingDeck: const Deck(title: 'Bestaand OpenKAT-rapport'),
    );
    addTearDown(controller.dispose);
    await _match(
      tester,
      name: 'openkat_update_confirmation',
      child: Center(
        child: OpenKatUpdateConfirmation(
          controller: controller,
          update: () async {},
          createNew: () async {},
        ),
      ),
    );
  });
}
