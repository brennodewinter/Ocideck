import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../utils/deck_text_search.dart';
import 'deck_search_target.dart';
import 'deck_search_highlight.dart';
import 'editor_text_controller.dart';
import 'markdown_find_bar.dart';
import '../markdown_editor/markdown_editor.dart';
import '../panels/preview_panel.dart';
import '../reader/document_search_overlay.dart';

/// Niet-blokkerend zoeken laat de huidige editor staan en behoudt zoekfocus.
class DeckSearchWorkspace extends ConsumerStatefulWidget {
  const DeckSearchWorkspace({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DeckSearchWorkspace> createState() =>
      _DeckSearchWorkspaceState();
}

class _DeckSearchWorkspaceState extends ConsumerState<DeckSearchWorkspace> {
  final _editorKey = GlobalKey();
  String _query = '';
  bool _visible = false;
  bool _caseSensitive = false;
  bool _includeNotes = false;
  int _index = -1;
  int _signal = 0;
  DeckTextMatch? _target;
  List<DeckTextMatch> _matches = const [];
  Deck? _searchedDeck;
  FocusNode? _previousFocus;
  FocusNode? _targetFocus;
  int _openSignal = 0;
  int _wrapDirection = 0;

  void _search() {
    final deck = ref.read(deckProvider).deck;
    final identity = _target?.identity;
    _matches = deck == null
        ? const []
        : searchDeckText(
            deck,
            _query,
            caseSensitive: _caseSensitive,
            includeNotes: _includeNotes,
          );
    _searchedDeck = deck;
    _index = identity == null
        ? -1
        : _matches.indexWhere((m) => m.identity == identity);
    _target = _index < 0 ? null : _matches[_index];
  }

  void _changeQuery(String query) {
    setState(() {
      _query = query;
      _target = null;
      _search();
    });
  }

  void _navigate(int direction) {
    if (_matches.isEmpty) return;
    _wrapDirection =
        _index >= 0 &&
            (_index + direction < 0 || _index + direction >= _matches.length)
        ? direction
        : 0;
    _choose(
      _index < 0
          ? (direction > 0 ? 0 : _matches.length - 1)
          : (_index + direction) % _matches.length,
    );
  }

  void _choose(int index) {
    final match = _matches[index];
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final slideIndex = deck.slides.indexWhere((s) => s.id == match.slideId);
    if (slideIndex < 0) return;
    ref.read(editorProvider.notifier).select(slideIndex);
    if (match.isNotes) {
      final page = int.tryParse(match.fieldId.split('.').last) ?? 0;
      ref.read(richTextPreviewPageProvider.notifier).state = page;
    }
    setState(() {
      _index = index;
      _target = match;
      _signal++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealEditable(match));
  }

  void _revealEditable(DeckTextMatch match) {
    if (!mounted || _target != match) return;
    void visit(Element element) {
      if (element.widget case Offstage(offstage: true)) return;
      if (element.widget case EditableText(:final controller)) {
        if ((controller is EditorTextController
                ? controller.searchFieldId
                : SearchFieldAnchor.fieldOf(element)) ==
            match.fieldId) {
          final currentMatches = match.text == controller.text;
          if (!currentMatches || match.range.end > controller.text.length) {
            return;
          }
          controller.selection = TextSelection(
            baseOffset: match.range.start,
            extentOffset: match.range.end,
          );
          final state = (element as StatefulElement).state as EditableTextState;
          _targetFocus = state.widget.focusNode;
          if (element.findAncestorWidgetOfExactType<ExcludeDocumentSearch>() ==
              null) {
            Scrollable.ensureVisible(element, alignment: 0.25);
            state.bringIntoView(TextPosition(offset: match.range.end));
          }
          return;
        }
      }
      if (element.widget case RichText(:final text)) {
        if (SearchFieldAnchor.fieldOf(element) == match.fieldId &&
            text.toPlainText().contains(match.text)) {
          Scrollable.ensureVisible(element, alignment: 0.25);
        }
      }
      if (element.widget case MarkdownNotesEditor(:final controller)) {
        if ((controller is EditorTextController
                ? controller.searchFieldId
                : SearchFieldAnchor.fieldOf(element)) ==
            match.fieldId) {
          Scrollable.ensureVisible(element, alignment: 0.25);
        }
      }
      element.visitChildren(visit);
    }

    _editorKey.currentContext?.visitChildElements(visit);
  }

  void _focusEditor() {
    FocusNode? focus;
    void visit(Element element) {
      if (element.widget case Offstage(offstage: true)) return;
      if (element.widget case EditableText(:final focusNode)) {
        focus ??= focusNode;
      }
      if (focus == null) element.visitChildren(visit);
    }

    _editorKey.currentContext?.visitChildElements(visit);
    focus?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(editorProvider.select((s) => s.markdownFindRequestId), (
      _,
      next,
    ) {
      if (ref.read(editorProvider).mode == EditorMode.visual) {
        _previousFocus = FocusManager.instance.primaryFocus;
        setState(() {
          _visible = true;
          _openSignal++;
        });
      }
    });
    final deck = ref.watch(deckProvider.select((s) => s.deck));
    if (!identical(deck, _searchedDeck)) _search();
    final l10n = context.l10n;
    final selected = ref.watch(editorProvider.select((s) => s.selectedIndex));
    final activeTarget =
        deck != null &&
            selected >= 0 &&
            selected < deck.slides.length &&
            deck.slides[selected].id == _target?.slideId
        ? _target
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_visible &&
            ref.watch(editorProvider.select((s) => s.mode)) ==
                EditorMode.visual) ...[
          MarkdownFindBar(
            key: ValueKey(_openSignal),
            resultContexts: [
              for (final match in _matches)
                '${l10n.d('Dia')} ${match.slideIndex + 1} · ${l10n.d(match.fieldLabel)} — ${match.context}',
            ],
            onSelectMatch: _choose,
            wrapDirection: _wrapDirection,
            query: _query,
            replace: '',
            caseSensitive: _caseSensitive,
            showReplace: false,
            matchCount: _matches.length,
            matchIndex: _index,
            onQueryChanged: _changeQuery,
            onReplaceChanged: (_) {},
            onCaseSensitiveChanged: (value) => setState(() {
              _caseSensitive = value;
              _search();
            }),
            onNext: () => _navigate(1),
            onPrevious: () => _navigate(-1),
            onReplaceCurrent: () {},
            onReplaceAll: () {},
            onClose: () {
              setState(() {
                _visible = false;
                _target = null;
              });
              final focus = _targetFocus?.context != null
                  ? _targetFocus
                  : _previousFocus;
              if (focus?.context != null) {
                focus!.requestFocus();
              } else {
                _focusEditor();
              }
            },
          ),
          CheckboxListTile(
            dense: true,
            title: Text(l10n.d('Ook in sprekersnotities')),
            value: _includeNotes,
            onChanged: (value) => setState(() {
              _includeNotes = value ?? false;
              _search();
            }),
          ),
        ],
        Expanded(
          child: DeckSearchTarget(
            match: activeTarget,
            signal: _signal,
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                if (_target != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }
                return false;
              },
              child: DeckSearchHighlight(
                match: activeTarget,
                child: KeyedSubtree(key: _editorKey, child: widget.child),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
