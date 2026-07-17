// Part of the app_shell library — see ../app_shell.dart.
// Het git-opslaan-pad (handler + dialoog), afgesplitst van shell_actions.dart
// zodat dat bestand onder de regelratchet blijft. Alle imports staan in de
// hoofdlibrary; het open-pad staat naast dit in shell_actions.dart.
part of '../app_shell.dart';

/// Schrijf het deck van het huidige tabblad terug naar git als één commit.
/// Vraagt de deknaam (voorin gevuld met de herkomst, zodat terugschrijven één
/// bevestiging is) en een commitboodschap. Anders dan Nextcloud werkt dit óók op
/// web (§4.4).
Future<void> _saveToGit(BuildContext context, WidgetRef ref) async {
  final tab = ref.read(tabsProvider).current;
  final deck = tab?.deckNotifier.currentState.deck;
  if (tab == null || deck == null) return;
  final forge = await ref.read(gitForgeProvider.future);
  if (!context.mounted) return;
  if (forge == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Stel eerst een git-repository in bij Instellingen → Git-repository.',
          ),
        ),
      ),
    );
    return;
  }
  final config = ref.read(settingsProvider).gitRepo;
  if (config == null) return;

  final defaultName = tab.gitOrigin?.deckName ?? _safeDeckName(deck.title);
  final choice = await _showGitSaveDialog(context, defaultName: defaultName);
  if (choice == null || !context.mounted) return;
  // Het dialoog valideert de naam al; dit is de vangnet-tak.
  final deckDir = GitRepoLayout.deckDir(choice.name);
  if (deckDir == null) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final result = await ref
        .read(tabsProvider.notifier)
        .saveToGit(
          forge,
          config: config,
          deckDir: deckDir,
          branch: config.defaultBranch,
          message: choice.message,
        );
    if (!context.mounted) return;
    switch (result.status) {
      case GitSaveStatus.committed:
        final base = '${l10n.d('Opgeslagen in git:')} $deckDir';
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.warnings.isEmpty
                  ? base
                  : '$base — ${l10n.d('video en audio gaan (nog) niet mee naar git')}',
            ),
          ),
        );
      case GitSaveStatus.conflict:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.d(
                'De branch is verplaatst; herlaad het deck en sla opnieuw op.',
              ),
            ),
          ),
        );
      case GitSaveStatus.failed:
        showErrorSnackBar(
          messenger,
          l10n,
          '${l10n.d('Opslaan mislukt:')} ${result.message ?? ''}',
        );
    }
  } on GitForgeException catch (e) {
    // De uitzondering draagt al een uitlegbare tekst voor de gebruiker.
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Maak een geldige deknaam (§6) uit een deck-titel, of een nette terugval.
String _safeDeckName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '')
      .replaceAll('..', '-');
  return GitRepoLayout.isValidDeckName(cleaned) ? cleaned : 'presentatie';
}

/// Keuze uit het git-opslaan-dialoog: de deknaam plus de commitboodschap.
typedef _GitSaveChoice = ({String name, String message});

Future<_GitSaveChoice?> _showGitSaveDialog(
  BuildContext context, {
  required String defaultName,
}) {
  return showDialog<_GitSaveChoice>(
    context: context,
    builder: (_) => _GitSaveDialog(defaultName: defaultName),
  );
}

class _GitSaveDialog extends StatefulWidget {
  final String defaultName;
  const _GitSaveDialog({required this.defaultName});

  @override
  State<_GitSaveDialog> createState() => _GitSaveDialogState();
}

class _GitSaveDialogState extends State<_GitSaveDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.defaultName,
  );
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = _name.text.trim();
    final valid = GitRepoLayout.isValidDeckName(name);
    return AlertDialog(
      title: Text(l10n.d('Opslaan naar git')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.d('Deknaam'),
                helperText: l10n.d(
                  'Wordt de map decks/<naam> in de repository',
                ),
                errorText: name.isEmpty || valid
                    ? null
                    : l10n.d(
                        'Alleen letters, cijfers, punt, streep en liggend streepje',
                      ),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              decoration: InputDecoration(
                labelText: l10n.d('Commitboodschap'),
                hintText: l10n.d('Wat is er veranderd?'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: valid
              ? () {
                  final message = _message.text.trim();
                  Navigator.pop(context, (
                    name: name,
                    message: message.isEmpty
                        ? l10n.d('Bijgewerkt met OciDeck')
                        : message,
                  ));
                }
              : null,
          icon: const Icon(Icons.cloud_upload_outlined, size: 16),
          label: Text(l10n.d('Opslaan')),
        ),
      ],
    );
  }
}
