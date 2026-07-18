// Part of the app_shell library — see ../app_shell.dart.
// Zoeken over álle decks in de repository (§9.3), niet alleen het geopende.
// Eigen bestand omdat de git-dialogen anders over de regelratchet gaan; de
// handler staat in shell_actions_git.dart.
part of '../app_shell.dart';

/// Zoek in elke `deck.md` in de repo en open de gekozen vindplaats.
///
/// Bewust een knop en geen zoeken-tijdens-typen: elke ronde leest N bestanden
/// over de REST-laag, en dat is niet iets om per toetsaanslag te doen.
class _GitSearchDialog extends StatefulWidget {
  final DeckSearch searcher;
  const _GitSearchDialog({required this.searcher});

  @override
  State<_GitSearchDialog> createState() => _GitSearchDialogState();
}

class _GitSearchDialogState extends State<_GitSearchDialog> {
  final _query = TextEditingController();
  bool _caseSensitive = false;
  bool _busy = false;
  DeckSearchResult? _result;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_query.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.searcher.search(
        _query.text,
        caseSensitive: _caseSensitive,
      );
      if (mounted) setState(() => _result = result);
    } on GitForgeException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Zoeken in alle decks')),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    onSubmitted: (_) => _run(),
                    decoration: InputDecoration(
                      labelText: l10n.d('Zoekterm'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _run,
                  child: Text(l10n.d('Zoeken')),
                ),
              ],
            ),
            CheckboxListTile(
              value: _caseSensitive,
              onChanged: (v) => setState(() => _caseSensitive = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(
                l10n.d('Hoofdlettergevoelig'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Flexible(child: _body(l10n)),
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

  Widget _body(AppLocalizations l10n) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(
        _error!,
        style: TextStyle(fontSize: 12, color: AppTheme.severityCritical),
      );
    }
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    if (result.hits.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Niets gevonden.'),
            style: TextStyle(fontSize: 12, color: AppTheme.slate400),
          ),
          _incompleteNote(l10n, result),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result.hits.length} ${l10n.d('vindplaatsen')}',
          style: TextStyle(fontSize: 12, color: AppTheme.slate400),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: result.hits.length,
            itemBuilder: (context, i) => _hitRow(l10n, result.hits[i]),
          ),
        ),
        _incompleteNote(l10n, result),
      ],
    );
  }

  Widget _hitRow(AppLocalizations l10n, DeckSearchHit hit) {
    final where = hit.isFrontMatter
        ? l10n.d('deck-eigenschappen')
        : hit.slideTitle.isEmpty
        ? '${l10n.d('slide')} ${hit.slideIndex + 1}'
        : '${l10n.d('slide')} ${hit.slideIndex + 1} — ${hit.slideTitle}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.description_outlined,
        size: 18,
        color: AppTheme.slate400,
      ),
      title: Text(
        '${hit.deck} · $where',
        style: const TextStyle(fontSize: 12.5),
      ),
      subtitle: Text(
        hit.snippet,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: AppTheme.slate400,
        ),
      ),
      // Het deck openen, niet de slide: het zoekresultaat wijst je de weg, de
      // deck zelf is waar je verder werkt.
      onTap: () => Navigator.pop(context, hit.deckDir),
    );
  }

  /// Zeg het wanneer het antwoord korter is dan de waarheid. Elke getoonde
  /// treffer klopt, maar "meer is er niet" mag hier niet gesuggereerd worden.
  Widget _incompleteNote(AppLocalizations l10n, DeckSearchResult result) {
    if (result.isComplete) return const SizedBox.shrink();
    final parts = <String>[
      if (result.truncated)
        l10n.d('Er zijn meer treffers dan hier passen; verfijn de zoekterm.'),
      if (result.unreadableDecks.isNotEmpty)
        '${l10n.d('Niet doorzocht, want onleesbaar:')} '
            '${result.unreadableDecks.join(', ')}.',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        parts.join(' '),
        style: TextStyle(fontSize: 11, color: AppTheme.amber600),
      ),
    );
  }
}
