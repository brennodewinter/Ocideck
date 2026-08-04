import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/documentation_service.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/doc_link.dart';
import '../../utils/log.dart';
import '../../utils/url_launcher_util.dart';
import 'document_markdown_view.dart';

/// A full-screen, accessible reader for a bundled Markdown document.
///
/// The content fills the height and the full available window width: tables,
/// code blocks and Mermaid diagrams span the whole measure (so wide tables and
/// flowcharts are no longer squeezed), while prose is kept to a readable line
/// length within that width. A subtle text-size control in the app bar enlarges
/// or shrinks the document text; the choice is remembered (see
/// [SettingsNotifier.setDocReaderTextScale]) independently of the app-wide
/// interface scale. Text is selectable and links open externally, and a
/// find-in-page bar jumps between occurrences of a search term. It sits above
/// dialogs (pushed on the root navigator), so it can be opened from the consent
/// gate and the settings screen alike.
class DocumentReaderScreen extends ConsumerStatefulWidget {
  const DocumentReaderScreen({
    super.key,
    required this.title,
    required this.assetBase,
    this.onlineUrl,
    this.initialAnchor,
    this.service = const DocumentationService(),
  });

  /// Localised screen title (e.g. the document name).
  final String title;

  /// Base asset key, e.g. `docs/USER_GUIDE.md` or `LICENSE.md`.
  final String assetBase;

  /// Optional canonical online version, offered as an "open online" action.
  final String? onlineUrl;

  /// A heading slug ([headingSlug]) to scroll to once the document has rendered
  /// — set when this reader was opened by an internal link that carried an
  /// anchor (`FILE_FORMAT.md#what-travels`). Null lands at the top.
  final String? initialAnchor;

  final DocumentationService service;

  /// Prose (paragraphs, headings, lists) is bounded to this measure so lines
  /// stay a readable length; tables, code blocks and diagrams ignore it and use
  /// the full width. The document column itself is not capped — it fills the
  /// window (minus [_horizontalPadding]), which is what "use the whole width"
  /// asked for.
  static const double _proseMaxWidth = 940;

  /// Breathing room on each side of the content column.
  static const double _horizontalPadding = 32;

  @override
  ConsumerState<DocumentReaderScreen> createState() =>
      _DocumentReaderScreenState();

  /// Pushes the reader over everything (including any open dialog).
  static Future<void> open(
    BuildContext context, {
    required String title,
    required String assetBase,
    String? onlineUrl,
    String? initialAnchor,
    DocumentationService service = const DocumentationService(),
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentReaderScreen(
          title: title,
          assetBase: assetBase,
          onlineUrl: onlineUrl,
          initialAnchor: initialAnchor,
          service: service,
        ),
      ),
    );
  }
}

class _DocumentReaderScreenState extends ConsumerState<DocumentReaderScreen> {
  // Shared by the Scrollbar and the SingleChildScrollView so the thumb is
  // bound to a real ScrollPosition. Without this, on desktop the Scrollbar
  // falls back to the PrimaryScrollController (which the scroll view does not
  // attach to there), and dragging throws "no ScrollPosition attached".
  final ScrollController _scrollController = ScrollController();

  // Find-in-page state.
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocus = FocusNode();

  /// A single key that follows the *active* match block, so scrolling to the
  /// current hit is just `ensureVisible` on its context.
  final GlobalKey _activeMatchKey = GlobalKey();
  bool _findVisible = false;
  String _query = '';
  int _activeMatch = 0;

  /// The bundled doc asset keys, loaded once. Decides whether an internal link
  /// opens in the reader (bundled) or in the browser (repo-only). Null until the
  /// first load resolves; [_handleLink] loads on demand if a tap beats it.
  Set<String>? _bundledAssets;

  /// A single key that follows the block an anchor link points at, so scrolling
  /// to a section is `ensureVisible` on its context — the same moving-key trick
  /// as [_activeMatchKey]. [_anchorBlockIndex] is the block it currently marks
  /// (`-1` for none).
  final GlobalKey _anchorKey = GlobalKey();
  int _anchorBlockIndex = -1;

  /// Whether the one-shot [DocumentReaderScreen.initialAnchor] scroll has run,
  /// so a rebuild (find-bar keystroke, text-size nudge) does not re-jump.
  bool _didInitialAnchorScroll = false;

  /// The document loaded once per (asset, language), cached so a rebuild — every
  /// keystroke in the find bar, every text-size nudge — does not re-read the
  /// asset and flash the spinner.
  late Future<({String text, bool isBaseVersion})> _docFuture;
  String? _loadedLanguage;

  /// The current document text, captured when [_docFuture] resolves, so the
  /// find-bar handlers can recompute matches without awaiting a Future.
  String _docText = '';

  // Memoise the block-text split by source text: the parser runs once per
  // document, not once per keystroke.
  String? _blockTextsSource;
  List<String> _blockTexts = const [];

  @override
  void initState() {
    super.initState();
    // Warm the bundled-doc set so a link tap classifies without waiting on I/O.
    // A missing manifest (some minimal test bundles) is harmless: links then
    // simply fall through to the browser instead of navigating in-app.
    widget.service.bundledDocAssets().then((assets) {
      if (mounted) _bundledAssets = assets;
    }, onError: (Object _, StackTrace _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (language == _loadedLanguage) return;
    _loadedLanguage = language;
    _resetFind();
    _docFuture = widget.service.loadDetailed(widget.assetBase, language);
    _docText = '';
    _docFuture.then((loaded) {
      if (mounted) _docText = loaded.text;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _findController.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final languageCode = Localizations.localeOf(context).languageCode;
    final scale = ref.watch(
      settingsProvider.select((s) => s.docReaderTextScale),
    );

    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(widget.title)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: l10n.d('Zoeken in document'),
            isSelected: _findVisible,
            onPressed: _toggleFind,
          ),
          ..._textSizeActions(context, ref, l10n, scale),
          if (widget.onlineUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: l10n.d('Online openen'),
              onPressed: () => openExternalUrl(widget.onlineUrl!),
            ),
        ],
      ),
      body: FutureBuilder<({String text, bool isBaseVersion})>(
        future: _docFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final loaded = snap.data;
          if (snap.hasError || loaded == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.d('Dit document kon niet worden geladen.')),
              ),
            );
          }
          final text = loaded.text;
          // One-shot landing on the anchor an internal link carried in, run
          // after this frame so the target heading's key is attached. Guarded so
          // a find-bar keystroke or text-size nudge does not re-jump.
          final anchor = widget.initialAnchor;
          if (anchor != null && !_didInitialAnchorScroll) {
            _didInitialAnchorScroll = true;
            // We are inside build, so mark the block directly (no setState); the
            // _body below reads _anchorBlockIndex this same frame, then we scroll
            // after it has attached the key.
            final index = DocumentMarkdownView.headingBlockIndex(text, anchor);
            if (index >= 0) {
              _anchorBlockIndex = index;
              _ensureAnchorVisible();
            }
          }
          // De titel van dit document staat in 32 talen, de inhoud vaak in één.
          // Dat verschil hoort de lezer te horen vóór hij begint te lezen, niet
          // halverwege te ontdekken (#626). De basis is Engels, dus de melding
          // hoort bij iederéén die géén Engels leest en op de basis terugvalt —
          // vóór #1181 stond hier `!= 'nl'`, wat juist de Nederlandse lezer
          // (die óók de Engelse basis kreeg) de melding onthield.
          final showNotice =
              loaded.isBaseVersion &&
              languageCode != DocumentationService.baseLanguage;
          // Which blocks contain the query, and which of those is the active
          // hit. Computed here (text in hand) so both the find bar's counter and
          // the document's highlight see the same result.
          final matches = _matchesIn(text, _findVisible ? _query : '');
          final activeBlock = matches.isEmpty
              ? -1
              : matches[_activeMatch.clamp(0, matches.length - 1)];
          return Column(
            children: [
              if (showNotice) _languageNotice(context, l10n),
              if (_findVisible) _findBar(context, l10n, matches.length),
              Expanded(child: _body(context, text, scale, activeBlock)),
            ],
          );
        },
      ),
    );
  }

  /// The find-in-page bar: a query field, a `position / total` counter, and
  /// previous/next/close. Enter jumps to the next hit.
  Widget _findBar(BuildContext context, AppLocalizations l10n, int matchCount) {
    final scheme = Theme.of(context).colorScheme;
    final hasMatches = matchCount > 0;
    final queryEmpty = _query.trim().isEmpty;
    final position = hasMatches ? (_activeMatch % matchCount) + 1 : 0;
    final counter = queryEmpty
        ? ''
        : (hasMatches ? '$position / $matchCount' : l10n.d('Geen treffers'));
    return Material(
      elevation: 1,
      child: Container(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _findController,
                focusNode: _findFocus,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: l10n.d('Zoeken in dit document…'),
                ),
                onChanged: _onFindChanged,
                onSubmitted: (_) => _step(1),
              ),
            ),
            if (counter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  counter,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              iconSize: 20,
              tooltip: l10n.d('Vorige treffer'),
              onPressed: hasMatches ? () => _step(-1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              iconSize: 20,
              tooltip: l10n.d('Volgende treffer'),
              onPressed: hasMatches ? () => _step(1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              iconSize: 20,
              tooltip: l10n.d('Zoeken sluiten'),
              onPressed: _toggleFind,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleFind() {
    setState(() {
      _findVisible = !_findVisible;
      if (!_findVisible) _resetFind();
    });
    if (_findVisible) _findFocus.requestFocus();
  }

  void _resetFind() {
    _findController.clear();
    _query = '';
    _activeMatch = 0;
  }

  void _onFindChanged(String value) {
    // A new query starts from the first hit again.
    setState(() {
      _query = value;
      _activeMatch = 0;
    });
    _scrollToActive();
  }

  void _step(int delta) {
    final matches = _matchesIn(_docText, _query);
    if (matches.isEmpty) return;
    // Dart's `%` keeps the result non-negative for a positive divisor, so
    // stepping back from the first hit wraps to the last.
    setState(() => _activeMatch = (_activeMatch + delta) % matches.length);
    _scrollToActive();
  }

  /// Bring the active-match block into view after the frame that re-tinted it,
  /// so [_activeMatchKey] is already attached to the new block.
  void _scrollToActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeMatchKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Routes a tapped link: an internal document link navigates (a bundled doc
  /// opens in a new reader, a repo-only doc opens online), an `#anchor` scrolls
  /// within this document, and anything external opens in the browser. This is
  /// why the reader no longer hands every href to [openExternalUrl] — a relative
  /// `.md` link would become `https://FILE_FORMAT.md` and die at the host gate.
  Future<void> _handleLink(String href) async {
    var bundled = _bundledAssets;
    if (bundled == null) {
      try {
        bundled = await widget.service.bundledDocAssets();
      } catch (e) {
        // No manifest → no in-app navigation; links still open in the browser.
        logWarning('doc reader: bundled asset list failed', e);
        bundled = const <String>{};
      }
      if (!mounted) return;
      _bundledAssets = bundled;
    }
    final target = resolveDocLink(
      currentAsset: widget.assetBase,
      href: href,
      bundledAssets: bundled,
    );
    switch (target) {
      case null:
        return;
      case ExternalDocLink(:final url):
        await openExternalUrl(url);
      case SameDocAnchorLink(:final anchor):
        _scrollToAnchor(anchor);
      case InAppDocLink():
        await _openDocument(target);
    }
  }

  /// Opens a bundled document in a new reader pushed over this one, so the back
  /// button walks the reading trail. The title is the target's own first
  /// heading — always right for the document that is actually shown, with the
  /// file name as a bare fallback.
  Future<void> _openDocument(InAppDocLink target) async {
    final language = Localizations.localeOf(context).languageCode;
    final text = await widget.service.load(target.assetBase, language);
    if (!mounted) return;
    final title =
        firstHeadingText(text) ??
        target.assetBase.split('/').last.replaceAll('.md', '');
    await DocumentReaderScreen.open(
      context,
      title: title,
      assetBase: target.assetBase,
      initialAnchor: target.anchor,
      service: widget.service,
    );
  }

  /// Points [_anchorKey] at the heading named by [slug] and scrolls to it. Marks
  /// the block via setState so the key attaches this frame, then scrolls after
  /// it — the same path find-in-page uses, which is why it lands reliably. A
  /// no-op when the slug names no heading in [_docText].
  void _scrollToAnchor(String slug) {
    final index = DocumentMarkdownView.headingBlockIndex(_docText, slug);
    if (index < 0) return;
    setState(() => _anchorBlockIndex = index);
    _ensureAnchorVisible();
  }

  /// Brings [_anchorKey]'s block into view after the frame that attached it.
  void _ensureAnchorVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchorKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Absolute indices of the blocks whose text contains [query]
  /// (case-insensitive), in document order. Empty for a blank query.
  List<int> _matchesIn(String text, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final texts = _textsFor(text);
    return [
      for (var i = 0; i < texts.length; i++)
        if (texts[i].toLowerCase().contains(q)) i,
    ];
  }

  /// The per-block search text for [text], parsed once and memoised.
  List<String> _textsFor(String text) {
    if (text != _blockTextsSource) {
      _blockTexts = DocumentMarkdownView.blockTexts(text);
      _blockTextsSource = text;
    }
    return _blockTexts;
  }

  /// The subtle "smaller / larger" pair, each disabled at its bound.
  List<Widget> _textSizeActions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    double scale,
  ) {
    void nudge(double delta) => ref
        .read(settingsProvider.notifier)
        .setDocReaderTextScale(scale + delta);

    const step = SettingsNotifier.docReaderTextScaleStep;
    final canShrink = scale > SettingsNotifier.docReaderTextScaleMin + 1e-6;
    final canGrow = scale < SettingsNotifier.docReaderTextScaleMax - 1e-6;
    return [
      IconButton(
        icon: const Icon(Icons.text_decrease),
        iconSize: 20,
        tooltip: l10n.d('Tekst kleiner'),
        onPressed: canShrink ? () => nudge(-step) : null,
      ),
      IconButton(
        icon: const Icon(Icons.text_increase),
        iconSize: 20,
        tooltip: l10n.d('Tekst groter'),
        onPressed: canGrow ? () => nudge(step) : null,
      ),
    ];
  }

  /// Eén regel boven een document dat alleen in de basisversie bestaat.
  ///
  /// Bewust een melding en geen waarschuwing: er is niets misgegaan, er is
  /// alleen iets er nog niet. De kleinste eerlijke oplossing voor #626 — 19.382
  /// regels vertalen is dat niet, maar zwijgen ook niet, want de app wekt de
  /// verwachting zélf met een vertaalde titel.
  Widget _languageNotice(BuildContext context, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      color: AppTheme.infoBg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.translate, size: 16, color: AppTheme.slate600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.d('Dit document bestaat alleen in het Engels.'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    String markdown,
    double scale,
    int activeBlock,
  ) {
    final media = MediaQuery.of(context);
    // The reader's own scale multiplies whatever the OS and the app-wide
    // interface scale already ask for, so all document text (tables included)
    // grows and shrinks together.
    final scaled = media.copyWith(
      textScaler: TextScaler.linear(media.textScaler.scale(1.0) * scale),
    );

    return MediaQuery(
      data: scaled,
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          // Fill the full available width (no centred, capped column): tables,
          // code and diagrams get the whole measure, while prose is held to a
          // readable line length by the bound below.
          padding: const EdgeInsets.symmetric(
            horizontal: DocumentReaderScreen._horizontalPadding,
            vertical: 28,
          ),
          // Force the document column to the full available width (a vertical
          // scroll otherwise hands its child a loose width, so the column would
          // shrink-wrap to its widest block and leave the rest of the window
          // unused). Prose stays bounded and left-aligned within it; wide
          // tables, code and diagrams now get the whole measure.
          child: SizedBox(
            width: double.infinity,
            // SelectionArea makes the whole document selectable/copyable while
            // keeping links tappable.
            child: SelectionArea(
              child: DocumentMarkdownView(
                markdown,
                onTapLink: _handleLink,
                maxTextWidth: DocumentReaderScreen._proseMaxWidth,
                searchTerm: _findVisible ? _query : null,
                activeMatchBlockIndex: activeBlock,
                activeMatchKey: _activeMatchKey,
                anchorBlockIndex: _anchorBlockIndex,
                anchorKey: _anchorKey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
