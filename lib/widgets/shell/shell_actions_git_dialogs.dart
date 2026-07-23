// Part of the app_shell library — see ../app_shell.dart.
// De git-dialogen (historie, versies, vergelijken, opslaan, review, merge, tag),
// afgesplitst van shell_actions_git.dart zodat beide bestanden onder de
// regelratchet blijven. Alle imports staan in de hoofdlibrary; de handlers die
// deze dialogen openen staan ernaast in shell_actions_git.dart.
part of '../app_shell.dart';

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
                        color: e.pushed ? AppTheme.slate400 : AppTheme.accentFg,
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

/// Kiezen per botsende slide (§8.6). Geeft terug wat er in het samengevoegde
/// deck omgewisseld moet worden: index → de slide die daar komt, of `null` om
/// hem weg te halen. Slides waar de gebruiker ónze kant houdt staan er niet in;
/// die staan er al.
class _MergeConflictDialog extends StatefulWidget {
  final List<SlideConflict> conflicts;
  const _MergeConflictDialog({required this.conflicts});

  @override
  State<_MergeConflictDialog> createState() => _MergeConflictDialogState();
}

class _MergeConflictDialogState extends State<_MergeConflictDialog> {
  /// baseIndex → nemen we die van de ander? Standaard nee: onze kant blijft.
  final Map<int, bool> _takeTheirs = {};

  String _titleOf(SlideConflict c, AppLocalizations l10n) {
    final title = (c.ours ?? c.theirs ?? c.base).title.trim();
    return title.isEmpty ? l10n.d('(zonder titel)') : title;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Allebei bewerkt — kies per slide')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Iemand anders bewerkte dit deck tegelijk met jou. Alles wat vanzelf kon is al samengevoegd; deze slides niet.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.conflicts.length,
                itemBuilder: (context, i) => _row(l10n, widget.conflicts[i]),
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
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _resolution()),
          child: Text(l10n.d('Toepassen')),
        ),
      ],
    );
  }

  Widget _row(AppLocalizations l10n, SlideConflict c) {
    final theirs = _takeTheirs[c.baseIndex] ?? false;
    // Een verwijdering heeft geen tekst om te tonen; benoem hem dan als zodanig.
    String label(Slide? slide, String whose) =>
        slide == null ? '$whose — ${l10n.d('verwijderd')}' : whose;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titleOf(c, l10n),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                label: Text(
                  label(c.ours, l10n.d('Mijn versie')),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  label(c.theirs, l10n.d('Hun versie')),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
            selected: {theirs},
            onSelectionChanged: (s) =>
                setState(() => _takeTheirs[c.baseIndex] = s.first),
          ),
        ],
      ),
    );
  }

  /// Vertaal de keuzes naar wat er in het samengevoegde deck moet gebeuren.
  /// Daar staat nu `ours ?? theirs`; alleen afwijkingen daarvan zijn werk.
  Map<int, Slide?> _resolution() {
    final out = <int, Slide?>{};
    for (final c in widget.conflicts) {
      final index = c.mergedIndex;
      if (index == null) continue;
      final theirs = _takeTheirs[c.baseIndex] ?? false;
      if (theirs) {
        // Hun kant: hun slide, of weghalen als zij hem juist weggooiden.
        out[index] = c.theirs;
      } else if (c.ours == null) {
        // Onze kant wás een verwijdering, maar er staat nu hun slide.
        out[index] = null;
      }
    }
    return out;
  }
}

/// Wat de versiekiezer teruggeeft: een versie om te openen, of het verzoek om
/// er twee te vergelijken.
typedef _VersionAction = ({TagRef? open, bool compare});

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
                    onTap: () =>
                        Navigator.pop(context, (open: tag, compare: false)),
                  );
                },
              ),
      ),
      actions: [
        // Vergelijken kan pas als er twee versies zijn om tussen te kijken.
        if (tags.length >= 2)
          TextButton.icon(
            onPressed: () =>
                Navigator.pop(context, (open: null, compare: true)),
            icon: const Icon(Icons.compare_arrows, size: 16),
            label: Text(l10n.d('Vergelijken…')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }
}

/// Kies twee versies om te vergelijken. Standaard de twee nieuwste, want dat is
/// bijna altijd wat je wilt weten: wat is er sinds de vorige versie veranderd?
Future<({TagRef a, TagRef b})?> _showVersionComparePicker(
  BuildContext context,
  String deckName,
  List<TagRef> tags,
) {
  return showDialog<({TagRef a, TagRef b})>(
    context: context,
    builder: (_) => _VersionComparePicker(deckName: deckName, tags: tags),
  );
}

class _VersionComparePicker extends StatefulWidget {
  final String deckName;
  final List<TagRef> tags;
  const _VersionComparePicker({required this.deckName, required this.tags});

  @override
  State<_VersionComparePicker> createState() => _VersionComparePickerState();
}

class _VersionComparePickerState extends State<_VersionComparePicker> {
  late TagRef _a = widget.tags[1]; // de op één na nieuwste (het "voor")
  late TagRef _b = widget.tags[0]; // de nieuwste (het "na")

  String _label(TagRef tag) =>
      GitRepoLayout.versionOfTag(tag.name, widget.deckName) ?? tag.name;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    DropdownButton<TagRef> picker(TagRef value, ValueChanged<TagRef> onPick) =>
        DropdownButton<TagRef>(
          value: value,
          isExpanded: true,
          items: [
            for (final tag in widget.tags)
              DropdownMenuItem(value: tag, child: Text(_label(tag))),
          ],
          onChanged: (v) => v == null ? null : onPick(v),
        );

    return AlertDialog(
      title: Text(l10n.d('Versies vergelijken')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Kies twee versies; de oudste van de twee is het vertrekpunt.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 14),
            picker(_a, (v) => setState(() => _a = v)),
            const SizedBox(height: 8),
            picker(_b, (v) => setState(() => _b = v)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: _a.name == _b.name
              ? null
              : () => Navigator.pop(context, (a: _a, b: _b)),
          icon: const Icon(Icons.compare_arrows, size: 16),
          label: Text(l10n.d('Vergelijken')),
        ),
      ],
    );
  }
}

/// Toont wat er tussen twee uitgebrachte versies veranderde (§9.5). Alleen de
/// wijzigingen: ongewijzigde slides zijn ruis in een vergelijking.
class _VersionDiffDialog extends StatelessWidget {
  final String beforeLabel;
  final String afterLabel;
  final Deck beforeDeck;
  final Deck afterDeck;
  final VersionDiff diff;

  const _VersionDiffDialog({
    required this.beforeLabel,
    required this.afterLabel,
    required this.beforeDeck,
    required this.afterDeck,
    required this.diff,
  });

  static String _titleOf(Slide? slide, AppLocalizations l10n) {
    final title = slide?.title.trim() ?? '';
    return title.isEmpty ? l10n.d('(zonder titel)') : title;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final changes = diff.changes
        .where((SlideChange c) => c.kind != SlideChangeKind.unchanged)
        .toList();

    return AlertDialog(
      title: Text('$beforeLabel → $afterLabel'),
      content: SizedBox(
        width: 520,
        child: changes.isEmpty
            ? Text(l10n.d('Deze twee versies zijn inhoudelijk gelijk.'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${diff.addedCount} ${l10n.d('toegevoegd')} · '
                    '${diff.removedCount} ${l10n.d('verwijderd')} · '
                    '${diff.editedCount} ${l10n.d('gewijzigd')} · '
                    '${diff.movedCount} ${l10n.d('verplaatst')}',
                    style: TextStyle(fontSize: 12, color: AppTheme.slate400),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: changes.length,
                      itemBuilder: (context, i) =>
                          _row(context, l10n, changes[i]),
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

  Widget _row(BuildContext context, AppLocalizations l10n, SlideChange change) {
    final (icon, colour, kindLabel) = switch (change.kind) {
      SlideChangeKind.added => (
        Icons.add_circle_outline,
        AppTheme.successFg,
        l10n.d('toegevoegd'),
      ),
      SlideChangeKind.removed => (
        Icons.remove_circle_outline,
        AppTheme.dangerFg,
        l10n.d('verwijderd'),
      ),
      SlideChangeKind.edited => (
        Icons.edit_outlined,
        AppTheme.amber600,
        l10n.d('gewijzigd'),
      ),
      SlideChangeKind.moved => (
        Icons.swap_vert,
        AppTheme.blue500,
        l10n.d('verplaatst'),
      ),
      SlideChangeKind.unchanged => (Icons.remove, AppTheme.slate400, ''),
    };
    // Waar de slide stond en waar hij nu staat, 1-gebaseerd voor de lezer.
    final before = change.beforeIndex == null
        ? null
        : '${l10n.d('slide')} ${change.beforeIndex! + 1}';
    final after = change.afterIndex == null
        ? null
        : '${l10n.d('slide')} ${change.afterIndex! + 1}';
    final where = switch ((before, after)) {
      (final b?, final a?) when b != a => '$b → $a',
      (final b?, null) => b,
      (null, final a?) => a,
      (final b?, _) => b,
      _ => '',
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 18, color: colour),
      title: Text(
        _titleOf(change.after ?? change.before, l10n),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '$kindLabel · $where',
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
      // Alleen een bijgewerkte slide heeft twee kanten om naast elkaar te zetten.
      trailing: change.kind == SlideChangeKind.edited
          ? TextButton(
              onPressed: () => SlideDiffDialog.show(
                context,
                primary: SlideDiffRef(
                  label: '$afterLabel · ${after ?? ''}',
                  slide: change.after!,
                  projectPath: afterDeck.projectPath,
                  themeProfile: afterDeck.themeProfile,
                ),
                others: [
                  SlideDiffRef(
                    label: '$beforeLabel · ${before ?? ''}',
                    slide: change.before!,
                    projectPath: beforeDeck.projectPath,
                    themeProfile: beforeDeck.themeProfile,
                  ),
                ],
              ),
              child: Text(l10n.d('Verschillen')),
            )
          : null,
    );
  }
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

typedef _ReviewChoice = ({String title, String message});

Future<_ReviewChoice?> _showReviewDialog(
  BuildContext context, {
  required String deckName,
}) {
  return showDialog<_ReviewChoice>(
    context: context,
    builder: (_) => _ReviewDialog(deckName: deckName),
  );
}

class _ReviewDialog extends StatefulWidget {
  final String deckName;
  const _ReviewDialog({required this.deckName});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final TextEditingController _title = TextEditingController(
    text: 'Concept: ${widget.deckName}',
  );
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _title.text.trim();
    return AlertDialog(
      title: Text(l10n.d('Uitbrengen ter review')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Opent een pull request van je concept naar de hoofdbranch, zodat het beoordeeld kan worden vóór het uitkomt.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.d('Titel'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.d('Toelichting'),
                hintText: l10n.d('Wat is er veranderd en waarom?'),
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
          onPressed: title.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  title: title,
                  message: _message.text.trim(),
                )),
          icon: const Icon(Icons.rate_review_outlined, size: 16),
          label: Text(l10n.d('Uitbrengen')),
        ),
      ],
    );
  }
}

/// Bevestig het mergen van een concept; geeft `true`/`false` (concept-branch
/// opruimen) terug, of `null` bij annuleren.
Future<bool?> _showMergeDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _MergeDialog(),
  );
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog();

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  bool _prune = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Concept mergen')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Voegt de review-PR van dit concept samen met de hoofdbranch.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _prune,
              onChanged: (v) => setState(() => _prune = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(l10n.d('Concept-branch opruimen na het mergen')),
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
          onPressed: () => Navigator.pop(context, _prune),
          icon: const Icon(Icons.merge_outlined, size: 16),
          label: Text(l10n.d('Mergen')),
        ),
      ],
    );
  }
}

typedef _TagChoice = ({String version, String message});

Future<_TagChoice?> _showTagDialog(BuildContext context) {
  return showDialog<_TagChoice>(
    context: context,
    builder: (_) => const _TagDialog(),
  );
}

class _TagDialog extends StatefulWidget {
  const _TagDialog();

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final TextEditingController _version = TextEditingController(text: 'v1.0');
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _version.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final version = _version.text.trim();
    // Valideer de versie los van de deknaam: een geldige tag zou eruit komen.
    final valid = GitRepoLayout.releaseTag('x', version) != null;
    return AlertDialog(
      title: Text(l10n.d('Versie vastleggen')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Zet een release-tag op de kop van de hoofdbranch — de versie die je hebt gepresenteerd.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _version,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.d('Versie'),
                hintText: l10n.d('v1.0'),
                errorText: version.isEmpty || valid
                    ? null
                    : l10n.d('Gebruik vX, bijvoorbeeld v1.0.'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              decoration: InputDecoration(
                labelText: l10n.d('Toelichting'),
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
              ? () => Navigator.pop(context, (
                  version: version,
                  message: _message.text.trim().isEmpty
                      ? '$version — vastgelegd met OciDeck'
                      : _message.text.trim(),
                ))
              : null,
          icon: const Icon(Icons.bookmark_add_outlined, size: 16),
          label: Text(l10n.d('Vastleggen')),
        ),
      ],
    );
  }
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
