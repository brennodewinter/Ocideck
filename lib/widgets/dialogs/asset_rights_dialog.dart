import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/asset_rights.dart';
import '../../services/git/asset_rights_index.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';

class AssetRightsDialog extends StatefulWidget {
  final RepoAssetRightsIndex index;
  final RepoAssetRightsSnapshot initial;

  const AssetRightsDialog({
    super.key,
    required this.index,
    required this.initial,
  });

  @override
  State<AssetRightsDialog> createState() => _AssetRightsDialogState();
}

class _AssetRightsDialogState extends State<AssetRightsDialog> {
  late List<AssetRightsAssessment> _items = [...widget.initial.assessments];
  String? _busyKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final review = _items.where((a) => a.openSignals.isNotEmpty).toList();
    return AlertDialog(
      title: Text(l10n.d('Mogelijke auteursrechtelijke risico’s')),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Dit is een technische signalering, geen juridisch oordeel. Een beheerder beoordeelt de aanwijzingen.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 8),
            Text(
              '${review.length} ${l10n.d('afbeeldingen vragen om beoordeling')} · '
              '${widget.initial.newlyScanned} ${l10n.d('nieuw gescand')}',
            ),
            if (widget.initial.unreadable.isNotEmpty)
              Text(
                '${widget.initial.unreadable.length} ${l10n.d('bestanden konden niet veilig worden beoordeeld')}',
                style: TextStyle(color: AppTheme.dangerFg),
              ),
            const Divider(),
            Expanded(
              child: review.isEmpty
                  ? Center(
                      child: Text(l10n.d('Geen openstaande aanwijzingen.')),
                    )
                  : ListView(
                      children: [
                        for (final assessment in review)
                          for (final signal in assessment.openSignals)
                            _signalTile(l10n, assessment, signal),
                      ],
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
  }

  Widget _signalTile(
    AppLocalizations l10n,
    AssetRightsAssessment assessment,
    AssetRightsSignal signal,
  ) {
    final busy = _busyKey == '${assessment.sha256} ${signal.key}';
    final colour = signal.risk == AssetRightsRisk.high
        ? AppTheme.dangerFg
        : AppTheme.amber600;
    return Card(
      child: ListTile(
        leading: Icon(Icons.copyright_outlined, color: colour),
        title: Text(signal.message),
        subtitle: Text(
          '${assessment.sha256.substring(0, 12)}… · ${signal.ruleId}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
        trailing: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : PopupMenuButton<(AssetRightsDispositionStatus, String)>(
                tooltip: l10n.d('Afdoening'),
                onSelected: (choice) =>
                    _decide(assessment, signal, choice.$1, choice.$2),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: (AssetRightsDispositionStatus.accepted, 'licensed'),
                    child: Text(l10n.d('Geldige rechten aangetoond')),
                  ),
                  PopupMenuItem(
                    value: (
                      AssetRightsDispositionStatus.accepted,
                      'false_positive',
                    ),
                    child: Text(l10n.d('Onterechte signalering')),
                  ),
                  PopupMenuItem(
                    value: (
                      AssetRightsDispositionStatus.rejected,
                      'not_permitted',
                    ),
                    child: Text(l10n.d('Niet gebruiken')),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _decide(
    AssetRightsAssessment assessment,
    AssetRightsSignal signal,
    AssetRightsDispositionStatus status,
    String reason,
  ) async {
    final note = await _askForNote();
    if (note == null || !mounted) return;
    setState(() => _busyKey = '${assessment.sha256} ${signal.key}');
    try {
      final updated = await widget.index.decide(
        assessment,
        signal,
        status: status,
        reason: reason,
        note: note.trim().isEmpty ? null : note.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final item in _items)
            if (item.sha256 == updated.sha256) updated else item,
        ];
      });
    } catch (error, stackTrace) {
      logError('AssetRightsDialog: afdoening opslaan', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.d(
                'De afdoening kon niet worden opgeslagen. Scan opnieuw en probeer het nogmaals.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<String?> _askForNote() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.d('Afdoening vastleggen')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.d('Notitie (optioneel)'),
            hintText: dialogContext.l10n.d(
              'Bijvoorbeeld een factuur-, licentie- of dossierverwijzing',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(dialogContext.l10n.d('Vastleggen')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
