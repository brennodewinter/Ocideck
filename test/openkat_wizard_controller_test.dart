import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/openkat/openkat_wizard_models.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_wizard_service.dart';
import 'package:ocideck/state/openkat_wizard_controller.dart';

import 'openkat_wizard_test_fakes.dart';

class _RescanGateway extends FakeOpenKatWizardGateway {
  final Completer<OpenKatWizardScan> rescan = Completer();

  @override
  Future<OpenKatWizardScan> prepare(String directory) {
    prepareCalls++;
    if (prepareCalls == 1) return Future.value(prepared);
    return rescan.future;
  }
}

void main() {
  late FakeOpenKatWizardGateway gateway;
  late OpenKatWizardController controller;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    gateway = FakeOpenKatWizardGateway();
    controller = OpenKatWizardController(gateway: gateway);
    addTearDown(() => controller.dispose());
  });

  test('voorbereiden kiest veilige, bruikbare standaardwaarden', () async {
    await controller.prepare('/reports');

    expect(controller.scanStatus, OpenKatWizardScanStatus.ready);
    expect(controller.selectedScenarioId, OpenKatWizardScenarioId.portfolio);
    expect(controller.selectedOrganizationCode, 'org-a');
    expect(controller.selectedOrganizationCodes, {'org-a', 'org-b'});
    expect(controller.currentAsOf, DateTime.utc(2026, 7, 1));
    expect(
      controller.previousAsOf,
      isNull,
      reason: 'het managementrecept vraagt geen eerdere peildatum',
    );
    expect(controller.cveId, 'CVE-2026-12345');
    expect(controller.language, OpenKatReportLanguage.dutch);
    expect(controller.canContinue, isTrue);
  });

  test('rapporttaal volgt de actieve app-taal met Engels als uitweg', () async {
    AppLocalizations.setActiveLanguageCode('de');
    controller.dispose();
    controller = OpenKatWizardController(gateway: gateway);

    await controller.prepare('/reports');

    expect(controller.language, OpenKatReportLanguage.english);
  });

  test(
    'normaal scenario navigeert via invoer en behoudt keuzes bij teruggaan',
    () async {
      await controller.prepare('/reports');
      controller.chooseScenario(OpenKatWizardScenarioId.organizationProgress);
      controller.next();
      controller.chooseOrganization('org-a');
      controller.choosePreviousDate(DateTime.utc(2026, 6, 1));
      controller.chooseLanguage(OpenKatReportLanguage.english);
      controller.setTitle('Eigen titel');
      controller.toggleMoreSettings();
      controller.next();
      controller.back();

      expect(controller.step, OpenKatWizardStep.inputs);
      expect(controller.selectedOrganizationCode, 'org-a');
      expect(controller.previousAsOf, DateTime.utc(2026, 6, 1));
      expect(controller.language, OpenKatReportLanguage.english);
      expect(controller.reportTitle, 'Eigen titel');
      expect(controller.moreSettingsExpanded, isTrue);
    },
  );

  test('datakwaliteit slaat de overbodige invoerstap over', () async {
    await controller.prepare('/reports');
    controller.chooseScenario(OpenKatWizardScenarioId.dataQuality);

    controller.next();
    expect(controller.step, OpenKatWizardStep.review);

    controller.back();
    expect(controller.step, OpenKatWizardStep.scenario);
  });

  test('een onbeschikbaar scenario kan niet geselecteerd worden', () async {
    final scan = wizardScan(
      scenarios: [
        for (final descriptor in OpenKatWizardService.scenarioDescriptors)
          OpenKatWizardScenarioAvailability(
            descriptor: descriptor,
            available: descriptor.id != OpenKatWizardScenarioId.cveExposure,
          ),
      ],
    );
    gateway.prepared = scan;
    await controller.prepare('/reports');

    controller.chooseScenario(OpenKatWizardScenarioId.cveExposure);

    expect(controller.selectedScenarioId, OpenKatWizardScenarioId.portfolio);
  });

  test(
    'opgeslagen recept wint van defaults, mits scenario beschikbaar is',
    () async {
      controller.dispose();
      controller = OpenKatWizardController(
        gateway: gateway,
        initialRecipe: OpenKatWizardRecipe(
          scenarioId: OpenKatWizardScenarioId.cveExposure,
          currentAsOf: DateTime.utc(2025),
          cveId: 'CVE-2026-12345',
          language: OpenKatReportLanguage.english,
          title: 'Bewaarde titel',
        ),
      );
      await controller.prepare('/reports');

      expect(
        controller.selectedScenarioId,
        OpenKatWizardScenarioId.cveExposure,
      );
      expect(controller.language, OpenKatReportLanguage.english);
      expect(controller.reportTitle, 'Bewaarde titel');
      expect(controller.cveId, 'CVE-2026-12345');
      expect(
        controller.currentAsOf,
        DateTime.utc(2026, 7, 1),
        reason: 'oude peildata mogen niet buiten de actuele scan vallen',
      );
    },
  );

  test('oude organisatiecode valt terug op een actuele optie', () async {
    controller.dispose();
    controller = OpenKatWizardController(
      gateway: gateway,
      initialRecipe: OpenKatWizardRecipe(
        scenarioId: OpenKatWizardScenarioId.organizationProgress,
        organizationCode: 'verdwenen-org',
        currentAsOf: DateTime.utc(2025),
      ),
    );

    await controller.prepare('/reports');

    expect(controller.selectedOrganizationCode, 'org-a');
    expect(controller.canContinue, isTrue);
  });

  test('nieuwe scan wist de oude scan al tijdens het wachten', () async {
    controller.dispose();
    final rescanGateway = _RescanGateway();
    controller = OpenKatWizardController(gateway: rescanGateway);
    await controller.prepare('/reports');
    expect(controller.scan, isNotNull);

    final pending = controller.prepare('/other-reports');

    expect(controller.scanStatus, OpenKatWizardScanStatus.scanning);
    expect(controller.scan, isNull);
    rescanGateway.rescan.complete(rescanGateway.prepared);
    await pending;
  });

  test('mislukte herscan toont nooit feiten uit de vorige map', () async {
    await controller.prepare('/reports');
    gateway.prepareError = StateError('kapotte tweede map');

    await controller.prepare('/other-reports');

    expect(controller.scanStatus, OpenKatWizardScanStatus.failed);
    expect(controller.scan, isNull);
    expect(controller.selectedPreviewFacts, isNull);
  });

  test('bestaand deck herstelt scenario, taal, titel en organisatie', () async {
    controller.dispose();
    controller = OpenKatWizardController(
      gateway: gateway,
      existingDeck: const Deck(
        title: 'Bestaande titel',
        language: 'en',
        slides: [
          Slide(
            id: 'generated',
            type: SlideType.title,
            notes:
                '<!-- ocideck_openkat_view: report.weekly-comparison.org.org-a.title -->',
          ),
        ],
      ),
    );
    await controller.prepare('/reports');

    expect(
      controller.selectedScenarioId,
      OpenKatWizardScenarioId.organizationProgress,
    );
    expect(controller.selectedOrganizationCode, 'org-a');
    expect(controller.language, OpenKatReportLanguage.english);
    expect(controller.reportTitle, 'Bestaande titel');
    expect(controller.updateConfirmationVisible, isTrue);
  });

  test(
    'legacy portfolio zonder opgeslagen scope slaat snelle update over',
    () async {
      controller.dispose();
      controller = OpenKatWizardController(
        gateway: gateway,
        existingDeck: const Deck(
          title: 'Legacy portfolio',
          slides: [
            Slide(
              id: 'generated',
              type: SlideType.title,
              notes:
                  '<!-- ocideck_openkat_view: report.management-overview.title -->',
            ),
          ],
        ),
      );

      await controller.prepare('/reports');

      expect(controller.selectedScenarioId, OpenKatWizardScenarioId.portfolio);
      expect(controller.updateConfirmationVisible, isFalse);
    },
  );

  test('scan- en bouwfouten laten keuzes staan voor herstel', () async {
    gateway.prepareError = StateError('kapotte map');
    await controller.prepare('/reports');
    expect(controller.scanStatus, OpenKatWizardScanStatus.failed);
    expect(controller.scanError, isA<StateError>());

    gateway.prepareError = null;
    await controller.prepare('/reports');
    controller.chooseScenario(OpenKatWizardScenarioId.dataQuality);
    controller.next();
    gateway.buildError = StateError('generator kapot');

    expect(await controller.build(), isNull);
    expect(controller.buildStatus, OpenKatWizardBuildStatus.failed);
    expect(controller.buildError, isA<StateError>());
    expect(controller.selectedScenarioId, OpenKatWizardScenarioId.dataQuality);
    expect(controller.step, OpenKatWizardStep.review);
  });

  test('afgevangen scan- en bouwfouten worden met stacktrace gelogd', () async {
    controller.dispose();
    final operations = <String>[];
    final stacks = <StackTrace>[];
    gateway.prepareError = StateError('kapotte map');
    controller = OpenKatWizardController(
      gateway: gateway,
      logFailure: (operation, error, stack) {
        operations.add(operation);
        stacks.add(stack);
      },
    );
    await controller.prepare('/reports');
    gateway.prepareError = null;
    await controller.prepare('/reports');
    gateway.buildError = StateError('generator kapot');
    await controller.build();

    expect(operations, [
      'OpenKatWizardController.prepare: scan reports',
      'OpenKatWizardController.build: generate report',
    ]);
    expect(stacks, everyElement(isA<StackTrace>()));
  });

  test('bouwen is alleen mogelijk na een geslaagde scan', () async {
    expect(await controller.build(), isNull);
    expect(gateway.buildCalls, 0);

    gateway.prepareError = StateError('kapot');
    await controller.prepare('/reports');
    expect(await controller.build(), isNull);
    expect(gateway.buildCalls, 0);
  });

  test(
    'datakwaliteit gebruikt kloktijd en expliciete actualiteitsgrens',
    () async {
      controller.dispose();
      final now = DateTime.utc(2026, 7, 29, 12);
      controller = OpenKatWizardController(gateway: gateway, now: () => now);
      await controller.prepare('/reports');

      controller.chooseScenario(OpenKatWizardScenarioId.dataQuality);

      final request = controller.recipe!.toRequest();
      expect(request.currentAsOf, now);
      expect(request.policy.maximumSnapshotAge, const Duration(days: 30));
    },
  );

  test('titeltypen bouwt de zware preview niet opnieuw', () async {
    await controller.prepare('/reports');
    expect(controller.reportPreview, isNotNull);
    expect(gateway.previewCalls, 1);

    controller.setTitle('E');
    expect(controller.reportPreview, isNotNull);
    controller.setTitle('Een nieuwe titel');
    expect(controller.reportPreview, isNotNull);

    expect(gateway.previewCalls, 1);
  });

  test('previewfeiten volgen de gekozen organisaties', () async {
    await controller.prepare('/reports');

    controller.toggleOrganization('org-a');

    final facts = controller.selectedPreviewFacts!;
    expect(facts.organizationCount, 1);
    expect(facts.reportCount, 1);
    expect(facts.criticalHighCount, 0);
    expect(facts.systemCount, 1);
    expect(facts.findingsByOrganization, {'Tweede organisatie': 0});
  });

  test('niet-gegenereerd rapport wordt als bouwfout behandeld', () async {
    gateway.report = const OpenKatReportResult(
      deck: null,
      plan: null,
      scenarioId: 'data-quality',
      scope: OpenKatReportScope.portfolio(),
      measurements: [],
      diagnostics: [],
      missingCapabilities: {},
      sourceTraces: [],
    );
    await controller.prepare('/reports');
    controller.chooseScenario(OpenKatWizardScenarioId.dataQuality);

    final result = await controller.build();

    expect(result, isNull);
    expect(controller.buildError, isA<OpenKatWizardBuildException>());
  });

  test('dubbel genereren start de gateway maar één keer', () async {
    await controller.prepare('/reports');
    final first = controller.build();
    final second = controller.build();

    expect(await second, isNull);
    expect(await first, isNotNull);
    expect(gateway.buildCalls, 1);
    expect(controller.buildStatus, OpenKatWizardBuildStatus.succeeded);
  });

  test(
    'als nieuw en bijwerken geven bewust een ander existing-contract',
    () async {
      controller.dispose();
      const existing = Deck(title: 'Bestaand');
      controller = OpenKatWizardController(
        gateway: gateway,
        existingDeck: existing,
      );
      await controller.prepare('/reports');

      await controller.build(asNew: true);
      expect(gateway.lastExisting, isNull);

      await controller.build();
      expect(gateway.lastExisting, same(existing));
    },
  );
}
