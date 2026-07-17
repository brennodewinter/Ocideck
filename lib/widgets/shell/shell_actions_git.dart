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

  // Native git als het er is: een echte lokale commit. Anders het REST-pad.
  final native = await ref.read(nativeGitMirrorProvider.future);
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final notifier = ref.read(tabsProvider.notifier);
    final result = native != null
        ? await notifier.saveToGitNative(
            native,
            config: config,
            deckDir: deckDir,
            branch: config.defaultBranch,
            message: choice.message,
          )
        : await notifier.saveToGit(
            forge,
            config: config,
            deckDir: deckDir,
            branch: config.defaultBranch,
            message: choice.message,
            mirror: ref.read(draftMirrorProvider),
            outbox: ref.read(outboxProvider),
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
      case GitSaveStatus.queued:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.d('Opgeslagen — gaat mee zodra er weer verbinding is.'),
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
    // Een geslaagde opslag is een goed moment om te kijken of er nog iets in de
    // wachtrij stond van een eerdere offline-sessie: leeg die op de koop toe.
    if (result.status == GitSaveStatus.committed && context.mounted) {
      await _flushGitQueue(context, ref, config, silent: true);
    }
  } on GitForgeException catch (e) {
    // De uitzondering draagt al een uitlegbare tekst voor de gebruiker.
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Loop de wachtrij van nog niet gepushte decks leeg (§8.5). Handmatig via het
/// menu, of stilletjes ([silent]) na een geslaagde opslag. Meldt de uitkomst
/// alleen als er iets te melden was, of wanneer de gebruiker er zelf om vroeg.
Future<void> _syncGit(BuildContext context, WidgetRef ref) async {
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
  await _flushGitQueue(context, ref, config, silent: false);
}

Future<void> _flushGitQueue(
  BuildContext context,
  WidgetRef ref,
  GitRepoConfig config, {
  required bool silent,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  // Native: duw de lokale historie omhoog. Er is geen wachtrij — niet-gepushte
  // commits zíjn de wachtrij.
  final native = await ref.read(nativeGitMirrorProvider.future);
  if (!context.mounted) return;
  if (native != null) {
    final result = await ref.read(tabsProvider.notifier).syncGitNative(native);
    if (!context.mounted || silent) return; // een stille flush meldt niets
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result.status) {
          GitSaveStatus.committed => l10n.d('Gesynchroniseerd met git.'),
          GitSaveStatus.queued => l10n.d(
            'Nog geen verbinding — het gaat later mee.',
          ),
          GitSaveStatus.conflict => l10n.d(
            'De branch is verzet; je commits staan lokaal klaar.',
          ),
          GitSaveStatus.failed => l10n.d('Synchroniseren mislukt.'),
        }),
      ),
    );
    return;
  }

  final engine = await ref.read(syncEngineProvider.future);
  if (engine == null) return;
  if (silent && await ref.read(outboxProvider).isEmpty) return;

  final outcomes = await ref
      .read(tabsProvider.notifier)
      .flushGit(engine, config);
  if (!context.mounted) return;

  final settled = outcomes.where((o) => o.isSettled).length;
  final stuck = outcomes.length - settled;
  if (silent && settled == 0 && stuck == 0) return;

  final String text;
  if (outcomes.isEmpty) {
    text = l10n.d('Niets in de wachtrij.');
  } else if (stuck == 0) {
    text = '${l10n.d('Gesynchroniseerd:')} $settled';
  } else {
    text =
        '${l10n.d('Gesynchroniseerd:')} $settled — '
        '${l10n.d('nog in de wachtrij:')} $stuck';
  }
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

/// Toon de commit-historie van het huidige, uit-git-geopende deck (§9.5). Alleen
/// bereikbaar op het native plane, waar er echte historie ís.
Future<void> _showGitHistory(BuildContext context, WidgetRef ref) async {
  final origin = ref.read(tabsProvider).current?.gitOrigin;
  if (origin == null) return;
  final native = await ref.read(nativeGitMirrorProvider.future);
  if (!context.mounted || native == null) return;
  final entries = await native.history(origin.deckDir);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _GitHistoryDialog(
      deckName: origin.deckName ?? origin.deckDir,
      entries: entries,
    ),
  );
}

class _GitHistoryDialog extends StatelessWidget {
  final String deckName;
  final List<GitLogEntry> entries;
  const _GitHistoryDialog({required this.deckName, required this.entries});

  String _when(DateTime? date) {
    if (date == null) return '';
    final d = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text('${l10n.d('Git-geschiedenis:')} $deckName'),
      content: SizedBox(
        width: 520,
        child: entries.isEmpty
            ? Text(l10n.d('Nog geen commits voor dit deck.'))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Tooltip(
                      message: e.pushed
                          ? l10n.d('Gepusht')
                          : l10n.d('Nog niet gepusht'),
                      child: Icon(
                        e.pushed
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined,
                        size: 18,
                        color: e.pushed ? AppTheme.slate400 : AppTheme.accent,
                      ),
                    ),
                    title: Text(
                      e.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${e.shortSha} · ${e.author} · ${_when(e.date)}',
                      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                    ),
                  );
                },
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
}

/// Toon de uitgebrachte versies (release-tags) van het huidige deck en open de
/// gekozen versie read-only (§9.4). Werkt op elk plane — het is een
/// forge-listing.
Future<void> _showGitVersions(BuildContext context, WidgetRef ref) async {
  final origin = ref.read(tabsProvider).current?.gitOrigin;
  final deckName = origin?.deckName;
  if (origin == null || deckName == null) return;
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
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final List<TagRef> tags;
  try {
    tags = await ref.read(gitDeckTagsProvider(deckName).future);
  } on GitForgeException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;

  final chosen = await showDialog<TagRef>(
    context: context,
    builder: (_) => _GitVersionsDialog(deckName: deckName, tags: tags),
  );
  if (chosen == null || !context.mounted) return;
  try {
    final result = await ref
        .read(tabsProvider.notifier)
        .openVersionFromGit(
          forge,
          config: origin.config,
          deckDir: origin.deckDir,
          tag: chosen.name,
        );
    _reportOpenFailure(messenger, l10n, result);
  } on GitForgeException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _GitVersionsDialog extends StatelessWidget {
  final String deckName;
  final List<TagRef> tags;
  const _GitVersionsDialog({required this.deckName, required this.tags});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text('${l10n.d('Versies:')} $deckName'),
      content: SizedBox(
        width: 460,
        child: tags.isEmpty
            ? Text(l10n.d('Nog geen uitgebrachte versies van dit deck.'))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: tags.length,
                itemBuilder: (context, i) {
                  final tag = tags[i];
                  final version =
                      GitRepoLayout.versionOfTag(tag.name, deckName) ??
                      tag.name;
                  final shortSha = tag.sha.length >= 7
                      ? tag.sha.substring(0, 7)
                      : tag.sha;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.label_outline, size: 18),
                    title: Text(version, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      shortSha,
                      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                    ),
                    onTap: () => Navigator.pop(context, tag),
                  );
                },
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
