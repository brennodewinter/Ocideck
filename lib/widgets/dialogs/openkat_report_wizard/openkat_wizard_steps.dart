import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/openkat/openkat_models.dart';
import '../../../models/openkat/openkat_reporting_models.dart';
import '../../../models/openkat/openkat_wizard_models.dart';
import '../../../state/openkat_wizard_controller.dart';
import '../../../theme/app_theme.dart';
import 'openkat_recipe_picker.dart';
import 'openkat_wizard_strings.dart';

typedef OpenKatWizardInputRenderer =
    Widget Function(
      OpenKatWizardController controller,
      TextEditingController cveController,
      TextEditingController titleController,
    );

final Map<OpenKatWizardInputKind, OpenKatWizardInputRenderer>
openKatWizardInputRenderers = {
  OpenKatWizardInputKind.organization: (controller, _, _) =>
      _OrganizationInputs(controller: controller),
  OpenKatWizardInputKind.organizations: (controller, _, _) =>
      _OrganizationsInputs(controller: controller),
  OpenKatWizardInputKind.currentAsOf: (controller, _, _) =>
      _CurrentDateInput(controller: controller),
  OpenKatWizardInputKind.previousAsOf: (controller, _, _) =>
      _PreviousDateInput(controller: controller),
  OpenKatWizardInputKind.cve: (controller, cveController, _) =>
      _CveInputs(controller: controller, textController: cveController),
  OpenKatWizardInputKind.language: (controller, _, _) =>
      _LanguageInput(controller: controller),
  OpenKatWizardInputKind.title: (controller, _, titleController) =>
      _TitleInput(controller: controller, textController: titleController),
};

class OpenKatSourceGate extends StatelessWidget {
  final OpenKatWizardController controller;
  final String? directory;
  final Future<void> Function() chooseDirectory;
  final VoidCallback? inspectAgain;

  const OpenKatSourceGate({
    super.key,
    required this.controller,
    required this.directory,
    required this.chooseDirectory,
    this.inspectAgain,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = controller.scanStatus;
    final scanFailed = status == OpenKatWizardScanStatus.failed;
    final failed = scanFailed || status == OpenKatWizardScanStatus.empty;
    final scanning = status == OpenKatWizardScanStatus.scanning;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  failed
                      ? Icons.folder_off_outlined
                      : Icons.folder_open_outlined,
                  size: 42,
                  color: failed
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  failed
                      ? scanFailed
                            ? l10n.d('Kon dit bestand niet openen.')
                            : l10n.d(
                                'Deze map bevat geen bruikbare rapportages',
                              )
                      : l10n.d('Waar staan de OpenKAT-rapportages?'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  failed
                      ? l10n.d(
                          'OciDeck kon geen bruikbare OpenKAT-metingen vinden. Kies een andere map of bekijk het importverslag om te zien welke bestanden zijn overgeslagen.',
                        )
                      : l10n.d(
                          'Kies de map waarin OpenKAT de rapportages heeft geplaatst. OciDeck leest deze map alleen; er wordt niets gewijzigd of verstuurd.',
                        ),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                if (directory != null) ...[
                  const SizedBox(height: 16),
                  _InfoSurface(
                    icon: Icons.folder_outlined,
                    child: SelectableText(
                      directory!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: scanning ? null : chooseDirectory,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(
                        failed
                            ? l10n.d('Andere map kiezen')
                            : l10n.d('Map kiezen…'),
                      ),
                    ),
                    if (directory != null)
                      FilledButton.icon(
                        onPressed: scanning ? null : inspectAgain,
                        icon: scanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.fact_check_outlined),
                        label: Text(l10n.d('Rapportages controleren…')),
                      ),
                    if (failed && controller.scan != null)
                      TextButton(
                        onPressed: () =>
                            showOpenKatImportReport(context, controller.scan!),
                        child: Text(l10n.d('Importverslag bekijken')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OpenKatScenarioStep extends StatelessWidget {
  final OpenKatWizardController controller;

  const OpenKatScenarioStep({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => OpenKatRecipePicker(
    controller: controller,
    inspectImport: () => showOpenKatImportReport(context, controller.scan!),
  );
}

class OpenKatInputsStep extends StatelessWidget {
  final OpenKatWizardController controller;
  final TextEditingController cveController;
  final TextEditingController titleController;

  const OpenKatInputsStep({
    super.key,
    required this.controller,
    required this.cveController,
    required this.titleController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final id = controller.selectedScenarioId!;
    final descriptor = controller.selectedScenario!.descriptor;
    Widget render(OpenKatWizardInputKind input) =>
        openKatWizardInputRenderers[input]!(
          controller,
          cveController,
          titleController,
        );
    final primaryInputs = descriptor.inputs.where(
      (input) =>
          input != OpenKatWizardInputKind.language &&
          input != OpenKatWizardInputKind.title,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Alleen wat nodig is'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          openKatScenarioTitle(l10n, id),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        for (final input in primaryInputs) ...[
          render(input),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 18),
        ExpansionTile(
          key: const ValueKey('openkat-more-settings'),
          initiallyExpanded: controller.moreSettingsExpanded,
          onExpansionChanged: (_) => controller.toggleMoreSettings(),
          tilePadding: EdgeInsets.zero,
          title: Text(l10n.d('Meer instellingen')),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  if (descriptor.inputs.contains(
                    OpenKatWizardInputKind.language,
                  ))
                    render(OpenKatWizardInputKind.language),
                  if (descriptor.inputs.contains(
                    OpenKatWizardInputKind.title,
                  )) ...[
                    const SizedBox(height: 14),
                    render(OpenKatWizardInputKind.title),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OrganizationsInputs extends StatelessWidget {
  final OpenKatWizardController controller;

  const _OrganizationsInputs({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Organisaties kiezen'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: controller.scan!.organizationOptions.length < 6
              ? controller.scan!.organizationOptions.length * 64
              : 320,
          child: ListView.builder(
            key: const ValueKey('openkat-organizations-list'),
            itemCount: controller.scan!.organizationOptions.length,
            itemExtent: 64,
            itemBuilder: (context, index) {
              final option = controller.scan!.organizationOptions[index];
              return CheckboxListTile(
                key: ValueKey('openkat-organization-${option.code}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: controller.selectedOrganizationCodes.contains(
                  option.code,
                ),
                onChanged: (_) => controller.toggleOrganization(option.code),
                title: Text(option.name),
                subtitle: Text(
                  '${option.measurementCount} ${l10n.d('metingen')}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrganizationInputs extends StatelessWidget {
  final OpenKatWizardController controller;

  const _OrganizationInputs({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scan = controller.scan!;
    final dates = MaterialLocalizations.of(context);
    final requiresPrevious = controller.selectedScenario!.descriptor.inputs
        .contains(OpenKatWizardInputKind.previousAsOf);
    return DropdownButtonFormField<String>(
      initialValue: controller.selectedOrganizationCode,
      decoration: InputDecoration(labelText: l10n.d('Organisatie')),
      isExpanded: true,
      items: [
        for (final option in scan.organizationOptions)
          DropdownMenuItem(
            value: option.code,
            enabled: !requiresPrevious || option.measurementCount > 1,
            child: Text(
              '${option.name} · '
              '${dates.formatMediumDate(option.latestMeasurement)} · '
              '${option.measurementCount} '
              '${l10n.d('metingen')}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: controller.chooseOrganization,
    );
  }
}

class _CurrentDateInput extends StatelessWidget {
  final OpenKatWizardController controller;

  const _CurrentDateInput({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatter = MaterialLocalizations.of(context);
    return _InfoSurface(
      icon: Icons.event_available_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.d('Laatste bruikbare meting')),
          const SizedBox(height: 3),
          Text(
            formatter.formatMediumDate(controller.currentAsOf!),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PreviousDateInput extends StatelessWidget {
  final OpenKatWizardController controller;

  const _PreviousDateInput({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatter = MaterialLocalizations.of(context);
    final scan = controller.scan!;
    final organizationInput = controller.selectedScenario!.descriptor.inputs
        .contains(OpenKatWizardInputKind.organization);
    final selected = organizationInput
        ? controller.selectedOrganizationCode
        : null;
    final dates = selected == null
        ? scan.preview.measurementDates.toList()
        : scan.organizations
              .where((organization) => organization.code == selected)
              .expand((organization) => organization.snapshots)
              .where((snapshot) => snapshot.usable)
              .map((snapshot) => snapshot.reportDate)
              .toSet()
              .toList();
    dates.sort();
    return DropdownButtonFormField<DateTime>(
      initialValue: controller.previousAsOf,
      decoration: InputDecoration(
        labelText: l10n.d('Eerdere bruikbare meting'),
      ),
      items: [
        for (final date in dates.where(
          (date) => date.isBefore(controller.currentAsOf!),
        ))
          DropdownMenuItem(
            value: date,
            child: Text(formatter.formatMediumDate(date)),
          ),
      ],
      onChanged: controller.choosePreviousDate,
    );
  }
}

class _LanguageInput extends StatelessWidget {
  final OpenKatWizardController controller;

  const _LanguageInput({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<OpenKatReportLanguage>(
      initialValue: controller.language,
      decoration: InputDecoration(labelText: l10n.d('Taal')),
      items: [
        DropdownMenuItem(
          value: OpenKatReportLanguage.dutch,
          child: Text(l10n.d('Nederlands')),
        ),
        DropdownMenuItem(
          value: OpenKatReportLanguage.english,
          child: Text(l10n.d('Engels')),
        ),
      ],
      onChanged: (value) {
        if (value != null) controller.chooseLanguage(value);
      },
    );
  }
}

class _TitleInput extends StatelessWidget {
  final OpenKatWizardController controller;
  final TextEditingController textController;

  const _TitleInput({required this.controller, required this.textController});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: textController,
      onChanged: controller.setTitle,
      decoration: InputDecoration(
        labelText: l10n.d('Rapporttitel'),
        hintText: openKatScenarioTitle(l10n, controller.selectedScenarioId!),
      ),
    );
  }
}

class _CveInputs extends StatelessWidget {
  final OpenKatWizardController controller;
  final TextEditingController textController;

  const _CveInputs({required this.controller, required this.textController});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final options = controller.scan!.cveOptions;
    final found = controller.cveId == null
        ? null
        : options.where((option) => option.id == controller.cveId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('openkat-cve-search'),
          controller: textController,
          onChanged: controller.chooseCve,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: l10n.d('CVE zoeken'),
            hintText: l10n.d('Bijvoorbeeld CVE-2026-12345'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 10),
        if (textController.text.isNotEmpty && found == null)
          _Message(
            icon: Icons.info_outline,
            text: l10n.d(
              'Deze CVE is niet aangetroffen in de gekozen metingen.',
            ),
          )
        else if (found != null)
          _InfoSurface(
            icon: Icons.hub_outlined,
            child: Text(
              '${found.id} · ${found.organizationCount} '
              '${l10n.d('organisaties')} · ${found.systemCount} '
              '${l10n.d('systemen')}',
            ),
          ),
        const SizedBox(height: 12),
        for (final option in options.take(8))
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            leading: Icon(
              controller.cveId == option.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: controller.cveId == option.id
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(option.id),
            subtitle: Text(
              '${option.organizationCount} ${l10n.d('organisaties')} · '
              '${option.systemCount} ${l10n.d('systemen')}',
            ),
            onTap: () {
              textController.text = option.id;
              controller.chooseCve(option.id);
            },
          ),
      ],
    );
  }
}

class OpenKatReviewStep extends StatelessWidget {
  final OpenKatWizardController controller;

  const OpenKatReviewStep({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scan = controller.scan!;
    final report = controller.reportPreview;
    final formatter = MaterialLocalizations.of(context);
    final measurements = report?.measurements ?? const [];
    final dates =
        measurements
            .where((item) => item.measuredAt != null)
            .map((item) => item.measuredAt!)
            .toSet()
            .toList()
          ..sort();
    final includedOrganizations = _includedOrganizationNames(scan);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Controleren'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          openKatScenarioTitle(l10n, controller.selectedScenarioId!),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        KeyedSubtree(
          key: const ValueKey('openkat-review-organizations'),
          child: _ReviewRow(
            icon: Icons.groups_outlined,
            title: l10n.d('Organisaties'),
            value: includedOrganizations,
          ),
        ),
        _ReviewRow(
          icon: Icons.calendar_month_outlined,
          title: l10n.d('Werkelijke meetdatums'),
          value: dates.isEmpty
              ? l10n.d('Geen bruikbare meetdatum')
              : dates.map(formatter.formatMediumDate).join(' · '),
        ),
        KeyedSubtree(
          key: const ValueKey('openkat-review-language'),
          child: _ReviewRow(
            icon: Icons.language_outlined,
            title: l10n.d('Taal'),
            value: controller.language == OpenKatReportLanguage.dutch
                ? l10n.d('Nederlands')
                : l10n.d('Engels'),
          ),
        ),
        _ReviewRow(
          icon: Icons.description_outlined,
          title: l10n.d('Import'),
          value:
              '${report?.sourceTraces.map((trace) => trace.sourceHash).toSet().length ?? 0} '
              '${l10n.d('rapportages gebruikt')} · '
              '${scan.preview.skippedCount} ${l10n.d('overgeslagen')}',
          action: TextButton(
            onPressed: () => showOpenKatImportReport(context, scan),
            child: Text(l10n.d('Bekijk importverslag')),
          ),
        ),
        if (controller.updating)
          _Message(
            icon: Icons.refresh,
            text: l10n.d(
              'Gegenereerde dia’s worden vernieuwd. Uw eigen dia’s en kopieën blijven behouden.',
            ),
          ),
        for (final diagnostic
            in report?.diagnostics ?? const <OpenKatReportDiagnostic>[])
          _Message(
            icon: diagnostic.severity == OpenKatReportDiagnosticSeverity.error
                ? Icons.error_outline
                : Icons.warning_amber_outlined,
            text: openKatDiagnosticText(l10n, diagnostic),
            error: diagnostic.severity == OpenKatReportDiagnosticSeverity.error,
            warning:
                diagnostic.severity != OpenKatReportDiagnosticSeverity.error,
          ),
        if (controller.buildError != null)
          _Message(
            icon: Icons.error_outline,
            text: l10n.d(
              controller.unsafeUpdate
                  ? 'Dit bestaande rapport kan niet veilig worden bijgewerkt. Maak het rapport als nieuw; het bestaande deck blijft ongewijzigd.'
                  : 'Het rapport kon niet worden gemaakt. Uw keuzes zijn behouden; controleer de waarschuwingen en probeer het opnieuw.',
            ),
            error: true,
          ),
        const SizedBox(height: 18),
        Text(
          l10n.d('Dit rapport bevat'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final block
            in report?.plan?.blocks ?? const <OpenKatReportBlock>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 44,
            leading: Icon(
              Icons.check,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(openKatBlockTitle(l10n, block.kind)),
          ),
      ],
    );
  }

  String _includedOrganizationNames(OpenKatWizardScan scan) {
    final inputs = controller.selectedScenario!.descriptor.inputs;
    final scoped = scan.organizationOptions.where(
      (item) => inputs.contains(OpenKatWizardInputKind.organization)
          ? item.code == controller.selectedOrganizationCode
          : controller.selectedOrganizationCodes.isEmpty ||
                controller.selectedOrganizationCodes.contains(item.code),
    );
    final cveId = controller.cveId;
    if (!inputs.contains(OpenKatWizardInputKind.cve) || cveId == null) {
      return scoped.map((item) => item.name).join(', ');
    }
    return scoped
        .where((option) {
          final organization = scan.organizations
              .where((item) => item.code == option.code)
              .firstOrNull;
          final snapshots =
              organization?.snapshots
                  .where(
                    (snapshot) =>
                        snapshot.usable &&
                        !snapshot.reportDate.isAfter(controller.currentAsOf!),
                  )
                  .toList() ??
              <OpenKatSnapshot>[];
          snapshots.sort((a, b) => a.reportDate.compareTo(b.reportDate));
          return snapshots.lastOrNull?.findings.any(
                (finding) => finding.cveIds.contains(cveId),
              ) ??
              false;
        })
        .map((item) => item.name)
        .join(', ');
  }
}

class OpenKatUpdateConfirmation extends StatelessWidget {
  final OpenKatWizardController controller;
  final Future<void> Function() update;
  final Future<void> Function() createNew;

  const OpenKatUpdateConfirmation({
    super.key,
    required this.controller,
    required this.update,
    required this.createNew,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.d('OpenKAT-rapport bijwerken'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.d(
                  'OciDeck gebruikt dezelfde bron en keuzes en neemt de nieuwste geschikte metingen. Uw eigen dia’s en kopieën blijven behouden.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (controller.buildError != null) ...[
                const SizedBox(height: 16),
                _Message(
                  icon: Icons.error_outline,
                  text: l10n.d(
                    controller.unsafeUpdate
                        ? 'Dit bestaande rapport kan niet veilig worden bijgewerkt. Maak het rapport als nieuw; het bestaande deck blijft ongewijzigd.'
                        : 'Het rapport kon niet worden gemaakt. Uw keuzes zijn behouden; controleer de waarschuwingen en probeer het opnieuw.',
                  ),
                  error: true,
                ),
              ],
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: controller.changeUpdateChoices,
                    child: Text(l10n.d('Keuzes wijzigen…')),
                  ),
                  if (controller.buildError != null && controller.scan != null)
                    OutlinedButton(
                      onPressed: () =>
                          showOpenKatImportReport(context, controller.scan!),
                      child: Text(l10n.d('Bekijk importverslag')),
                    ),
                  FilledButton.icon(
                    onPressed: controller.busy
                        ? null
                        : controller.unsafeUpdate
                        ? createNew
                        : update,
                    icon: controller.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      controller.buildError == null
                          ? l10n.d('Rapport bijwerken')
                          : controller.unsafeUpdate
                          ? l10n.d('Als nieuw rapport maken')
                          : l10n.d('Opnieuw proberen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoSurface extends StatelessWidget {
  final IconData icon;
  final Widget child;

  const _InfoSurface({required this.icon, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    ),
  );
}

class _ReviewRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Widget? action;

  const _ReviewRow({
    required this.icon,
    required this.title,
    required this.value,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _InfoSurface(
      icon: icon,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool error;
  final bool warning;

  const _Message({
    required this.icon,
    required this.text,
    this.error = false,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = error
        ? AppTheme.dangerBg
        : warning
        ? AppTheme.warningBg
        : colors.surfaceContainerLow;
    final foreground = error
        ? AppTheme.dangerFg
        : warning
        ? AppTheme.warningFg
        : colors.onSurfaceVariant;
    final border = error
        ? AppTheme.dangerBgSoft
        : warning
        ? AppTheme.warningBgSoft
        : colors.outlineVariant;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showOpenKatImportReport(
  BuildContext context,
  OpenKatWizardScan scan,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('OpenKAT-importverslag')),
      content: SizedBox(
        width: 640,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in scan.manifest.entries)
              ListTile(
                leading: Icon(
                  entry.status == 'ok'
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  color: entry.status == 'ok'
                      ? AppTheme.successFg
                      : AppTheme.warningFg,
                ),
                title: Text(entry.path),
                subtitle: Text(
                  entry.status == 'ok'
                      ? l10n.d('Bruikbaar')
                      : _manifestStatus(l10n, entry.status),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  },
);

String _manifestStatus(AppLocalizations l10n, String status) {
  if (status == 'duplicate') return l10n.d('Dubbel bestand overgeslagen');
  if (status == 'conflict') return l10n.d('Conflicterende meting overgeslagen');
  if (status == 'unrecognized') {
    return l10n.d('Geen ondersteunde OpenKAT-rapportage');
  }
  if (status.startsWith('error')) {
    return l10n.d('Bestand kon niet worden gelezen');
  }
  return l10n.d('Overgeslagen');
}
