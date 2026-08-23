import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/documentation_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../utils/text_search.dart';
import '../../utils/url_launcher_util.dart';
import 'document_reader_screen.dart';

/// One document row in the Settings → Documentation list: the icon and title
/// shown on the tile, the bundled asset it opens, and an optional canonical
/// online version. The `assetBase` string literals live where these entries are
/// built (settings_dialog_docs.dart) so `docs_registration_test` keeps finding
/// them.
class DocEntry {
  const DocEntry({
    required this.icon,
    required this.title,
    required this.assetBase,
    this.onlineUrl,
  });

  final IconData icon;
  final String title;
  final String assetBase;
  final String? onlineUrl;
}

/// A named group of documents (e.g. "Gebruiker", "Techniek"), rendered under a
/// small caps heading when the list is unfiltered or has matches in the group.
class DocSection {
  const DocSection({required this.label, required this.entries});

  final String label;
  final List<DocEntry> entries;
}

/// A document that satisfies the current query, plus a snippet drawn from its
/// content around the first match with the matched words marked for
/// highlighting.
class DocSearchHit {
  const DocSearchHit(this.snippet, this.highlights);

  /// A short, whitespace-collapsed excerpt of the document content (empty when
  /// the query matched the title only and the document has no body).
  final String snippet;

  /// Ranges within [snippet] that should be emphasised. Non-overlapping and
  /// sorted by start.
  final List<TextMatchRange> highlights;
}

/// Collapses any run of whitespace (including newlines) to a single space so a
/// snippet reads as one line. Hoisted out of the hot path per the project's
/// "no inline RegExp" convention.
final RegExp _whitespaceRun = RegExp(r'\s+');

/// Splits a raw query into the individual words to match. Empty when the query
/// is blank.
List<String> parseQueryTerms(String query) {
  return query
      .split(_whitespaceRun)
      .where((t) => t.isNotEmpty)
      .toList(growable: false);
}

/// Returns a hit when [title] + [content] contains **every** term
/// (case-insensitive, substring), or `null` when any term is absent. Multiple
/// terms therefore narrow the results (AND), matching how a filter box is
/// expected to behave. The snippet is drawn around the earliest content match;
/// when a document matches on its title alone the snippet falls back to the
/// start of its body.
DocSearchHit? matchDoc({
  required String title,
  required String content,
  required List<String> terms,
}) {
  if (terms.isEmpty) return null;
  for (final term in terms) {
    final inTitle = findAllMatches(title, term).isNotEmpty;
    final inContent = findAllMatches(content, term).isNotEmpty;
    if (!inTitle && !inContent) return null;
  }
  return _buildHit(content, terms);
}

DocSearchHit _buildHit(String content, List<String> terms) {
  var firstStart = -1;
  var firstEnd = -1;
  for (final term in terms) {
    final matches = findAllMatches(content, term);
    if (matches.isEmpty) continue;
    final m = matches.first;
    if (firstStart < 0 || m.start < firstStart) {
      firstStart = m.start;
      firstEnd = m.end;
    }
  }
  // Only matched in the title: show the opening of the body as context.
  if (firstStart < 0) return _snippet(content, 0, 0, terms);
  return _snippet(content, firstStart, firstEnd, terms);
}

/// Builds a whitespace-collapsed excerpt of [content] around [start]..[end],
/// bracketed with an ellipsis where it was trimmed, and recomputes the
/// highlight ranges against the final string (so they stay correct after the
/// collapse and ellipsis prefix).
DocSearchHit _snippet(String content, int start, int end, List<String> terms) {
  const pad = 60;
  final from = (start - pad).clamp(0, content.length);
  final to = (end + pad).clamp(0, content.length);
  final core = content
      .substring(from, to)
      .replaceAll(_whitespaceRun, ' ')
      .trim();
  final prefix = from > 0 ? '… ' : '';
  final suffix = to < content.length ? ' …' : '';
  final snippet = '$prefix$core$suffix';

  final ranges = <TextMatchRange>[];
  for (final term in terms) {
    ranges.addAll(findAllMatches(snippet, term));
  }
  ranges.sort((a, b) => a.start.compareTo(b.start));
  return DocSearchHit(snippet, _mergeRanges(ranges));
}

/// Merges overlapping or touching ranges so the rendered spans never overlap
/// (two query words can match adjacent or overlapping text).
List<TextMatchRange> _mergeRanges(List<TextMatchRange> sorted) {
  final merged = <TextMatchRange>[];
  for (final r in sorted) {
    if (merged.isNotEmpty && r.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add(
        TextMatchRange(last.start, r.end > last.end ? r.end : last.end),
      );
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// The Settings → Documentation pane: a search field over the bundled document
/// list. With an empty query it shows the full grouped list; while typing it
/// filters to documents whose title or body contains every typed word and shows
/// a matching excerpt beneath each. Document bodies are loaded once (in the
/// current UI language) so filtering is instant.
class DocumentationSearchTab extends StatefulWidget {
  const DocumentationSearchTab({
    super.key,
    required this.sections,
    this.service = const DocumentationService(),
    this.repositoryDocsUrl,
  });

  final List<DocSection> sections;
  final DocumentationService service;

  /// When set, a footer card links out to the repository for the documentation
  /// that is deliberately not bundled (developer and design docs). Shown under
  /// the list in every state — including an empty search result — so a user who
  /// searched for an un-bundled doc still finds the way to it.
  final String? repositoryDocsUrl;

  @override
  State<DocumentationSearchTab> createState() => _DocumentationSearchTabState();
}

class _DocumentationSearchTabState extends State<DocumentationSearchTab> {
  final TextEditingController _controller = TextEditingController();
  final Map<String, String> _content = {};
  String? _loadedLanguage;
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (language != _loadedLanguage) _loadContent(language);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _controller.text;
    if (query != _query) setState(() => _query = query);
  }

  Future<void> _loadContent(String language) async {
    _loadedLanguage = language;
    setState(() => _loading = true);
    final loaded = <String, String>{};
    for (final section in widget.sections) {
      for (final entry in section.entries) {
        try {
          loaded[entry.assetBase] = await widget.service.load(
            entry.assetBase,
            language,
          );
        } catch (error, stack) {
          logError('doc-search: load ${entry.assetBase}', error, stack);
        }
      }
    }
    // A newer language load (or a disposed widget) supersedes this one.
    if (!mounted || _loadedLanguage != language) return;
    setState(() {
      _content
        ..clear()
        ..addAll(loaded);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final terms = parseQueryTerms(_query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _searchField(l10n),
        const SizedBox(height: 16),
        if (terms.isEmpty)
          ..._unfilteredSections()
        else
          ..._filteredSections(l10n, terms),
        if (widget.repositoryDocsUrl != null) _repositoryFooter(l10n),
      ],
    );
  }

  /// A footer card pointing to the repository for the docs that are not bundled.
  /// It leaves the app (opens the browser) rather than opening the in-app
  /// reader, so it is styled as a distinct "go elsewhere" row with an
  /// open-in-new affordance, not as a document tile.
  Widget _repositoryFooter(AppLocalizations l10n) {
    final url = widget.repositoryDocsUrl!;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => openExternalUrl(url),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.slate300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 22,
                  color: AppTheme.blue500,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.d('Meer documentatie op de repository'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.d(
                          'De volledige documentatie — ook architectuur, bouw, broncode en ontwerp — staat op de repository.',
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new, size: 18, color: AppTheme.slate400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField(AppLocalizations l10n) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.d('Zoek in documentatie…'),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 20),
                tooltip: l10n.d('Zoekopdracht wissen'),
                onPressed: _controller.clear,
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<Widget> _unfilteredSections() {
    final widgets = <Widget>[];
    for (final section in widget.sections) {
      widgets.add(_sectionHeader(section.label));
      for (final entry in section.entries) {
        widgets.add(_tile(entry));
      }
    }
    return widgets;
  }

  List<Widget> _filteredSections(AppLocalizations l10n, List<String> terms) {
    final widgets = <Widget>[];
    for (final section in widget.sections) {
      final matched = <Widget>[];
      for (final entry in section.entries) {
        final hit = matchDoc(
          title: entry.title,
          content: _content[entry.assetBase] ?? '',
          terms: terms,
        );
        if (hit != null) matched.add(_tile(entry, hit: hit));
      }
      if (matched.isNotEmpty) {
        widgets
          ..add(_sectionHeader(section.label))
          ..addAll(matched);
      }
    }
    if (widgets.isEmpty) {
      // While bodies are still loading, stay quiet rather than briefly claiming
      // nothing matches; show the empty-result message only once loaded.
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Text(
                  l10n.d('Geen documenten gevonden'),
                  style: TextStyle(fontSize: 14, color: AppTheme.slate500),
                ),
        ),
      );
    }
    return widgets;
  }

  /// Small caps-style heading separating a class of documents.
  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10, left: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppTheme.slate400,
        ),
      ),
    );
  }

  Widget _tile(DocEntry entry, {DocSearchHit? hit}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        // `paper` en niet vast wit: de titel en het fragment zijn `slate700`/
        // `slate500` — mode-afhankelijk, dus licht in donkere modus. Op een wit
        // vlak stonden ze op 1,30 en 2,09:1, een wit blok met spooktekst in een
        // verder donkere leesomgeving (#825). Op `paper` lezen ze 13,2 / 8,2:1.
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => DocumentReaderScreen.open(
            context,
            title: entry.title,
            assetBase: entry.assetBase,
            onlineUrl: entry.onlineUrl,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.slate300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(entry.icon, size: 22, color: AppTheme.blue500),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate700,
                        ),
                      ),
                      if (hit != null && hit.snippet.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _snippetText(hit),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: AppTheme.slate400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renders the excerpt with the matched words bold; the rest muted.
  Widget _snippetText(DocSearchHit hit) {
    final base = TextStyle(fontSize: 12.5, color: AppTheme.slate500);
    final mark = base.copyWith(
      fontWeight: FontWeight.w700,
      color: AppTheme.slate700,
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in hit.highlights) {
      if (range.start > cursor) {
        spans.add(TextSpan(text: hit.snippet.substring(cursor, range.start)));
      }
      spans.add(
        TextSpan(
          text: hit.snippet.substring(range.start, range.end),
          style: mark,
        ),
      );
      cursor = range.end;
    }
    if (cursor < hit.snippet.length) {
      spans.add(TextSpan(text: hit.snippet.substring(cursor)));
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
