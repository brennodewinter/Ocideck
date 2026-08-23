import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/libreplan/libreplan_client.dart';
import '../../services/libreplan/libreplan_import.dart';
import '../../services/secret_store.dart';
import '../../state/deck_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';

/// Dialoog voor het importeren van een LibrePlan-projectsnapshot als slides.
///
/// Toont checkboxes per slide-type, een "Importeren"-knop, en voortgangs-
/// indicator tijdens het ophalen. De slides worden ingevoegd in het huidige
/// deck via [DeckNotifier.insertSlides].
class LibreplanImportDialog extends ConsumerStatefulWidget {
  const LibreplanImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const LibreplanImportDialog(),
    );
  }

  @override
  ConsumerState<LibreplanImportDialog> createState() =>
      _LibreplanImportDialogState();
}

class _LibreplanImportDialogState extends ConsumerState<LibreplanImportDialog> {
  bool _gantt = true;
  bool _wbs = true;
  bool _resources = true;
  bool _timesheet = true;
  bool _resourceLoad = true;
  bool _status = true;
  bool _milestones = true;
  bool _criticalPath = true;
  bool _importing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('LibrePlan importeren')),
      content: SizedBox(
        width: 420,
        child: _importing ? _importingContent(l10n) : _optionsContent(l10n),
      ),
      actions: _importing ? null : _actions(l10n),
    );
  }

  Widget _optionsContent(AppLocalizations l10n) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Kies welke slides u uit het LibrePlan-project wilt halen. De import is alleen-lezen en schrijft niets terug.',
            ),
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
          const SizedBox(height: 16),
          _checkbox(
            l10n.d('Gantt-planning'),
            _gantt,
            (v) => setState(() => _gantt = v ?? false),
          ),
          _checkbox(
            l10n.d('WBS (hiërarchie)'),
            _wbs,
            (v) => setState(() => _wbs = v ?? false),
          ),
          _checkbox(
            l10n.d('Projectstatus (cockpit)'),
            _status,
            (v) => setState(() => _status = v ?? false),
          ),
          _checkbox(
            l10n.d('Milestones (tijdlijn)'),
            _milestones,
            (v) => setState(() => _milestones = v ?? false),
          ),
          _checkbox(
            l10n.d('Kritieke pad (flow)'),
            _criticalPath,
            (v) => setState(() => _criticalPath = v ?? false),
          ),
          _checkbox(
            l10n.d('Resources (tabel)'),
            _resources,
            (v) => setState(() => _resources = v ?? false),
          ),
          _checkbox(
            l10n.d('Timesheet (tabel)'),
            _timesheet,
            (v) => setState(() => _timesheet = v ?? false),
          ),
          _checkbox(
            l10n.d('Resourcebelasting (grafiek)'),
            _resourceLoad,
            (v) => setState(() => _resourceLoad = v ?? false),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: AppTheme.dangerFg),
            ),
          ],
        ],
      ),
    );
  }

  Widget _importingContent(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.d('Ophalen uit LibrePlan…'),
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  List<Widget> _actions(AppLocalizations l10n) {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.d('Annuleren')),
      ),
      ElevatedButton(
        onPressed: _anyEnabled() ? () => _doImport() : null,
        child: Text(l10n.d('Importeren')),
      ),
    ];
  }

  bool _anyEnabled() =>
      _gantt ||
      _wbs ||
      _resources ||
      _timesheet ||
      _resourceLoad ||
      _status ||
      _milestones ||
      _criticalPath;

  Widget _checkbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
    );
  }

  Future<void> _doImport() async {
    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final settings = ref.read(settingsProvider).libreplanSettings;
      final key = SecretStore.libreplanKey(settings.baseUrl, settings.username);
      final password = await ref
          .read(settingsProvider.notifier)
          .readLibreplanPassword(key);

      final client = LibreplanClient(
        settings: settings,
        password: password,
        isWeb: false,
      );
      final importer = LibreplanImporter(client);
      final result = await importer.import(
        options: LibreplanImportOptions(
          gantt: _gantt,
          wbs: _wbs,
          resources: _resources,
          timesheet: _timesheet,
          resourceLoad: _resourceLoad,
          status: _status,
          milestones: _milestones,
          criticalPath: _criticalPath,
        ),
      );

      if (!mounted) return;

      if (result.slides.isEmpty) {
        setState(() {
          _importing = false;
          _error = result.warnings.isNotEmpty
              ? result.warnings.join('\n')
              : context.l10n.d('Geen slides gevonden.');
        });
        return;
      }

      // Voeg slides toe aan het huidige deck.
      final deckNotifier = ref.read(deckProvider.notifier);
      deckNotifier.insertSlides(result.slides);

      if (!mounted) return;
      Navigator.of(context).pop();

      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      final count = result.slides.length;
      final warning = result.hasWarnings ? ' ${result.warnings.first}' : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text('$count ${l10n.d("dia's geïmporteerd.")}$warning'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = '${context.l10n.d('Import mislukt: ')}$e';
      });
    }
  }
}
