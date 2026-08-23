import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/git_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/user_facing_error.dart';

/// Kiest een deck uit de geconfigureerde git-repository en geeft de deckmap
/// terug (`decks/<naam>`), of `null` bij annuleren. Het ophalen/openen zelf doet
/// de aanroeper — zodat de security-gate en de foutmeldingen daar leven, net als
/// bij [WebdavBrowserDialog].
///
/// Fase 0 is read-only en toont alleen de hoofdbranch. De branchkiezer hoort bij
/// Fase 4, waar branches en tags betekenis krijgen.
class GitBrowserDialog extends ConsumerWidget {
  /// De verbinding waaruit gebladerd wordt. Meegegeven en niet zelf uit de
  /// instellingen gelezen: de aanroeper heeft de gebruiker al laten kiezen, en
  /// die keuze mag hier niet stilletjes een andere worden.
  final String connectionId;

  const GitBrowserDialog({super.key, required this.connectionId});

  static Future<String?> show(
    BuildContext context, {
    required String connectionId,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => GitBrowserDialog(connectionId: connectionId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final config = ref.watch(gitConfigProvider(connectionId));
    final branch = config?.defaultBranch ?? 'main';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                l10n.d('Presentatie openen uit git'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (config != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  '${config.slug} · $branch',
                  style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                ),
              ),
            const Divider(height: 1),
            Expanded(child: _body(context, ref, branch)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.d('Annuleren')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, String branch) {
    final l10n = context.l10n;
    final decks = ref.watch(
      gitDeckListProvider((connectionId: connectionId, branch: branch)),
    );

    return decks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _message(
        // De ruwe forge-tekst was Nederlands en onvertaald, en bij een
        // onbekende status letterlijk "Onverwachte status 418". Alles wat niet
        // uit deze provider komt is een bug — dan liever algemene raad dan een
        // ruwe fout op het scherm; userFacingError doet precies dat.
        userFacingError(l10n, e),
        icon: Icons.error_outline,
      ),
      data: (map) {
        if (map.isEmpty) {
          return _message(
            l10n.d('Geen presentaties in deze repository.'),
            icon: Icons.folder_off_outlined,
          );
        }
        final names = map.keys.toList()..sort();
        return ListView.builder(
          itemCount: names.length,
          itemBuilder: (context, i) {
            final name = names[i];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.slideshow_outlined, size: 20),
              title: Text(name, style: const TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(context).pop(map[name]),
            );
          },
        );
      },
    );
  }

  Widget _message(String text, {required IconData icon}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppTheme.slate400),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
          ],
        ),
      ),
    );
  }
}
