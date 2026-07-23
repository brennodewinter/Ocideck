import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/git/deck_search.dart';
import '../../services/git/git_forge.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../utils/user_facing_error.dart';

/// Zoeken over álle decks in de repository (§9.3), niet alleen het geopende:
/// zoek in elke `deck.md` in de repo en geef de gekozen deckmap terug, zodat de
/// aanroeper hem langs het gewone openpad opent.
///
/// Bewust een knop en geen zoeken-tijdens-typen: elke ronde leest N bestanden
/// over de REST-laag, en dat is niet iets om per toetsaanslag te doen.
///
/// Een eigen dialoogbestand en geen `part` van de app-shell: de shell hoeft er
/// alleen een [DeckSearch] in te schuiven, en zo is dit scherm ook los te
/// beproeven — als deel van de shell-bibliotheek was het dat niet.
class GitSearchDialog extends StatefulWidget {
  final DeckSearch searcher;
  const GitSearchDialog({super.key, required this.searcher});

  /// Toont het scherm en geeft de gekozen deckmap terug, of `null`.
  static Future<String?> show(BuildContext context, DeckSearch searcher) =>
      showDialog<String>(
        context: context,
        builder: (_) => GitSearchDialog(searcher: searcher),
      );

  @override
  State<GitSearchDialog> createState() => _GitSearchDialogState();
}

class _GitSearchDialogState extends State<GitSearchDialog> {
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
      logWarning('git-zoeken: forge-aanroep mislukt', e);
      if (mounted) {
        setState(() => _error = userFacingError(context.l10n, e));
      }
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
        style: TextStyle(fontSize: 12, color: AppTheme.dangerFg),
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
  /// treffer klopt, maar "meer is er niet" mag hier niet gesuggereerd worden —
  /// of het nu door afkapping, een onleesbaar deck, of een geïndexeerde
  /// serverzoekopdracht komt die achter kan lopen.
  Widget _incompleteNote(AppLocalizations l10n, DeckSearchResult result) {
    final parts = <String>[
      if (result.coverage == DeckSearchCoverage.bestEffort)
        l10n.d(
          'Snelle server-zoekopdracht — door indexeringsvertraging kan een net gewijzigd deck ontbreken.',
        ),
      if (result.truncated)
        l10n.d('Er zijn meer treffers dan hier passen; verfijn de zoekterm.'),
      if (result.unreadableDecks.isNotEmpty)
        '${l10n.d('Niet doorzocht, want onleesbaar:')} '
            '${result.unreadableDecks.join(', ')}.',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        parts.join(' '),
        style: TextStyle(fontSize: 11, color: AppTheme.amber600),
      ),
    );
  }
}
