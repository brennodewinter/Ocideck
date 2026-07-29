@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_wizard_models.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/openkat/openkat_wizard_service.dart';
import 'package:ocideck/state/openkat_wizard_controller.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_scenario_card.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_wizard_steps.dart';

import '../openkat_wizard_test_fakes.dart';

const _surfaceKey = ValueKey('openkat-golden-surface');

Future<void> _match(
  WidgetTester tester, {
  required String name,
  required Widget child,
  bool dark = false,
  Size size = const Size(1000, 720),
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
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: true,
          textScaler: TextScaler.noScaling,
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

Widget _scenarioStates({required bool dark}) {
  final scan = wizardScan();
  final descriptors = OpenKatWizardService.scenarioDescriptors;
  final states = [
    OpenKatWizardScenarioAvailability(
      descriptor: descriptors[0],
      available: true,
    ),
    OpenKatWizardScenarioAvailability(
      descriptor: descriptors[1],
      available: true,
    ),
    OpenKatWizardScenarioAvailability(
      descriptor: descriptors[2],
      available: false,
      reason: OpenKatWizardUnavailableReason.noReliableCveReferences,
    ),
    OpenKatWizardScenarioAvailability(
      descriptor: descriptors[3],
      available: true,
    ),
  ];
  const titles = [
    'Managementoverzicht',
    'Voortgang per organisatie',
    'CVE-blootstelling',
    'Datakwaliteit',
  ];
  return GridView.builder(
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.55,
    ),
    itemCount: states.length,
    itemBuilder: (context, index) => OpenKatScenarioCard(
      scenario: states[index],
      facts: scan.preview,
      title: titles[index],
      description: index == 2
          ? 'Welke organisaties en systemen zijn aantoonbaar geraakt?'
          : 'Een feitelijke rapportopbouw op basis van de gevonden metingen.',
      recommendedLabel: 'Aanbevolen',
      selectedLabel: 'Geselecteerd',
      unavailableReason: index == 2
          ? 'Geen betrouwbare CVE-verwijzingen in alle bronnen'
          : null,
      selected: index == 0,
      onSelected: (_) {},
    ),
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

  testWidgets('scenariokaarten licht met geselecteerd en onbeschikbaar', (
    tester,
  ) async {
    await _match(
      tester,
      name: 'openkat_scenario_states_light',
      child: _scenarioStates(dark: false),
    );
  });

  testWidgets('scenariokaarten donker met geselecteerd en onbeschikbaar', (
    tester,
  ) async {
    await _match(
      tester,
      name: 'openkat_scenario_states_dark',
      child: _scenarioStates(dark: true),
      dark: true,
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
