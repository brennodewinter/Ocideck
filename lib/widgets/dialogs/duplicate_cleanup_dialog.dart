import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../services/trash_service.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/display_path.dart';
import '../../utils/log.dart';
import '../duplicate_badges.dart';
import '../resizable_dialog_box.dart';

/// Eén stel byte-identieke kopieën van dezelfde presentatie.
class CleanupGroup {
  final String title;
  final List<String> paths;

  const CleanupGroup({required this.title, required this.paths});
}

/// Zet groepen identieke kopieën naast elkaar (vindplaats + wijzigingsdatum)
/// en verplaatst overbodige naar de prullenbak van het OS — nadrukkelijk de
/// prullenbak, nooit hard verwijderen. De laatste kopie van een groep en
/// bestanden die nog in een tabblad openstaan zijn niet te verwijderen.
///
/// Geeft true terug wanneer er iets is verplaatst (de aanroeper kan dan
/// bijvoorbeeld opnieuw scannen).
class DuplicateCleanupDialog extends ConsumerStatefulWidget {
  final List<CleanupGroup> groups;
  final String? homeDir;

  /// Injecteerbaar voor tests, zodat die niet naar de echte prullenbak
  /// van de ontwikkelaar schrijven.
  final TrashService? trashService;

  const DuplicateCleanupDialog({
    super.key,
    required this.groups,
    required this.homeDir,
    this.trashService,
  });

  static Future<bool> show(
    BuildContext context, {
    required List<CleanupGroup> groups,
    required String? homeDir,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => DuplicateCleanupDialog(groups: groups, homeDir: homeDir),
    );
    return changed ?? false;
  }

  @override
  ConsumerState<DuplicateCleanupDialog> createState() =>
      _DuplicateCleanupDialogState();
}

class _DuplicateCleanupDialogState
    extends ConsumerState<DuplicateCleanupDialog> {
  late final TrashService _trash = widget.trashService ?? TrashService();
  final Map<String, DateTime?> _modified = {};
  final Set<String> _removed = {};
  final Set<String> _busy = {};
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    for (final group in widget.groups) {
      for (final path in group.paths) {
        try {
          _modified[path] = (await File(path).stat()).modified;
        } catch (e) {
          logWarning('DuplicateCleanupDialog: stat failed', e);
        }
      }
    }
    if (mounted) setState(() {});
  }

  /// Paden die nu in een tabblad openstaan: die kopieën blijven met rust.
  Set<String> _openPaths() {
    return {
      for (final tab in ref.read(tabsProvider).tabs)
        if (tab.deckNotifier.currentState.filePath != null)
          tab.deckNotifier.currentState.filePath!,
    };
  }

  Future<void> _moveToTrash(String path) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(path));
    final ok = await _trash.moveToTrash(path);
    if (!mounted) return;
    setState(() {
      _busy.remove(path);
      if (ok) {
        _removed.add(path);
        _changed = true;
      }
    });
    if (ok) {
      await ref.read(settingsProvider.notifier).removeRecentFile(path);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.d('Naar de prullenbak verplaatst:')} '
            '${displayFolder(path, homeDir: widget.homeDir, osHome: osHomeDirectory)}',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.d('Kon niet naar de prullenbak verplaatsen.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final openPaths = _openPaths();
    final groups = [
      for (final group in widget.groups)
        (
          title: group.title,
          paths: group.paths.where((path) => !_removed.contains(path)).toList(),
        ),
    ].where((group) => group.paths.isNotEmpty).toList();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.cleaning_services_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.d('Dubbele presentaties opruimen'))),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: ResizableDialogBox(
        initialWidth: 640,
        height: 420,
        builder: (context, handle) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Opgeruimde groepen blijven zichtbaar met hun overgebleven kopie
            // (uitgegrijsd): dat bevestigt wat er is gebeurd en wat er staat.
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        l10n.d('Geen dubbele presentaties gevonden.'),
                        style: TextStyle(
                          color: AppTheme.slate500,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final group in groups)
                          _groupSection(
                            l10n,
                            group.title,
                            group.paths,
                            openPaths,
                          ),
                      ],
                    ),
            ),
            Align(alignment: Alignment.centerRight, child: handle),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: Text(l10n.t('close')),
        ),
      ],
    );
  }

  Widget _groupSection(
    AppLocalizations l10n,
    String title,
    List<String> paths,
    Set<String> openPaths,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.copy_outlined, size: 14, color: AppTheme.accentFg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$title  ·  ${paths.length} × ${l10n.d('Identieke kopieën').toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final path in paths) _pathRow(l10n, path, paths, openPaths),
        ],
      ),
    );
  }

  Widget _pathRow(
    AppLocalizations l10n,
    String path,
    List<String> groupPaths,
    Set<String> openPaths,
  ) {
    final isLast = groupPaths.length == 1;
    final isOpen = openPaths.contains(path);
    final date = formatModifiedDate(_modified[path]);
    final String? blockReason = isLast
        ? l10n.d('Laatste kopie blijft behouden')
        : (isOpen ? l10n.d('Nog geopend in een tabblad') : null);

    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: path,
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                '${displayFolder(path, homeDir: widget.homeDir, osHome: osHomeDirectory)}'
                '  ·  ${p.basename(path)}${date.isEmpty ? '' : '  ·  $date'}',
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_busy.contains(path))
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: blockReason ?? l10n.d('Naar prullenbak'),
              icon: const Icon(Icons.delete_outline, size: 18),
              visualDensity: VisualDensity.compact,
              color: blockReason == null
                  ? AppTheme.slate600
                  : AppTheme.slate200,
              onPressed: blockReason == null ? () => _moveToTrash(path) : null,
            ),
        ],
      ),
    );
  }
}
