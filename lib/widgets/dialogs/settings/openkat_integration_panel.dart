import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/openkat_provider.dart';
import '../../../state/settings_provider.dart';
import '../../../theme/app_theme.dart';
import '../../shell/openkat_import_action.dart';
import '../../shell/openkat_import_summary.dart';
import 'openkat_installations_section.dart';

/// De instellingen van de OpenKAT-koppeling: map-import én live servers.
/// Body van de OpenKAT-sectie op Integraties (#1158); de schakelaar komt van
/// `IntegrationsPanel`.
///
/// Twee bronblokken met één hiërarchie — zie `docs/design/OPENKAT_LIVE_UX.md`.
class OpenKatIntegrationBody extends ConsumerWidget {
  const OpenKatIntegrationBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final desktop = ref.watch(openKatDesktopCapableProvider);
    if (!desktop) {
      return Text(
        l10n.d(
          'De OpenKAT-koppeling is alleen beschikbaar in de desktopversie.',
        ),
        style: TextStyle(fontSize: 12, color: AppTheme.slate600),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Vanuit een map'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.d(
            'Kies de map waarin OpenKAT de rapportages heeft geplaatst. OciDeck leest deze map alleen; er wordt niets gewijzigd of verstuurd.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        const SizedBox(height: 12),
        _DirectoryField(),
        const SizedBox(height: 12),
        const _ImportNowRow(),
        const SizedBox(height: 10),
        Text(
          l10n.d(
            'De import leest alleen; er wordt niets in deze map gewijzigd of verstuurd. Bestanden die geen OpenKAT-rapportage blijken, worden overgeslagen en in het importverslag benoemd.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),
        OpenKatInstallationsSection(desktopCapable: desktop),
      ],
    );
  }
}

/// De knop die de map-import hier meteen uitvoert, met het verslag eronder.
class _ImportNowRow extends ConsumerStatefulWidget {
  const _ImportNowRow();

  @override
  ConsumerState<_ImportNowRow> createState() => _ImportNowRowState();
}

class _ImportNowRowState extends ConsumerState<_ImportNowRow> {
  bool _running = false;
  OpenKatImportOutcome? _outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final directory = ref.watch(openKatDirectoryProvider);
    final enabled = directory != null && !_running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: directory == null ? l10n.d('Geen map gekozen') : '',
          child: FilledButton.icon(
            onPressed: enabled ? _import : null,
            icon: _running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined, size: 16),
            label: Text(l10n.d('Rapportages controleren…')),
          ),
        ),
        if (_outcome != null) ...[
          const SizedBox(height: 8),
          _OutcomeText(outcome: _outcome!),
        ],
      ],
    );
  }

  Future<void> _import() async {
    setState(() {
      _running = true;
      _outcome = null;
    });
    final outcome = await importOpenKatReports(context, ref, announce: false);
    if (!mounted) return;
    setState(() {
      _running = false;
      _outcome = outcome;
    });
  }
}

class _OutcomeText extends StatelessWidget {
  final OpenKatImportOutcome outcome;

  const _OutcomeText({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bad = outcome.failed || outcome.loaded == 0;
    final text = [
      openKatImportSummary(l10n, outcome),
      if (!bad && !outcome.updatedDeck)
        l10n.d('Het overzicht staat klaar in een nieuw tabblad.'),
    ].join(' ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          bad ? Icons.error_outline : Icons.check_circle_outline,
          size: 15,
          color: bad ? Theme.of(context).colorScheme.error : AppTheme.slate600,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: bad
                  ? Theme.of(context).colorScheme.error
                  : AppTheme.slate600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DirectoryField extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final directory = ref.watch(openKatDirectoryProvider);
    final pathBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.iceBlue),
      ),
      child: Text(
        directory ?? l10n.d('Geen map gekozen'),
        style: TextStyle(
          fontSize: 12,
          color: directory == null ? AppTheme.slate500 : AppTheme.slate800,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pick(context, ref),
          icon: const Icon(Icons.folder_open_outlined, size: 16),
          label: Text(l10n.d('Map kiezen…')),
        ),
        if (directory != null)
          IconButton(
            onPressed: () =>
                ref.read(openKatProvider.notifier).setReportDirectory(null),
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.d('Map wissen'),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (scale >= 1.5 || constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pathBox,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: pathBox),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    if (!supportsLocalProjectFolders) return;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map met OpenKAT-rapportages kiezen'),
      initialDirectory:
          ref.read(openKatDirectoryProvider) ??
          ref.read(settingsProvider).homeDirectory,
    );
    if (result == null) return;
    await ref.read(openKatProvider.notifier).setReportDirectory(result);
  }
}
