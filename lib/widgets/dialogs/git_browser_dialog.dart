import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/git_provider.dart';
import '../../utils/user_facing_error.dart';
import 'remote_browser_dialog_chrome.dart';

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

    return RemoteBrowserDialogChrome(
      title: l10n.d('Presentatie openen uit git'),
      icon: Icons.source_outlined,
      subtitle: config == null ? null : Text('${config.slug} · $branch'),
      body: _body(context, ref, branch),
      cancelLabel: l10n.d('Annuleren'),
      onCancel: () => Navigator.of(context).pop(),
      initialWidth: 520,
      height: 500,
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, String branch) {
    final l10n = context.l10n;
    final decks = ref.watch(
      gitDeckListProvider((connectionId: connectionId, branch: branch)),
    );

    return decks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RemoteBrowserMessage(
        // De ruwe forge-tekst was Nederlands en onvertaald, en bij een
        // onbekende status letterlijk "Onverwachte status 418". Alles wat niet
        // uit deze provider komt is een bug — dan liever algemene raad dan een
        // ruwe fout op het scherm; userFacingError doet precies dat.
        text: userFacingError(l10n, e),
        icon: Icons.error_outline,
      ),
      data: (map) {
        if (map.isEmpty) {
          return RemoteBrowserMessage(
            text: l10n.d('Geen presentaties in deze repository.'),
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
}
