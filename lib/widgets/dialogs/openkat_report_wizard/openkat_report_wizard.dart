import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/openkat/openkat_wizard_models.dart';
import '../../../state/openkat_wizard_controller.dart';
import '../../../theme/app_theme.dart';
import 'openkat_wizard_preview.dart';
import 'openkat_wizard_steps.dart';

class OpenKatReportWizard extends StatefulWidget {
  final OpenKatWizardController controller;
  final String? initialDirectory;
  final Future<String?> Function() chooseDirectory;
  final ValueChanged<String> onDirectorySelected;

  const OpenKatReportWizard({
    super.key,
    required this.controller,
    required this.chooseDirectory,
    required this.onDirectorySelected,
    this.initialDirectory,
  });

  static Future<OpenKatWizardBuildResult?> show(
    BuildContext context, {
    required OpenKatWizardController controller,
    required Future<String?> Function() chooseDirectory,
    required ValueChanged<String> onDirectorySelected,
    String? initialDirectory,
  }) => showDialog<OpenKatWizardBuildResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OpenKatReportWizard(
      controller: controller,
      initialDirectory: initialDirectory,
      chooseDirectory: chooseDirectory,
      onDirectorySelected: onDirectorySelected,
    ),
  );

  @override
  State<OpenKatReportWizard> createState() => _OpenKatReportWizardState();
}

class _OpenKatReportWizardState extends State<OpenKatReportWizard> {
  late final TextEditingController _cveController;
  late final TextEditingController _titleController;
  String? _directory;

  OpenKatWizardController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _directory = widget.initialDirectory;
    _cveController = TextEditingController(text: controller.cveId);
    _titleController = TextEditingController(text: controller.reportTitle);
    controller.addListener(_changed);
    if (_directory != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.prepare(_directory!),
      );
    }
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    _cveController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final cve = controller.cveId ?? '';
    if (_cveController.text != cve) {
      _cveController.value = TextEditingValue(
        text: cve,
        selection: TextSelection.collapsed(offset: cve.length),
      );
    }
    if (_titleController.text != controller.reportTitle) {
      _titleController.value = TextEditingValue(
        text: controller.reportTitle,
        selection: TextSelection.collapsed(
          offset: controller.reportTitle.length,
        ),
      );
    }
    setState(() {});
  }

  Future<void> _chooseDirectory() async {
    final selected = await widget.chooseDirectory();
    if (selected == null || !mounted) return;
    _directory = selected;
    widget.onDirectorySelected(selected);
    await controller.prepare(selected);
  }

  Future<void> _inspectAgain() async {
    final directory = _directory;
    if (directory != null) await controller.prepare(directory);
  }

  Future<void> _build({bool asNew = false}) async {
    final result = await controller.build(asNew: asNew);
    if (result == null || !mounted) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final ready = controller.scanStatus == OpenKatWizardScanStatus.ready;
    final l10n = context.l10n;
    return PopScope(
      canPop: !controller.busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        backgroundColor: AppTheme.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppTheme.slate300),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1220, maxHeight: 860),
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width - 40,
            height: MediaQuery.sizeOf(context).height - 40,
            child: Column(
              children: [
                _Header(controller: controller),
                Expanded(
                  child: !ready
                      ? OpenKatSourceGate(
                          controller: controller,
                          directory: _directory,
                          chooseDirectory: _chooseDirectory,
                          inspectAgain: _inspectAgain,
                        )
                      : controller.updateConfirmationVisible
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: OpenKatUpdateConfirmation(
                            controller: controller,
                            update: _build,
                          ),
                        )
                      : _WizardBody(
                          controller: controller,
                          cveController: _cveController,
                          titleController: _titleController,
                        ),
                ),
                if (!ready || !controller.updateConfirmationVisible)
                  _Footer(
                    controller: controller,
                    sourceReady: ready,
                    onBuild: _build,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => Navigator.pop(context),
                        child: Text(l10n.d('Annuleren')),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final OpenKatWizardController controller;

  const _Header({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = controller.scanStatus == OpenKatWizardScanStatus.ready;
    final number = switch (controller.step) {
      OpenKatWizardStep.scenario => 1,
      OpenKatWizardStep.inputs => 2,
      OpenKatWizardStep.review => 3,
    };
    final title = Row(
      children: [
        Image.asset(
          'assets/images/openkat-logo.png',
          width: 52,
          height: 52,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.updating
                    ? l10n.d('OpenKAT-rapport bijwerken')
                    : l10n.d('OpenKAT-rapport maken'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                ready
                    ? '${l10n.d('Stap')} $number ${l10n.d('van')} 3'
                    : l10n.d('Rapportages voorbereiden'),
                style: TextStyle(
                  color: AppTheme.accentFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final enlarged = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: enlarged ? 16 : 24,
        vertical: enlarged ? 10 : 18,
      ),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: Border(bottom: BorderSide(color: AppTheme.slate300)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 760 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 12),
                const _PrivacyPill(),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 18),
              const _PrivacyPill(),
            ],
          );
        },
      ),
    );
  }
}

class _PrivacyPill extends StatelessWidget {
  const _PrivacyPill();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 44),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: AppTheme.successBg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppTheme.successFg),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 18, color: AppTheme.successFg),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            context.l10n.d('Alles blijft op dit apparaat'),
            style: TextStyle(
              color: AppTheme.successFg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _WizardBody extends StatefulWidget {
  final OpenKatWizardController controller;
  final TextEditingController cveController;
  final TextEditingController titleController;

  const _WizardBody({
    required this.controller,
    required this.cveController,
    required this.titleController,
  });

  @override
  State<_WizardBody> createState() => _WizardBodyState();
}

class _WizardBodyState extends State<_WizardBody> {
  final ScrollController _choicesScrollController = ScrollController(
    keepScrollOffset: false,
  );

  @override
  void dispose() {
    _choicesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final stepContent = switch (widget.controller.step) {
        OpenKatWizardStep.scenario => OpenKatScenarioStep(
          key: const ValueKey('openkat-step-scenario'),
          controller: widget.controller,
        ),
        OpenKatWizardStep.inputs => OpenKatInputsStep(
          key: const ValueKey('openkat-step-inputs'),
          controller: widget.controller,
          cveController: widget.cveController,
          titleController: widget.titleController,
        ),
        OpenKatWizardStep.review => OpenKatReviewStep(
          key: const ValueKey('openkat-step-review'),
          controller: widget.controller,
        ),
      };
      final choices = SingleChildScrollView(
        key: const ValueKey('openkat-wizard-choices'),
        controller: _choicesScrollController,
        primary: false,
        padding: const EdgeInsets.all(24),
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? const Duration(milliseconds: 1)
              : const Duration(milliseconds: 240),
          child: stepContent,
        ),
      );
      final preview = Padding(
        padding: const EdgeInsets.all(24),
        child: OpenKatWizardPreview(controller: widget.controller),
      );
      if (wide) {
        return Row(
          children: [
            Expanded(flex: 58, child: choices),
            VerticalDivider(width: 1, color: AppTheme.slate300),
            Expanded(
              flex: 42,
              child: ColoredBox(color: AppTheme.slate50, child: preview),
            ),
          ],
        );
      }
      return SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: constraints.maxHeight * 0.72, child: choices),
            Divider(height: 1, color: AppTheme.slate300),
            SizedBox(height: 520, child: preview),
          ],
        ),
      );
    },
  );
}

class _Footer extends StatelessWidget {
  final OpenKatWizardController controller;
  final bool sourceReady;
  final Future<void> Function({bool asNew}) onBuild;

  const _Footer({
    required this.controller,
    required this.sourceReady,
    required this.onBuild,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scan = controller.scan;
    final review = controller.step == OpenKatWizardStep.review;
    final enlarged = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: enlarged ? 16 : 24,
        vertical: enlarged ? 7 : 14,
      ),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: Border(top: BorderSide(color: AppTheme.slate300)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final status = sourceReady && scan != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      size: 20,
                      color: AppTheme.slate600,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${scan.preview.reportCount} ${l10n.d('bruikbaar')} · '
                        '${scan.preview.skippedCount} ${l10n.d('overgeslagen')}',
                        style: TextStyle(color: AppTheme.slate600),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink();
          final actions = Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: controller.busy
                    ? null
                    : () {
                        if (sourceReady &&
                            controller.step != OpenKatWizardStep.scenario) {
                          controller.back();
                        } else {
                          Navigator.pop(context);
                        }
                      },
                child: Text(
                  sourceReady && controller.step != OpenKatWizardStep.scenario
                      ? controller.buildError != null
                            ? l10n.d('Keuzes wijzigen…')
                            : l10n.d('Terug')
                      : l10n.d('Annuleren'),
                ),
              ),
              if (sourceReady && review && controller.updating)
                OutlinedButton(
                  onPressed: controller.busy
                      ? null
                      : () => onBuild(asNew: true),
                  child: Text(l10n.d('Als nieuw rapport maken')),
                ),
              if (sourceReady)
                FilledButton.icon(
                  key: const ValueKey('openkat-primary-action'),
                  onPressed: controller.busy || !controller.canContinue
                      ? null
                      : review
                      ? () => onBuild(asNew: false)
                      : controller.next,
                  icon:
                      controller.buildStatus ==
                          OpenKatWizardBuildStatus.building
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(review ? Icons.auto_awesome : Icons.arrow_forward),
                  label: Text(
                    review
                        ? controller.buildError != null
                              ? l10n.d('Opnieuw proberen')
                              : controller.updating
                              ? l10n.d('Rapport bijwerken')
                              : l10n.d('Rapport maken')
                        : l10n.d('Doorgaan'),
                  ),
                ),
            ],
          );
          final stacked =
              constraints.maxWidth < 720 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                if (sourceReady) const SizedBox(height: 8),
                actions,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}
