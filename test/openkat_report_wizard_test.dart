import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/openkat/openkat_wizard_models.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_deck_generator.dart';
import 'package:ocideck/services/openkat/openkat_wizard_service.dart';
import 'package:ocideck/state/openkat_wizard_controller.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_report_wizard.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_scenario_card.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_wizard_preview.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_wizard_steps.dart';

import 'openkat_wizard_test_fakes.dart';

Future<void> _pumpFrames(
  WidgetTester tester, {
  int count = 4,
  Duration frame = const Duration(milliseconds: 50),
}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(frame);
  }
}

Widget _app(
  Widget child, {
  Size size = const Size(1280, 900),
  double textScale = 1,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: child),
  ),
);

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _DelayedGateway extends FakeOpenKatWizardGateway {
  final Completer<OpenKatWizardScan> completer = Completer();

  @override
  Future<OpenKatWizardScan> prepare(String directory) {
    prepareCalls++;
    return completer.future;
  }
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));
  tearDown(() => AppTheme.isDark = false);

  group('scenariokaart', () {
    testWidgets('volgt alle kleurrollen van een afwijkend app-profiel', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      const profile = AppAppearanceProfile(
        name: 'Regressieprofiel',
        primaryColor: '#6B2145',
        accentColor: '#C47A00',
        backgroundColor: '#EAF2ED',
        surfaceColor: '#CFE8DD',
        textColor: '#182B23',
        mutedTextColor: '#405D50',
        panelColor: '#203A2F',
        panelTextColor: '#F4FFF9',
      );
      final theme = AppTheme.fromProfile(profile);
      final scan = wizardScan();
      final available = scan.scenarios.first;
      final unavailableDescriptor = OpenKatWizardService.scenarioDescriptors
          .firstWhere((item) => item.id == OpenKatWizardScenarioId.dataQuality);

      await tester.pumpWidget(
        _app(
          Column(
            children: [
              SizedBox(
                width: 340,
                child: OpenKatScenarioCard(
                  scenario: available,
                  facts: scan.preview,
                  title: 'Managementoverzicht',
                  description: 'Vergelijk alle organisaties.',
                  recommendedLabel: 'Aanbevolen',
                  selectedLabel: 'Geselecteerd',
                  selected: false,
                  onSelected: (_) {},
                ),
              ),
              SizedBox(
                width: 340,
                child: OpenKatScenarioCard(
                  scenario: OpenKatWizardScenarioAvailability(
                    descriptor: unavailableDescriptor,
                    available: false,
                    reason: OpenKatWizardUnavailableReason.noUsableMeasurements,
                  ),
                  facts: scan.preview,
                  title: 'Datakwaliteit',
                  description: 'Beoordeel de beschikbare metingen.',
                  recommendedLabel: 'Aanbevolen',
                  selectedLabel: 'Geselecteerd',
                  unavailableReason: 'Geen bruikbare metingen',
                  selected: false,
                  onSelected: (_) {},
                ),
              ),
            ],
          ),
          theme: theme,
        ),
      );

      final availableCard = find.byKey(
        const ValueKey('openkat-scenario-portfolio'),
      );
      final decoration =
          tester.widget<AnimatedContainer>(availableCard).decoration!
              as BoxDecoration;
      final border = decoration.border! as Border;
      expect(decoration.color, theme.colorScheme.surface);
      expect(border.top.color, theme.colorScheme.outlineVariant);
      expect(
        tester.widget<Text>(find.text('Managementoverzicht')).style?.color,
        theme.colorScheme.onSurface,
      );
      expect(
        tester
            .widget<Text>(find.text('Vergelijk alle organisaties.'))
            .style
            ?.color,
        theme.colorScheme.onSurfaceVariant,
      );

      final badge = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Aanbevolen'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (badge.decoration! as BoxDecoration).color,
        theme.colorScheme.primary,
      );

      final heatCells = tester
          .widgetList<Container>(
            find.descendant(
              of: availableCard,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).borderRadius ==
                        BorderRadius.circular(3),
              ),
            ),
          )
          .toList();
      expect(heatCells, isNotEmpty);
      final heatColor = (heatCells.first.decoration! as BoxDecoration).color!;
      expect(
        heatColor.withValues(alpha: 1).toARGB32(),
        theme.colorScheme.primary.toARGB32(),
      );
      expect(heatColor.a, closeTo(0.9, 0.01));

      final unavailableCard = find.byKey(
        const ValueKey('openkat-scenario-dataQuality'),
      );
      final statusDots = tester
          .widgetList<Container>(
            find.descendant(
              of: unavailableCard,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).shape ==
                        BoxShape.circle,
              ),
            ),
          )
          .toList();
      expect(statusDots, isNotEmpty);
      final statusColor =
          (statusDots.first.decoration! as BoxDecoration).color!;
      expect(
        statusColor.withValues(alpha: 1).toARGB32(),
        theme.colorScheme.outline.toARGB32(),
      );
      expect(statusColor.a, closeTo(0.28, 0.01));
    });

    testWidgets('geselecteerde kaart heeft naam, rol en aangevinkte toestand', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final semantics = tester.ensureSemantics();
      final scenario = wizardScan().scenarios.first;

      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 340,
              child: OpenKatScenarioCard(
                scenario: scenario,
                facts: wizardScan().preview,
                title: 'Managementoverzicht',
                description: 'Vergelijk alle organisaties.',
                recommendedLabel: 'Aanbevolen',
                selectedLabel: 'Geselecteerd',
                selected: true,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(
        find.bySemanticsLabel(
          RegExp(
            'Managementoverzicht.*Vergelijk alle organisaties.*Geselecteerd',
          ),
        ),
      );
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isChecked, ui.CheckedState.isTrue);
      expect(node.flagsCollection.isEnabled, ui.Tristate.isTrue);
      expect(node.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      semantics.dispose();
    });

    testWidgets('toetsenbord activeert een beschikbare kaart en toont focus', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      OpenKatWizardScenarioId? selected;
      final scenario = wizardScan().scenarios.first;
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 340,
              child: OpenKatScenarioCard(
                scenario: scenario,
                facts: wizardScan().preview,
                title: 'Managementoverzicht',
                description: 'Vergelijk alle organisaties.',
                recommendedLabel: 'Aanbevolen',
                selectedLabel: 'Geselecteerd',
                selected: false,
                onSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 50));
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, OpenKatWizardScenarioId.portfolio);
    });

    testWidgets('onbeschikbare kaart legt reden uit en reageert nergens op', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      var selections = 0;
      final descriptor = OpenKatWizardService.scenarioDescriptors.firstWhere(
        (item) => item.id == OpenKatWizardScenarioId.cveExposure,
      );
      final scenario = OpenKatWizardScenarioAvailability(
        descriptor: descriptor,
        available: false,
        reason: OpenKatWizardUnavailableReason.noReliableCveReferences,
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 340,
              child: OpenKatScenarioCard(
                scenario: scenario,
                facts: wizardScan().preview,
                title: 'CVE-blootstelling',
                description: 'Laat kwetsbare systemen zien.',
                recommendedLabel: 'Aanbevolen',
                selectedLabel: 'Geselecteerd',
                unavailableReason: 'Geen betrouwbare CVE-verwijzingen',
                selected: false,
                onSelected: (_) => selections++,
              ),
            ),
          ),
        ),
      );

      final card = find.byKey(const ValueKey('openkat-scenario-cveExposure'));
      await tester.tap(card);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selections, 0);
      final node = tester.getSemantics(
        find.bySemanticsLabel(
          RegExp('CVE-blootstelling.*Geen betrouwbare CVE-verwijzingen'),
        ),
      );
      expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
      semantics.dispose();
    });

    testWidgets('lang label past bij 200% tekst in licht en donker', (
      tester,
    ) async {
      _useViewport(tester, const Size(360, 1400));
      final scenario = wizardScan().scenarios.first;
      for (final dark in [false, true]) {
        AppTheme.isDark = dark;
        await tester.pumpWidget(
          _app(
            Center(
              child: SizedBox(
                width: 320,
                child: OpenKatScenarioCard(
                  scenario: scenario,
                  facts: wizardScan().preview,
                  title:
                      'Managementoverzicht voor alle geselecteerde organisaties',
                  description:
                      'Een uitzonderlijk lange uitleg die ook bij sterke '
                      'tekstvergroting volledig leesbaar moet blijven.',
                  recommendedLabel: 'Sterk aanbevolen',
                  selectedLabel: 'Geselecteerd',
                  selected: true,
                  onSelected: (_) {},
                ),
              ),
            ),
            size: const Size(360, 900),
            textScale: 2,
            theme: dark ? ThemeData.dark() : ThemeData.light(),
          ),
        );
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull, reason: 'dark=$dark');
        expect(
          find.text('Managementoverzicht voor alle geselecteerde organisaties'),
          findsOneWidget,
        );
      }
    });
  });

  group('bronpoort en wizardroute', () {
    testWidgets('ieder geregistreerd invoertype heeft een renderpad', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final rendered = <OpenKatWizardInputKind>{};

      for (final descriptor in OpenKatWizardService.scenarioDescriptors) {
        final controller = OpenKatWizardController(
          gateway: FakeOpenKatWizardGateway(),
        );
        addTearDown(controller.dispose);
        await controller.prepare('/reports');
        controller.chooseScenario(descriptor.id);
        final cve = TextEditingController(text: controller.cveId);
        final title = TextEditingController(text: controller.reportTitle);
        addTearDown(cve.dispose);
        addTearDown(title.dispose);

        await tester.pumpWidget(
          _app(
            SingleChildScrollView(
              child: OpenKatInputsStep(
                controller: controller,
                cveController: cve,
                titleController: title,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: descriptor.id.name);

        for (final input in descriptor.inputs) {
          final finder = switch (input) {
            OpenKatWizardInputKind.organization => find.text('Organisatie'),
            OpenKatWizardInputKind.period => find.textContaining(
              'Laatste bruikbare meting',
            ),
            OpenKatWizardInputKind.cve => find.byKey(
              const ValueKey('openkat-cve-search'),
            ),
            OpenKatWizardInputKind.language ||
            OpenKatWizardInputKind.title ||
            OpenKatWizardInputKind.organizations => find.byKey(
              const ValueKey('openkat-more-settings'),
            ),
          };
          expect(finder, findsWidgets, reason: '${descriptor.id.name}: $input');
          rendered.add(input);
        }
      }

      expect(rendered, OpenKatWizardInputKind.values.toSet());
    });

    testWidgets('scannen blokkeert knoppen en toont begrensde voortgang', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final gateway = _DelayedGateway();
      final controller = OpenKatWizardController(gateway: gateway);
      await tester.pumpWidget(
        _app(
          OpenKatReportWizard(
            controller: controller,
            initialDirectory: '/reports',
            chooseDirectory: () async => null,
            onDirectorySelected: (_) {},
          ),
        ),
      );
      await _pumpFrames(tester, count: 2);

      expect(controller.scanStatus, OpenKatWizardScanStatus.scanning);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final inspect = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Rapportages controleren…'),
      );
      expect(inspect.onPressed, isNull);

      gateway.completer.complete(gateway.prepared);
      await _pumpFrames(tester);
      expect(controller.scanStatus, OpenKatWizardScanStatus.ready);
    });

    testWidgets('lege scan blijft op bronpoort zonder scenario’s', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final controller = OpenKatWizardController(
        gateway: FakeOpenKatWizardGateway(prepared: wizardScan(reportCount: 0)),
      );
      await tester.pumpWidget(
        _app(
          OpenKatReportWizard(
            controller: controller,
            initialDirectory: '/empty',
            chooseDirectory: () async => null,
            onDirectorySelected: (_) {},
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(controller.scanStatus, OpenKatWizardScanStatus.empty);
      expect(
        find.text('Deze map bevat geen bruikbare rapportages'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('openkat-scenario-portfolio')),
        findsNothing,
      );
    });

    testWidgets('scanfout biedt andere map aan en bewaart bronpad', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final controller = OpenKatWizardController(
        gateway: FakeOpenKatWizardGateway(
          prepareError: StateError('onleesbaar'),
        ),
      );
      await tester.pumpWidget(
        _app(
          OpenKatReportWizard(
            controller: controller,
            initialDirectory: '/kapot',
            chooseDirectory: () async => null,
            onDirectorySelected: (_) {},
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Kon dit bestand niet openen.'), findsOneWidget);
      expect(find.text('Andere map kiezen'), findsOneWidget);
      expect(find.text('/kapot'), findsOneWidget);
    });

    testWidgets('nieuw rapport toont alle geregistreerde scenario’s', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final controller = OpenKatWizardController(
        gateway: FakeOpenKatWizardGateway(),
      );
      await tester.pumpWidget(
        _app(
          OpenKatReportWizard(
            controller: controller,
            initialDirectory: '/reports',
            chooseDirectory: () async => null,
            onDirectorySelected: (_) {},
          ),
        ),
      );
      await _pumpFrames(tester);

      for (final id in OpenKatWizardScenarioId.values) {
        expect(
          find.byKey(ValueKey('openkat-scenario-${id.name}')),
          findsOneWidget,
          reason: '${id.name} moet vanuit het register renderen',
        );
      }
      expect(find.text('OpenKAT-rapport maken'), findsOneWidget);
      final choices = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('openkat-wizard-choices')),
      );
      expect(choices.controller, isNotNull);
      expect(choices.controller!.position.pixels, 0);
      expect(
        tester.getTopLeft(find.text('Wat wilt u laten zien?')).dy,
        greaterThan(tester.getBottomLeft(find.text('Stap 1 van 3')).dy),
      );
    });

    testWidgets('bijwerken vraagt eerst bevestiging en biedt keuzes wijzigen', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final controller = OpenKatWizardController(
        gateway: FakeOpenKatWizardGateway(),
        existingDeck: const Deck(
          title: 'Bestaand',
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
      await tester.pumpWidget(
        _app(
          OpenKatReportWizard(
            controller: controller,
            initialDirectory: '/reports',
            chooseDirectory: () async => null,
            onDirectorySelected: (_) {},
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(
        find.textContaining('Uw eigen dia’s en kopieën blijven behouden'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keuzes wijzigen…'));
      await _pumpFrames(tester, count: 2);
      expect(
        find.byKey(const ValueKey('openkat-scenario-portfolio')),
        findsOneWidget,
      );
    });

    testWidgets('mislukte snelle update toont de bouwfout in de bevestiging', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final gateway = FakeOpenKatWizardGateway(
        buildError: StateError('generator kapot'),
      );
      final controller = OpenKatWizardController(
        gateway: gateway,
        existingDeck: const Deck(
          title: 'Bestaand',
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
      await tester.pumpWidget(
        _app(
          OpenKatReportWizard(
            controller: controller,
            initialDirectory: '/reports',
            chooseDirectory: () async => null,
            onDirectorySelected: (_) {},
          ),
        ),
      );
      await _pumpFrames(tester);

      await tester.tap(find.text('Rapport bijwerken'));
      await _pumpFrames(tester);

      expect(
        find.textContaining('Het rapport kon niet worden gemaakt'),
        findsOneWidget,
      );
      expect(find.text('Opnieuw proberen'), findsOneWidget);
      expect(find.text('Keuzes wijzigen…'), findsOneWidget);
      expect(find.text('Bekijk importverslag'), findsOneWidget);
    });

    testWidgets('onveilige update biedt een nieuw rapport als veilige uitweg', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final gateway = FakeOpenKatWizardGateway(
        buildError: const OpenKatUnsafeUpdateException('legacy.view'),
      );
      final controller = OpenKatWizardController(
        gateway: gateway,
        existingDeck: const Deck(
          title: 'Legacy',
          slides: [
            Slide(
              id: 'legacy',
              type: SlideType.title,
              notes: '<!-- ocideck_openkat_view: legacy.view -->',
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        _app(
          OpenKatReportWizard(
            controller: controller,
            initialDirectory: '/reports',
            chooseDirectory: () async => null,
            onDirectorySelected: (_) {},
          ),
        ),
      );
      await _pumpFrames(tester);

      await tester.tap(find.text('Rapport bijwerken'));
      await _pumpFrames(tester);

      expect(
        find.textContaining('kan niet veilig worden bijgewerkt'),
        findsOneWidget,
      );
      expect(find.text('Als nieuw rapport maken'), findsOneWidget);

      gateway.buildError = null;
      await tester.tap(find.text('Als nieuw rapport maken'));
      await _pumpFrames(tester);

      expect(gateway.lastExisting, isNull);
    });

    testWidgets('reviewwaarschuwingen noemen organisatie en ouderdom', (
      tester,
    ) async {
      _useViewport(tester, const Size(1280, 900));
      final gateway = FakeOpenKatWizardGateway(
        report: wizardReport(
          diagnostics: const [
            OpenKatReportDiagnostic(
              code: OpenKatReportDiagnosticCode.incompletePortfolio,
              severity: OpenKatReportDiagnosticSeverity.warning,
              arguments: {'missingOrganizations': 'org-b'},
            ),
            OpenKatReportDiagnostic(
              code: OpenKatReportDiagnosticCode.snapshotTooOld,
              severity: OpenKatReportDiagnosticSeverity.warning,
              arguments: {
                'organizationCode': 'org-a',
                'ageDays': '131',
                'maximumAgeDays': '30',
              },
            ),
          ],
        ),
      );
      final controller = OpenKatWizardController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.prepare('/reports');
      controller.chooseScenario(OpenKatWizardScenarioId.dataQuality);
      controller.next();

      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: OpenKatReviewStep(controller: controller),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.textContaining('Organisaties: org-b'), findsOneWidget);
      expect(
        find.textContaining('org-a: 131 dagen > 30 dagen'),
        findsOneWidget,
      );
    });

    testWidgets('live preview toont alleen gekozen portfolio-organisaties', (
      tester,
    ) async {
      _useViewport(tester, const Size(680, 900));
      final controller = OpenKatWizardController(
        gateway: FakeOpenKatWizardGateway(),
      );
      addTearDown(controller.dispose);
      await controller.prepare('/reports');
      controller.toggleOrganization('org-a');

      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 520,
            height: 780,
            child: OpenKatWizardPreview(controller: controller),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Tweede organisatie'), findsOneWidget);
      expect(
        find.text('Een organisatie met een bijzonder lange naam'),
        findsNothing,
      );
      expect(find.text('1 organisaties · 1 rapportages'), findsOneWidget);
      expect(find.text('Kwetsbare systemen'), findsOneWidget);
      expect(find.text('Getroffen systemen'), findsNothing);
    });

    testWidgets('smalle wizard met 200% tekst blijft zonder renderfout', (
      tester,
    ) async {
      _useViewport(tester, const Size(420, 900));
      final controller = OpenKatWizardController(
        gateway: FakeOpenKatWizardGateway(
          prepared: wizardScan(
            organizationName:
                'Organisatie met een zeer lange officiële statutaire naam',
          ),
        ),
      );
      await tester.pumpWidget(
        _app(
          OpenKatReportWizard(
            controller: controller,
            initialDirectory: '/reports',
            chooseDirectory: () async => null,
            onDirectorySelected: (_) {},
          ),
          size: const Size(420, 900),
          textScale: 2,
        ),
      );
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('openkat-wizard-choices')),
        findsOneWidget,
      );
    });
  });
}
