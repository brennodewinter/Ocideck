import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/openkat_wizard_controller.dart';
import '../../../theme/app_theme.dart';
import 'openkat_wizard_strings.dart';

class OpenKatWizardPreview extends StatelessWidget {
  final OpenKatWizardController controller;

  const OpenKatWizardPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scan = controller.scan;
    if (scan == null) {
      return const _PreviewSkeleton();
    }
    final l10n = context.l10n;
    final report = controller.reportPreview;
    final facts = controller.selectedPreviewFacts ?? scan.preview;
    final plan = report?.plan;
    final scenario = controller.selectedScenarioId;
    return Semantics(
      container: true,
      label: l10n.d('Live voorvertoning van de rapportopbouw'),
      child: Stack(
        children: [
          Positioned.fill(
            top: 16,
            left: 18,
            right: 0,
            child: _Paper(shade: AppTheme.slate100),
          ),
          Positioned.fill(
            top: 8,
            left: 9,
            right: 9,
            child: _Paper(shade: AppTheme.slate50),
          ),
          Positioned.fill(
            bottom: 8,
            child: _Paper(
              shade: AppTheme.paper,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.reportTitle.trim().isNotEmpty
                          ? controller.reportTitle.trim()
                          : scenario == null
                          ? l10n.d('OpenKAT-rapport')
                          : openKatScenarioTitle(l10n, scenario),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Metric(
                          label: l10n.d('Organisaties'),
                          value: '${facts.organizationCount}',
                        ),
                        _Metric(
                          label: l10n.d('Critical/high'),
                          value: '${facts.criticalHighCount}',
                        ),
                        _Metric(
                          label: l10n.d('Getroffen systemen'),
                          value: '${facts.systemCount}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      l10n.d('Feitelijke gegevens'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final entry
                        in facts.findingsByOrganization.entries.take(6))
                      _FindingBar(
                        label: entry.key,
                        value: entry.value,
                        maximum: facts.findingsByOrganization.values.fold(
                          1,
                          (a, b) => a > b ? a : b,
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.d('Dit rapport bevat'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (plan == null)
                      Text(
                        l10n.d(
                          'De inhoud verschijnt zodra alle noodzakelijke keuzes zijn gemaakt.',
                        ),
                        style: TextStyle(color: AppTheme.slate600),
                      )
                    else
                      for (final block in plan.blocks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: AppTheme.successFg,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  openKatBlockTitle(l10n, block.kind),
                                  style: TextStyle(color: AppTheme.slate700),
                                ),
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 12),
                    Text(
                      '${facts.organizationCount} ${l10n.d('organisaties')} · '
                      '${facts.reportCount} ${l10n.d('rapportages')}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppTheme.slate600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  final Color shade;
  final Widget? child;

  const _Paper({required this.shade, this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: shade,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.slate300),
      boxShadow: [
        BoxShadow(
          color: AppTheme.slate800.withValues(alpha: 0.1),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 96),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.slate50,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AppTheme.slate300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppTheme.slate600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _FindingBar extends StatelessWidget {
  final String label;
  final int value;
  final int maximum;

  const _FindingBar({
    required this.label,
    required this.value,
    required this.maximum,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: value / maximum,
              backgroundColor: AppTheme.slate200,
              color: AppTheme.tealFg,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$value', style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) => _Paper(
    shade: AppTheme.paper,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 210, height: 24, color: AppTheme.slate200),
          const SizedBox(height: 24),
          for (var index = 0; index < 4; index++) ...[
            Container(
              height: 36,
              width: double.infinity,
              color: AppTheme.slate100,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    ),
  );
}
