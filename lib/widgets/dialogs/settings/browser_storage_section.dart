import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/browser_deck_store.dart';
import '../../../state/tabs_provider.dart';
import '../../../utils/log.dart';
import '../browser_storage_dialog.dart';

/// Heropenen gebruikt dezelfde pakketimport en veiligheidscontrole als bestanden.
class BrowserStorageSection extends ConsumerStatefulWidget {
  const BrowserStorageSection({super.key});
  @override
  ConsumerState<BrowserStorageSection> createState() =>
      _BrowserStorageSectionState();
}

class _BrowserStorageSectionState extends ConsumerState<BrowserStorageSection> {
  late Future<List<BrowserDeckEntry>> _entries;
  @override
  void initState() {
    super.initState();
    _entries = BrowserDeckStore().list();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.d(browserStorageWarning)),
        const SizedBox(height: 8),
        FutureBuilder<List<BrowserDeckEntry>>(
          future: _entries,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                l10n.d(
                  'Browseropslag mislukt. Download uw presentatie als bestand.',
                ),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            if (snapshot.data!.isEmpty) {
              return Text(
                l10n.d(
                  'Nog geen browserkopieën. Kies bij Opslaan voor In browser bewaren.',
                ),
              );
            }
            return Column(
              children: [
                for (final entry in snapshot.data!)
                  ListTile(
                    title: Text(entry.title),
                    subtitle: Text(entry.savedAt),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.folder_open),
                          tooltip: l10n.d('Openen'),
                          onPressed: () => _open(entry),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l10n.d('Verwijderen'),
                          onPressed: () => _remove(entry),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _open(BrowserDeckEntry entry) async {
    try {
      final tabs = ref.read(tabsProvider.notifier);
      final result = await tabs.openDeckFromBytes(
        entry.bytes,
        '${entry.id}.ocideck',
      );
      if (!mounted) return;
      if (result != OpenResult.opened) {
        _failed();
        return;
      }
      ref.read(tabsProvider).current?.deckNotifierOrNull?.browserStorageId =
          entry.id;
      Navigator.pop(context);
    } catch (e, s) {
      logError('browser-storage: operation failed', e, s);
      if (mounted) _failed();
    }
  }

  Future<void> _remove(BrowserDeckEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.d('Verwijderen')),
        content: Text(
          l10n.d(
            'Browserkopie verwijderen? Bewaar zo nodig eerst een bestand.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.d('Verwijderen')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await BrowserDeckStore().remove(entry.id);
      if (mounted) setState(() => _entries = BrowserDeckStore().list());
    } catch (e, s) {
      logError('browser-storage: operation failed', e, s);
      if (mounted) _failed();
    }
  }

  void _failed() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'Browseropslag mislukt. Download uw presentatie als bestand.',
        ),
      ),
    ),
  );
}
