import 'dart:convert';

import '../markdown_service.dart';
import 'git_forge.dart';

/// Eén vindplaats: waar in de repo de zoekterm staat.
class DeckSearchHit {
  /// De deknaam, zoals in `decks/<naam>/`.
  final String deck;

  /// De deckmap, voor de aanroeper die hem wil openen.
  final String deckDir;

  /// Nulgebaseerde slidepositie, of -1 wanneer de treffer in de deck-eigenschappen
  /// (de front matter) staat en dus niet bij één slide hoort.
  final int slideIndex;

  /// De eerste kop in die slide, puur ter oriëntatie — leeg als de slide er geen
  /// heeft.
  final String slideTitle;

  /// De regel waar de term in staat, ingekort; nooit de hele slide.
  final String snippet;

  const DeckSearchHit({
    required this.deck,
    required this.deckDir,
    required this.slideIndex,
    required this.slideTitle,
    required this.snippet,
  });

  /// De treffer staat in de deck-eigenschappen, niet in een slide.
  bool get isFrontMatter => slideIndex < 0;
}

/// De uitkomst van één zoekronde.
class DeckSearchResult {
  final List<DeckSearchHit> hits;

  /// Decks waarvan de `deck.md` niet te lezen viel. Het antwoord is dan korter
  /// dan de waarheid, niet onjuist — zie [DeckSearch.search].
  final List<String> unreadableDecks;

  /// Er waren meer treffers dan de limiet. De lijst is afgekapt, en dat mag de
  /// gebruiker weten in plaats van een stille halve waarheid te krijgen.
  final bool truncated;

  const DeckSearchResult({
    required this.hits,
    required this.unreadableDecks,
    this.truncated = false,
  });

  /// Iedere deck is gelezen en niets is afgekapt.
  bool get isComplete => unreadableDecks.isEmpty && !truncated;
}

/// Zoeken over álle decks in de repo, niet alleen het geopende (§9.3).
///
/// Dit is de tekst-tegenhanger van `AssetIndex`: dezelfde ene ronde over de repo,
/// maar dan naar tekst. En met bewust de omgekeerde faalrichting. De
/// assetindex weigert te antwoorden zodra hij iets niet kon lezen, want daar is
/// het antwoord "niemand gebruikt dit" en volgt er een onomkeerbare verwijdering
/// uit. Hier is het antwoord "hier staat het", en dat blijft waar ook als één
/// deck ontbreekt: de gebruiker krijgt de treffers die er zijn, mét de melding
/// welk deck niet gelezen kon worden. Stil afkappen zou het erge zijn.
class DeckSearch {
  DeckSearch({required this.forge, required this.branch});

  final GitForge forge;
  final String branch;

  /// Voorbij deze grens houdt een lijst op nuttig te zijn en wordt hij afgekapt
  /// — maar wel zichtbaar, via [DeckSearchResult.truncated].
  static const defaultMaxHits = 200;

  /// Zoveel tekens rond de treffer, zodat een regel van 4 kB de lijst niet
  /// onleesbaar maakt.
  static const _snippetWindow = 120;

  /// Zoek [query] in elke `deck.md` op [branch].
  ///
  /// Leest N bestanden over de REST-laag, dus dit hoort bij een ingedrukte
  /// zoekknop en niet bij elke toetsaanslag. Een lege of witruimte-only term
  /// levert niets op: die zou elk deck volledig teruggeven.
  Future<DeckSearchResult> search(
    String query, {
    bool caseSensitive = false,
    int maxHits = defaultMaxHits,
  }) async {
    final needle = caseSensitive ? query.trim() : query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const DeckSearchResult(hits: [], unreadableDecks: []);
    }

    final decks = await forge.listDecks(branch);
    final hits = <DeckSearchHit>[];
    final unreadable = <String>[];
    var truncated = false;

    for (final entry in decks.entries) {
      if (hits.length >= maxHits) {
        truncated = true;
        break;
      }
      final markdown = await _deckMarkdown(entry.value);
      if (markdown == null) {
        unreadable.add(entry.key);
        continue;
      }
      final found = _searchDeck(
        deck: entry.key,
        deckDir: entry.value,
        markdown: markdown,
        needle: needle,
        caseSensitive: caseSensitive,
        room: maxHits - hits.length,
      );
      if (found.truncated) truncated = true;
      hits.addAll(found.hits);
    }

    return DeckSearchResult(
      hits: hits,
      unreadableDecks: unreadable..sort(),
      truncated: truncated,
    );
  }

  ({List<DeckSearchHit> hits, bool truncated}) _searchDeck({
    required String deck,
    required String deckDir,
    required String markdown,
    required String needle,
    required bool caseSensitive,
    required int room,
  }) {
    final text = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final split = _splitFrontMatter(text);
    final hits = <DeckSearchHit>[];
    // Apart van `hits.length == room`: een lijst die precies vol is hoeft niet
    // afgekapt te zijn. Alleen echt vroegtijdig stoppen telt.
    var stoppedEarly = false;

    void collect(int slideIndex, String slideTitle, String block) {
      for (final line in block.split('\n')) {
        final haystack = caseSensitive ? line : line.toLowerCase();
        final at = haystack.indexOf(needle);
        if (at < 0) continue;
        // Pas hier de grens, niet bovenaan de lus: "afgekapt" moet betekenen dat
        // er een échte treffer niet is getoond. Anders zet elke lege regel ná de
        // laatste treffer de vlag, en waarschuwt het scherm over niets.
        if (hits.length >= room) {
          stoppedEarly = true;
          return;
        }
        hits.add(
          DeckSearchHit(
            deck: deck,
            deckDir: deckDir,
            slideIndex: slideIndex,
            slideTitle: slideTitle,
            snippet: _snippet(line, at),
          ),
        );
      }
    }

    collect(-1, '', split.frontMatter);
    // Bewust de splitser van de parser en geen eigen `split('---')`: die zou een
    // `---` binnen een codeblok als slidegrens lezen en de treffer bij de
    // verkeerde slide hangen. Wel de splitser, níét de hele parse — zoeken moet
    // ook werken in een deck dat (nog) niet parseert.
    final blocks = MarkdownService.splitSlideBlocks(split.body);
    for (var i = 0; i < blocks.length; i++) {
      collect(i, _titleOf(blocks[i]), blocks[i]);
    }

    return (hits: hits, truncated: stoppedEarly);
  }

  /// De eerste kopregel in een slide, of leeg. Puur om de gebruiker te laten
  /// zien wélke slide hij aankijkt.
  static String _titleOf(String block) {
    for (final line in block.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        return trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      }
    }
    return '';
  }

  /// Een venster rond de treffer, met ellipsis waar er is weggeknipt.
  static String _snippet(String line, int at) {
    final trimmed = line.trim();
    if (trimmed.length <= _snippetWindow) return trimmed;
    final offset = at - (line.length - line.trimLeft().length);
    var start = offset - _snippetWindow ~/ 3;
    if (start < 0) start = 0;
    var end = start + _snippetWindow;
    if (end > trimmed.length) {
      end = trimmed.length;
      start = end - _snippetWindow;
    }
    return '${start > 0 ? '…' : ''}${trimmed.substring(start, end)}'
        '${end < trimmed.length ? '…' : ''}';
  }

  /// Splitst de front matter van de rest, volgens dezelfde regel als de parser:
  /// een `---`-regel bovenaan tot de eerstvolgende `---`.
  static ({String frontMatter, String body}) _splitFrontMatter(String text) {
    if (!text.startsWith('---\n')) return (frontMatter: '', body: text);
    final end = text.indexOf('\n---\n', 4);
    if (end == -1) return (frontMatter: '', body: text);
    return (frontMatter: text.substring(4, end), body: text.substring(end + 5));
  }

  Future<String?> _deckMarkdown(String deckDir) async {
    try {
      final bytes = await forge.readBlob(branch, '$deckDir/deck.md');
      return utf8.decode(bytes, allowMalformed: true);
    } on GitForgeException {
      return null;
    }
  }
}
