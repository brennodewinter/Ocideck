import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/openkat/openkat_wizard_models.dart';
import '../../../state/openkat_wizard_controller.dart';
import 'openkat_wizard_strings.dart';

class OpenKatRecipePicker extends StatelessWidget {
  final OpenKatWizardController controller;
  final VoidCallback inspectImport;

  const OpenKatRecipePicker({
    super.key,
    required this.controller,
    required this.inspectImport,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scan = controller.scan!;
    final familyScenarios =
        scan.scenarios
            .where(
              (scenario) =>
                  scenario.descriptor.family == controller.selectedFamilyId,
            )
            .toList()
          ..sort((a, b) => a.descriptor.order.compareTo(b.descriptor.order));
    final recommended = familyScenarios
        .where((scenario) => scenario.descriptor.recommended)
        .toList();
    final more = familyScenarios
        .where((scenario) => !scenario.descriptor.recommended)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Wat wilt u laten zien?'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'Kies eerst het onderwerp en daarna de vraag die het rapport moet beantwoorden.',
          ),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _ScanSummary(scan: scan, inspectImport: inspectImport),
        const SizedBox(height: 20),
        Text(
          l10n.d('Onderwerp'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final family in OpenKatReportFamilyId.values)
              ChoiceChip(
                key: ValueKey('openkat-family-${family.name}'),
                selected: controller.selectedFamilyId == family,
                onSelected: (_) => controller.chooseFamily(family),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Text(openKatFamilyTitle(l10n, family)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          openKatFamilyDescription(l10n, controller.selectedFamilyId),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          l10n.d('Welk rapport beantwoordt uw vraag?'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final scenario in recommended) ...[
          _RecipeOption(
            controller: controller,
            scenario: scenario,
            inspectImport: inspectImport,
          ),
          const SizedBox(height: 8),
        ],
        if (more.isNotEmpty)
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              key: const ValueKey('openkat-more-recipes'),
              initiallyExpanded: controller.moreRecipesExpanded,
              onExpansionChanged: (_) => controller.toggleMoreRecipes(),
              tilePadding: EdgeInsets.zero,
              title: Text(l10n.d('Meer rapportvragen')),
              children: [
                for (final scenario in more) ...[
                  _RecipeOption(
                    controller: controller,
                    scenario: scenario,
                    inspectImport: inspectImport,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ScanSummary extends StatelessWidget {
  final OpenKatWizardScan scan;
  final VoidCallback inspectImport;

  const _ScanSummary({required this.scan, required this.inspectImport});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dates = MaterialLocalizations.of(context);
    final summary = l10n
        .d(
          '{reports} rapportages gevonden voor {organizations} organisaties. De metingen lopen van {firstDate} tot en met {lastDate}. {skipped} bestanden zijn overgeslagen.',
        )
        .replaceAll('{reports}', '${scan.preview.reportCount}')
        .replaceAll('{organizations}', '${scan.preview.organizationCount}')
        .replaceAll(
          '{firstDate}',
          dates.formatMediumDate(scan.earliestMeasurement!),
        )
        .replaceAll(
          '{lastDate}',
          dates.formatMediumDate(scan.latestMeasurement!),
        )
        .replaceAll('{skipped}', '${scan.preview.skippedCount}');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fact_check_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: inspectImport,
                    child: Text(l10n.d('Bekijk importverslag')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeOption extends StatelessWidget {
  final OpenKatWizardController controller;
  final OpenKatWizardScenarioAvailability scenario;
  final VoidCallback inspectImport;

  const _RecipeOption({
    required this.controller,
    required this.scenario,
    required this.inspectImport,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final descriptor = scenario.descriptor;
    final selected = controller.selectedScenarioId == descriptor.id;
    final reason = scenario.reason == null
        ? null
        : openKatUnavailableReason(l10n, scenario.reason!);
    final colors = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: scenario.available,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          controller.chooseScenario(descriptor.id);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Card(
            key: ValueKey('openkat-recipe-${descriptor.id.name}'),
            margin: EdgeInsets.zero,
            color: selected
                ? colors.primaryContainer.withValues(alpha: 0.28)
                : colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: focused
                    ? colors.secondary
                    : selected
                    ? colors.primary
                    : colors.outlineVariant,
                width: focused ? 3 : (selected ? 2 : 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  container: true,
                  button: true,
                  selected: selected,
                  enabled: scenario.available,
                  inMutuallyExclusiveGroup: true,
                  label: [
                    openKatScenarioTitle(l10n, descriptor.id),
                    openKatScenarioDescription(l10n, descriptor.id),
                    ?reason,
                  ].join('. '),
                  child: ExcludeSemantics(
                    child: ExcludeFocus(
                      child: ListTile(
                        enabled: scenario.available,
                        onTap: scenario.available
                            ? () => controller.chooseScenario(descriptor.id)
                            : null,
                        leading: Icon(
                          _previewIcons[descriptor.previewKind],
                          color: scenario.available
                              ? colors.primary
                              : colors.outline,
                        ),
                        title: Text(
                          openKatScenarioTitle(l10n, descriptor.id),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            openKatScenarioDescription(l10n, descriptor.id),
                            ?reason,
                          ].join('\n'),
                        ),
                        trailing: selected
                            ? Icon(Icons.check_circle, color: colors.primary)
                            : scenario.available
                            ? const Icon(Icons.chevron_right)
                            : const Icon(Icons.lock_outline),
                      ),
                    ),
                  ),
                ),
                if (!scenario.available)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        0,
                        16,
                        8,
                      ),
                      child: TextButton.icon(
                        onPressed: inspectImport,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(l10n.d('Bekijk importverslag')),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

const Map<OpenKatWizardPreviewKind, IconData> _previewIcons = {
  OpenKatWizardPreviewKind.summary: Icons.dashboard_outlined,
  OpenKatWizardPreviewKind.comparison: Icons.compare_arrows,
  OpenKatWizardPreviewKind.trend: Icons.show_chart,
  OpenKatWizardPreviewKind.findings: Icons.fact_check_outlined,
  OpenKatWizardPreviewKind.systems: Icons.dns_outlined,
  OpenKatWizardPreviewKind.controls: Icons.rule_outlined,
  OpenKatWizardPreviewKind.cve: Icons.hub_outlined,
  OpenKatWizardPreviewKind.monitoring: Icons.monitor_heart_outlined,
  OpenKatWizardPreviewKind.accountability: Icons.receipt_long_outlined,
};
