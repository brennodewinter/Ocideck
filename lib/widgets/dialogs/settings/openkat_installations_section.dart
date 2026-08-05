import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/openkat/openkat_installation.dart';
import '../../../services/openkat/openkat_error_messages.dart';
import '../../../services/openkat/openkat_rocky_client.dart';
import '../../../state/openkat_provider.dart';
import '../../../theme/app_theme.dart';
import '../openkat_installation_wizard.dart';
import '../openkat_server_report_dialog.dart';

/// Het serverblok op Integraties: installatiekaarten + toevoegen + rapportage.
class OpenKatInstallationsSection extends ConsumerWidget {
  const OpenKatInstallationsSection({super.key, required this.desktopCapable});

  final bool desktopCapable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final installations = ref.watch(openKatInstallationsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Vanuit een OpenKAT-server'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.d(
            'Sluit één of meer OpenKAT-omgevingen aan (bijvoorbeeld productie en acceptatie). OciDeck toont beschikbare rapportages; de inhoud haalt u binnen via een JSON-export uit OpenKAT.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600, height: 1.35),
        ),
        const SizedBox(height: 12),
        if (!desktopCapable)
          Text(
            l10n.d(
              'De OpenKAT-koppeling is alleen beschikbaar in de desktopversie.',
            ),
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          )
        else if (installations.isEmpty)
          _EmptyInstallations(
            onAdd: () => OpenKatInstallationWizard.show(context),
          )
        else ...[
          for (final installation in installations) ...[
            _InstallationCard(installation: installation),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => OpenKatInstallationWizard.show(context),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.d('Server toevoegen…')),
              ),
              FilledButton.icon(
                onPressed: () => OpenKatServerReportDialog.show(context),
                icon: const Icon(Icons.cloud_download_outlined, size: 16),
                label: Text(l10n.d('Rapportage van server…')),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EmptyInstallations extends StatelessWidget {
  const _EmptyInstallations({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Nog geen OpenKAT-server aangesloten.'),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.d('Server toevoegen…')),
        ),
      ],
    );
  }
}

class _InstallationCard extends ConsumerStatefulWidget {
  const _InstallationCard({required this.installation});

  final OpenKatInstallation installation;

  @override
  ConsumerState<_InstallationCard> createState() => _InstallationCardState();
}

class _InstallationCardState extends ConsumerState<_InstallationCard> {
  bool _testing = false;

  OpenKatInstallation get installation => widget.installation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppTheme.slate50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.iceBlue),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _StatusDot(status: installation.lastStatus),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        installation.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        installation.host.isEmpty
                            ? installation.baseUrl
                            : installation.host,
                        style: TextStyle(fontSize: 11, color: AppTheme.slate600),
                      ),
                      Text(
                        l10n.d(openKatStatusLabel(installation.lastStatus)),
                        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _testing ? null : _test,
                  child: Text(
                    _testing
                        ? l10n.d('Bezig…')
                        : l10n.d('Testen'),
                  ),
                ),
                TextButton(
                  onPressed: () => OpenKatInstallationWizard.show(
                    context,
                    existing: installation,
                  ),
                  child: Text(l10n.d('Bewerken')),
                ),
                TextButton(
                  onPressed: _confirmDelete,
                  child: Text(l10n.d('Verwijderen')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final notifier = ref.read(openKatProvider.notifier);
    final token = await notifier.readToken(installation.id);
    if (token == null || token.trim().isEmpty) {
      await notifier.markInstallationChecked(
        id: installation.id,
        status: OpenKatInstallationStatus.tokenMissing,
      );
      if (mounted) setState(() => _testing = false);
      return;
    }
    final client = OpenKatRockyClient(
      installation: installation,
      token: token,
    );
    try {
      if (!client.canSend) throw OpenKatRequestException(client.denialReason!);
      await client.testConnection();
      await notifier.markInstallationChecked(
        id: installation.id,
        status: OpenKatInstallationStatus.connected,
      );
    } catch (_) {
      await notifier.markInstallationChecked(
        id: installation.id,
        status: OpenKatInstallationStatus.failed,
      );
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _confirmDelete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.d('OpenKAT-server verwijderen?')),
        content: Text(
          l10n
              .d(
                'Dit verwijdert “{name}” en het bijbehorende toegangstoken van dit apparaat. Dat kunt u niet ongedaan maken.',
              )
              .replaceAll('{name}', installation.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.d('Verwijderen')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(openKatProvider.notifier).removeInstallation(installation.id);
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final OpenKatInstallationStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      OpenKatInstallationStatus.connected => AppTheme.accentFg,
      OpenKatInstallationStatus.tokenMissing => AppTheme.slate400,
      OpenKatInstallationStatus.failed => Theme.of(context).colorScheme.error,
      OpenKatInstallationStatus.unchecked => AppTheme.slate400,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
