import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/markdown_outline.dart';
import '../../models/markdown_source_document.dart';
import '../../models/markdown_writing_suggestion.dart';
import '../../models/markdown_validation.dart';
import '../../services/markdown_validator.dart';
import '../../state/editor_provider.dart';
import '../../utils/text_search.dart';
import '../markdown_editor/markdown_editor_actions.dart';
import '../markdown_editor/markdown_editor_theme.dart';
import '../markdown_editor/markdown_editor_toolbar.dart';
import 'markdown_find_bar.dart';
import 'markdown_command_palette.dart';
import 'markdown_smart_input_formatter.dart';
import 'markdown_source_controller.dart';
import '../../theme/app_theme.dart';

// De kantlijn en de gekleurde bevindingsbanden. Een part omdat ze op de private
// regelhoogte van de editor-state leunen — zie het bestand zelf.
part 'markdown_deck_editor_gutter.dart';

class MarkdownDeckEditor extends ConsumerStatefulWidget {
  final String initialContent;
  final String? baselineContent;
  final bool Function(String) onApply;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<int>? onActiveSlideChanged;
  final bool parseError;
  final VoidCallback onExitMarkdown;

  /// Of de editor de hele presentatie of alleen de actieve slide toont.
  final MarkdownScope scope;

  /// 1-gebaseerd nummer van de actieve slide (voor het per-slide label).
  final int slideNumber;

  /// Totaal aantal slides (voor het per-slide label).
  final int slideCount;

  /// Wissel de omvang tussen hele presentatie en actieve slide.
  final ValueChanged<MarkdownScope> onScopeChanged;

  const MarkdownDeckEditor({
    super.key,
    required this.initialContent,
    this.baselineContent,
    required this.onApply,
    this.onDraftChanged,
    this.onActiveSlideChanged,
    required this.parseError,
    required this.onExitMarkdown,
    this.scope = MarkdownScope.deck,
    this.slideNumber = 1,
    this.slideCount = 1,
    required this.onScopeChanged,
  });

  bool get isSlideScope => scope == MarkdownScope.slide;

  @override
  ConsumerState<MarkdownDeckEditor> createState() => _MarkdownDeckEditorState();
}

class _MarkdownDeckEditorState extends ConsumerState<MarkdownDeckEditor> {
  static const _lineHeight = 19.5;

  /// Top inset of the text area; the finding bands and the gutter share it so
  /// every line's band lines up with its text and its line number.
  static const _editorTopPadding = 16.0;

  late final MarkdownSourceController _ctrl;
  late MarkdownSourceDocument _sourceDocument;
  late List<MarkdownWritingSuggestion> _writingSuggestions;
  late String _observedText;
  late final ScrollController _scrollController;
  late final FocusNode _editorFocusNode;
  late final UndoHistoryController _undoController;
  final _validator = MarkdownValidator();
  Timer? _validationTimer;
  late String _baselineContent;
  MarkdownValidationResult? _validation;
  bool _validationPending = false;
  bool _syncingExternalContent = false;
  int? _lastReportedSlide;
  bool _showIssues = false;

  bool _findVisible = false;
  bool _showReplace = false;
  String _findQuery = '';
  String _replaceText = '';
  bool _caseSensitive = false;
  int _matchIndex = -1;
  List<TextMatchRange> _matches = const [];

  @override
  void initState() {
    super.initState();
    _ctrl = MarkdownSourceController(text: widget.initialContent);
    _sourceDocument = MarkdownSourceDocument.parse(widget.initialContent);
    _writingSuggestions = inspectMarkdownWriting(widget.initialContent);
    _observedText = widget.initialContent;
    _baselineContent = widget.baselineContent ?? widget.initialContent;
    _ctrl.addListener(_onDocumentChanged);
    _scrollController = ScrollController();
    _editorFocusNode = FocusNode();
    _undoController = UndoHistoryController()..addListener(_onUndoChanged);
    _scheduleValidation();
  }

  @override
  void didUpdateWidget(MarkdownDeckEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Bij het wisselen van omvang (hele presentatie ↔ slide) of van de actieve
    // slide levert het paneel verse [initialContent]. De widget blijft bestaan
    // (zodat de toggle animeert), dus laden we de nieuwe inhoud hier in en
    // ruimen we validatie/zoekstaat op.
    //
    // Maar niet over ongetoepast tikwerk heen. Deze editor is een wachtruimte:
    // niets bereikt het deck vóór "Toepassen". Het paneel bérekent
    // [initialContent] echter opnieuw bij elke opbouw, dus élke wijziging elders
    // — een dia toevoegen, dupliceren, overslaan, één klik in de lijst ernaast —
    // leverde verse inhoud op en gooide het getypte werk weg. Zonder
    // waarschuwing, en ongedaan maken kwam er niet bij, want het had het deck
    // nooit bereikt.
    //
    // Staat er iets ongetoepasts, dan wint dat. De inhoud loopt dan achter op
    // het deck, maar dat is precies wat een wachtruimte hoort te doen: bij
    // "Toepassen" schrijft hij toch het geheel.
    if (widget.initialContent != oldWidget.initialContent) {
      if (_ctrl.text != oldWidget.initialContent) return;
      _syncingExternalContent = true;
      _ctrl.text = widget.initialContent;
      _sourceDocument = _sourceDocument.reparse(widget.initialContent);
      _writingSuggestions = inspectMarkdownWriting(widget.initialContent);
      _observedText = widget.initialContent;
      _baselineContent = widget.baselineContent ?? widget.initialContent;
      _syncingExternalContent = false;
      setState(() {
        _validation = null;
        _showIssues = false;
        _matches = const [];
        _matchIndex = -1;
      });
    }
    if (widget.scope == MarkdownScope.deck &&
        widget.slideNumber != oldWidget.slideNumber) {
      MarkdownSourceBlock? target;
      for (final block in _sourceDocument.blocks) {
        if (block.slideNumber == widget.slideNumber) {
          target = block;
          break;
        }
      }
      if (target != null) {
        final targetStart = target.start;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToRange(TextMatchRange(targetStart, targetStart));
        });
      }
    }
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _ctrl.removeListener(_onDocumentChanged);
    _ctrl.dispose();
    _scrollController.dispose();
    _editorFocusNode.dispose();
    _undoController
      ..removeListener(_onUndoChanged)
      ..dispose();
    super.dispose();
  }

  void _onUndoChanged() {
    if (mounted) setState(() {});
  }

  bool get _isDirty => _ctrl.text != _baselineContent;

  void _onDocumentChanged() {
    if (_syncingExternalContent) return;
    if (_ctrl.text == _observedText) {
      _reportActiveSourceSlide();
      if (mounted) setState(() {});
      return;
    }
    _observedText = _ctrl.text;
    _sourceDocument = _sourceDocument.reparse(_ctrl.text);
    _writingSuggestions = inspectMarkdownWriting(_ctrl.text);
    widget.onDraftChanged?.call(_ctrl.text);
    _reportActiveSourceSlide();
    _validation = null;
    _scheduleValidation();
    if (_findVisible && _findQuery.isNotEmpty) {
      final matches = findAllMatches(
        _ctrl.text,
        _findQuery,
        caseSensitive: _caseSensitive,
      );
      _matches = matches;
      _matchIndex = matches.isEmpty
          ? -1
          : _matchIndex.clamp(0, matches.length - 1);
      _syncSearchHighlights();
    }
    if (mounted) setState(() {});
  }

  void _reportActiveSourceSlide() {
    if (widget.scope != MarkdownScope.deck ||
        widget.onActiveSlideChanged == null) {
      return;
    }
    final block = _sourceDocument.blockAt(_ctrl.selection.extentOffset);
    if (block == null || block.slideNumber == _lastReportedSlide) return;
    _lastReportedSlide = block.slideNumber;
    widget.onActiveSlideChanged!(block.slideNumber - 1);
  }

  void _scheduleValidation() {
    _validationTimer?.cancel();
    _validationPending = true;
    _validationTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final result = _validator.validate(_ctrl.text);
      setState(() {
        _validation = result;
        _validationPending = false;
      });
    });
  }

  void _openFind({required bool showReplace}) {
    setState(() {
      _findVisible = true;
      _showReplace = showReplace;
    });
    _recountMatches(selectFirst: true);
  }

  void _closeFind() {
    setState(() {
      _findVisible = false;
      _matchIndex = -1;
      _matches = const [];
    });
    _syncSearchHighlights();
  }

  void _syncSearchHighlights() {
    _ctrl.showSearchMatches(_findVisible ? _matches : const [], _matchIndex);
  }

  void _recountMatches({bool selectFirst = false}) {
    final matches = findAllMatches(
      _ctrl.text,
      _findQuery,
      caseSensitive: _caseSensitive,
    );
    setState(() {
      _matches = matches;
      if (matches.isEmpty) {
        _matchIndex = -1;
      } else if (selectFirst ||
          _matchIndex < 0 ||
          _matchIndex >= matches.length) {
        _matchIndex = 0;
        _jumpToRange(matches[0]);
      } else {
        _jumpToRange(matches[_matchIndex]);
      }
    });
    _syncSearchHighlights();
  }

  void _goToNextMatch() {
    if (_matches.isEmpty) return;
    final next = nextMatchIndex(_matchIndex, _matches.length);
    setState(() => _matchIndex = next);
    _syncSearchHighlights();
    _jumpToRange(_matches[next]);
  }

  void _goToPreviousMatch() {
    if (_matches.isEmpty) return;
    final prev = previousMatchIndex(_matchIndex, _matches.length);
    setState(() => _matchIndex = prev);
    _syncSearchHighlights();
    _jumpToRange(_matches[prev]);
  }

  void _replaceCurrentMatch() {
    if (_matchIndex < 0 || _matchIndex >= _matches.length) return;
    final match = _matches[_matchIndex];
    final updated = replaceRange(_ctrl.text, match, _replaceText);
    _ctrl.text = updated;
    _recountMatches(selectFirst: false);
    if (_matches.isNotEmpty) {
      final idx = _matchIndex.clamp(0, _matches.length - 1);
      setState(() => _matchIndex = idx);
      _jumpToRange(_matches[idx]);
    }
  }

  void _replaceAllMatches() {
    if (_findQuery.isEmpty) return;
    final result = replaceAllInText(
      _ctrl.text,
      _findQuery,
      _replaceText,
      caseSensitive: _caseSensitive,
    );
    _ctrl.text = result.text;
    setState(() {
      _matches = const [];
      _matchIndex = -1;
    });
    _syncSearchHighlights();
  }

  MarkdownValidationResult _runValidation() {
    _validationTimer?.cancel();
    final result = _validator.validate(_ctrl.text);
    setState(() {
      _validation = result;
      _validationPending = false;
      _showIssues = result.hasIssues;
    });
    return result;
  }

  VoidCallback? _quickFixFor(MarkdownValidationIssue issue) {
    final message = issue.message;
    final suffix =
        message.contains('Codeblok is niet afgesloten') ||
            message.contains('-blok is niet afgesloten')
        ? '\n```\n'
        : message.contains('HTML-commentaar is niet afgesloten')
        ? '-->'
        : null;
    if (suffix == null) return null;
    return () {
      _ctrl.value = TextEditingValue(
        text: '${_ctrl.text}$suffix',
        selection: TextSelection.collapsed(
          offset: _ctrl.text.length + suffix.length,
        ),
      );
      _runValidation();
      _editorFocusNode.requestFocus();
    };
  }

  void _jumpToLine(int line) {
    final lines = _ctrl.text.split('\n');
    final index = (line - 1).clamp(0, lines.length - 1);
    var offset = 0;
    for (var i = 0; i < index; i++) {
      offset += lines[i].length + 1;
    }
    _jumpToRange(TextMatchRange(offset, offset + lines[index].length));
  }

  void _jumpToRange(TextMatchRange range) {
    _ctrl.selection = TextSelection(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    final textBefore = _ctrl.text.substring(0, range.start);
    final line = '\n'.allMatches(textBefore).length;
    final target = line * _lineHeight;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<bool> _confirmApplyWithIssues(
    BuildContext context,
    MarkdownValidationResult result,
  ) async {
    final choice = await showDialog<_ApplyChoiceResult>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          title: Text(l10n.d('Syntaxproblemen gevonden')),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${l10n.d('De markdown bevat')} ${result.errorCount} '
                  '${l10n.d('fout(en) en')} ${result.warningCount} '
                  '${l10n.d('waarschuwing(en). Slides kunnen daardoor verkeerd worden ingelezen.')}',
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final issue in result.issues)
                          _IssueTile(
                            issue: issue,
                            onTap: () => Navigator.pop(
                              ctx,
                              _ApplyChoiceResult(_ApplyChoice.edit, issue.line),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                const _ApplyChoiceResult(_ApplyChoice.edit),
              ),
              child: Text(l10n.d('Terug naar editor')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                const _ApplyChoiceResult(_ApplyChoice.cancel),
              ),
              child: Text(l10n.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                ctx,
                const _ApplyChoiceResult(_ApplyChoice.applyAnyway),
              ),
              child: Text(l10n.d('Toch toepassen')),
            ),
          ],
        );
      },
    );

    if (choice?.choice == _ApplyChoice.edit && choice?.focusLine != null) {
      _jumpToLine(choice!.focusLine!);
    }
    return choice?.choice == _ApplyChoice.applyAnyway;
  }

  Future<void> _applyMarkdown() async {
    final result = _runValidation();
    if (result.hasIssues) {
      final proceed = await _confirmApplyWithIssues(context, result);
      if (!proceed) return;
    }
    final ok = widget.onApply(_ctrl.text);
    if (ok) {
      _baselineContent = _ctrl.text;
      widget.onExitMarkdown();
    }
  }

  Future<void> _requestExitMarkdown() async {
    if (!_isDirty) {
      widget.onExitMarkdown();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          title: Text(l10n.d('Niet-toegepaste wijzigingen')),
          content: Text(
            l10n.d(
              'Je wijzigingen zijn nog niet toegepast. Wil je ze verwerpen?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.d('Doorgaan met bewerken')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.d('Wijzigingen verwerpen')),
            ),
          ],
        );
      },
    );
    if (discard == true && mounted) widget.onExitMarkdown();
  }

  void _formatSelection(String before, String after) {
    MarkdownEditorActions.wrapSelection(
      _ctrl,
      before: before,
      after: after,
      placeholder: 'tekst',
    );
  }

  Future<void> _openCommandPalette() async {
    final command = await showMarkdownCommandPalette(context);
    if (command == null || !mounted) return;
    switch (command) {
      case MarkdownCommand.heading1:
        MarkdownEditorActions.toggleHeading(_ctrl, 1);
      case MarkdownCommand.heading2:
        MarkdownEditorActions.toggleHeading(_ctrl, 2);
      case MarkdownCommand.heading3:
        MarkdownEditorActions.toggleHeading(_ctrl, 3);
      case MarkdownCommand.bulletList:
        MarkdownEditorActions.toggleBullet(_ctrl);
      case MarkdownCommand.numberedList:
        MarkdownEditorActions.toggleNumbered(_ctrl);
      case MarkdownCommand.task:
        MarkdownEditorActions.insertTask(_ctrl);
      case MarkdownCommand.quote:
        MarkdownEditorActions.toggleQuote(_ctrl);
      case MarkdownCommand.link:
        MarkdownEditorActions.insertLink(_ctrl);
      case MarkdownCommand.image:
        MarkdownEditorActions.insertImage(_ctrl);
      case MarkdownCommand.table:
        MarkdownEditorActions.insertTable(_ctrl);
      case MarkdownCommand.codeBlock:
        MarkdownEditorActions.insertCodeBlock(_ctrl);
    }
    _editorFocusNode.requestFocus();
  }

  void _requestScopeChange(MarkdownScope scope) {
    if (scope == widget.scope) return;
    if (_isDirty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d(
              'Pas de huidige wijzigingen eerst toe of verwerp ze voordat je van bereik wisselt.',
            ),
          ),
        ),
      );
      return;
    }
    widget.onScopeChanged(scope);
  }

  Future<void> _showSourceDiff() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        Widget sourcePane(String label, String source) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.slate50,
                    border: Border.all(color: AppTheme.slate200),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(10),
                    child: SelectableText(
                      source,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        return AlertDialog(
          title: Text(l10n.d('Wijzigingen vergelijken')),
          content: SizedBox(
            width: 900,
            height: 520,
            child: Row(
              children: [
                sourcePane(l10n.d('Toegepaste versie'), _baselineContent),
                const SizedBox(width: 12),
                sourcePane(l10n.d('Huidig concept'), _ctrl.text),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.t('close')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showWritingSuggestions() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.d('Schrijftips')),
        content: SizedBox(
          width: 560,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _writingSuggestions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final suggestion = _writingSuggestions[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.tips_and_updates_outlined, size: 18),
                title: Text(suggestion.message),
                subtitle: Text('${ctx.l10n.d('Regel')} ${suggestion.line}'),
                onTap: () {
                  Navigator.pop(ctx);
                  _jumpToLine(suggestion.line);
                  _editorFocusNode.requestFocus();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.t('close')),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleEscape(FocusNode node, KeyEvent event) {
    if (!_findVisible) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closeFind();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EditorState>(editorProvider, (previous, next) {
      if (previous?.markdownFindRequestId != next.markdownFindRequestId &&
          next.markdownFindRequestId > 0) {
        _openFind(showReplace: next.markdownFindShowReplace);
      }
    });

    final l10n = context.l10n;
    final lineCount = '\n'.allMatches(_ctrl.text).length + 1;
    final validationIssues =
        _validation?.issues ?? const <MarkdownValidationIssue>[];
    final issueLines = <int, MarkdownValidationSeverity>{
      for (final issue in validationIssues) issue.line: issue.severity,
    };

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _openFind(showReplace: false),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _openFind(showReplace: false),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            _openFind(showReplace: true),
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () =>
            _openFind(showReplace: true),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            _formatSelection('**', '**'),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            _formatSelection('**', '**'),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            _formatSelection('*', '*'),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
            _formatSelection('*', '*'),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            MarkdownEditorActions.insertLink(_ctrl),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            MarkdownEditorActions.insertLink(_ctrl),
        const SingleActivator(LogicalKeyboardKey.space, control: true):
            _openCommandPalette,
        const SingleActivator(LogicalKeyboardKey.space, meta: true):
            _openCommandPalette,
        const SingleActivator(LogicalKeyboardKey.tab): () =>
            MarkdownEditorActions.indentSelection(_ctrl),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
            MarkdownEditorActions.outdentSelection(_ctrl),
      },
      child: Focus(
        onKeyEvent: _handleEscape,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _modeBanner(l10n),
            _formattingBar(),
            if (_validation != null)
              _ValidationSummaryBar(
                result: _validation!,
                expanded: _showIssues,
                onToggle: () => setState(() => _showIssues = !_showIssues),
                onJumpToLine: _jumpToLine,
                quickFixFor: _quickFixFor,
              ),
            if (widget.parseError)
              Container(
                color: AppTheme.dangerBg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 14,
                      color: AppTheme.dangerFg,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.d(
                          'Markdown kon niet worden verwerkt. Controleer de syntax.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.dangerFg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_findVisible)
              MarkdownFindBar(
                key: ValueKey('find-$_showReplace'),
                query: _findQuery,
                replace: _replaceText,
                caseSensitive: _caseSensitive,
                showReplace: _showReplace,
                matchCount: _matches.length,
                matchIndex: _matchIndex,
                onQueryChanged: (value) {
                  _findQuery = value;
                  _recountMatches(selectFirst: true);
                },
                onReplaceChanged: (value) =>
                    setState(() => _replaceText = value),
                onCaseSensitiveChanged: (value) {
                  _caseSensitive = value;
                  _recountMatches(selectFirst: false);
                },
                onNext: _goToNextMatch,
                onPrevious: _goToPreviousMatch,
                onReplaceCurrent: _replaceCurrentMatch,
                onReplaceAll: _replaceAllMatches,
                onClose: _closeFind,
              ),
            const Divider(height: 1),
            _editorArea(lineCount, issueLines),
          ],
        ),
      ),
    );
  }

  Widget _modeBanner(AppLocalizations l10n) {
    return Container(
      color: AppTheme.warnSurface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.code, size: 14, color: AppTheme.warningFg),
          const SizedBox(width: 8),
          Flexible(
            child: _MarkdownScopeToggle(
              scope: widget.scope,
              slideNumber: widget.slideNumber,
              slideCount: widget.slideCount,
              onChanged: _requestScopeChange,
            ),
          ),
          const Spacer(),
          _DocumentStatus(
            dirty: _isDirty,
            validationPending: _validationPending,
            validation: _validation,
            onPressed: _isDirty ? _showSourceDiff : null,
          ),
          const SizedBox(width: 6),
          _MarkdownOutlineButton(
            entries: _sourceDocument.outline,
            onSelected: _jumpToLine,
          ),
          IconButton(
            onPressed: _openCommandPalette,
            icon: const Icon(Icons.add_circle_outline, size: 16),
            tooltip: l10n.d('Invoegen of opmaken (Ctrl/Cmd+Spatie)'),
            visualDensity: VisualDensity.compact,
            color: AppTheme.warningFg,
          ),
          // Zoeken zat er al — op Ctrl/Cmd+F, en via het menu en de
          // opdrachtenbalk — maar nergens zichtbaar in de markdown-weergave
          // zelf. Zonder knop weet niemand dat het kan: "in markdown kan ik niet
          // zoeken" was de klacht, terwijl de balk er wél was. Een icoonknop en
          // geen tekstknop, want de kopregel is smal: het vergrootglas is een
          // vertrouwd zoek-signaal en de tooltip vertelt de rest.
          IconButton(
            onPressed: () => _openFind(showReplace: false),
            icon: const Icon(Icons.search, size: 16),
            tooltip: l10n.d('Zoeken'),
            visualDensity: VisualDensity.compact,
            color: AppTheme.warningFg,
          ),
          TextButton.icon(
            onPressed: _runValidation,
            icon: const Icon(Icons.rule, size: 16),
            label: Text(l10n.d('Controleren')),
          ),
          TextButton(
            onPressed: _applyMarkdown,
            child: Text(l10n.d('Toepassen')),
          ),
          TextButton(
            onPressed: _requestExitMarkdown,
            child: Text(l10n.t('cancel')),
          ),
        ],
      ),
    );
  }

  Widget _formattingBar() {
    final theme = MarkdownEditorTheme.editorPanel(
      text: AppTheme.ink,
      link: AppTheme.accentFg,
      accent: AppTheme.accentFg,
      codeBackground: AppTheme.slate100,
      border: AppTheme.slate200,
      fontSize: 13,
    );
    return ColoredBox(
      color: AppTheme.slate50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: _undoController.value.canUndo
                  ? _undoController.undo
                  : null,
              icon: const Icon(Icons.undo, size: 18),
              tooltip: context.l10n.d('Ongedaan maken'),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: _undoController.value.canRedo
                  ? _undoController.redo
                  : null,
              icon: const Icon(Icons.redo, size: 18),
              tooltip: context.l10n.d('Opnieuw'),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: MarkdownEditorToolbar(
                controller: _ctrl,
                focusNode: _editorFocusNode,
                theme: theme,
                compact: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorArea(
    int lineCount,
    Map<int, MarkdownValidationSeverity> issueLines,
  ) {
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LineNumberGutter(
                  scrollController: _scrollController,
                  lineCount: lineCount,
                  issueLines: issueLines,
                  onLineTap: _jumpToLine,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(color: AppTheme.slate50),
                      ),
                      Positioned.fill(
                        child: _IssueHighlightLayer(
                          scrollController: _scrollController,
                          issueLines: issueLines,
                          topPadding: _editorTopPadding,
                        ),
                      ),
                      Semantics(
                        label: context.l10n.d('Markdown-broneditor'),
                        textField: true,
                        child: TextField(
                          controller: _ctrl,
                          undoController: _undoController,
                          autocorrect: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          spellCheckConfiguration:
                              WidgetsBinding
                                  .instance
                                  .platformDispatcher
                                  .nativeSpellCheckServiceDefined
                              ? SpellCheckConfiguration(
                                  misspelledTextStyle: TextStyle(
                                    decoration: TextDecoration.underline,
                                    decorationStyle: TextDecorationStyle.wavy,
                                    decorationColor: AppTheme.dangerFg,
                                  ),
                                )
                              : const SpellCheckConfiguration.disabled(),
                          focusNode: _editorFocusNode,
                          scrollController: _scrollController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.5,
                          ),
                          inputFormatters: const [
                            MarkdownSmartInputFormatter(),
                          ],
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.fromLTRB(
                              8,
                              _editorTopPadding,
                              16,
                              16,
                            ),
                            border: InputBorder.none,
                            filled: true,
                            fillColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _MarkdownSourceStatusBar(
            text: _ctrl.text,
            selection: _ctrl.selection,
            slideNumber: _sourceDocument
                .blockAt(_ctrl.selection.extentOffset)
                ?.slideNumber,
            writingSuggestionCount: _writingSuggestions.length,
            onWritingSuggestions: _writingSuggestions.isEmpty
                ? null
                : _showWritingSuggestions,
          ),
        ],
      ),
    );
  }
}

class _MarkdownSourceStatusBar extends StatelessWidget {
  final String text;
  final TextSelection selection;
  final int? slideNumber;
  final int writingSuggestionCount;
  final VoidCallback? onWritingSuggestions;

  const _MarkdownSourceStatusBar({
    required this.text,
    required this.selection,
    required this.slideNumber,
    required this.writingSuggestionCount,
    required this.onWritingSuggestions,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final offset = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : 0;
    final before = text.substring(0, offset);
    final line = '\n'.allMatches(before).length + 1;
    final lastBreak = before.lastIndexOf('\n');
    final column = offset - lastBreak;
    final plain = text
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
        .replaceAll(RegExp(r'!?\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[`*_#>|~-]+'), ' ');
    final words = plain.trim().isEmpty
        ? 0
        : plain.trim().split(RegExp(r'\s+')).length;
    final speakingSeconds = (words * 60 / 130).round();
    final duration = speakingSeconds < 60
        ? '${speakingSeconds}s'
        : '${speakingSeconds ~/ 60}:${(speakingSeconds % 60).toString().padLeft(2, '0')}';
    final style = TextStyle(fontSize: 10.5, color: AppTheme.slate500);
    return Semantics(
      label:
          '${slideNumber == null ? '' : '${l10n.d('Dia')} $slideNumber, '}'
          '${l10n.d('Regel')} $line, ${l10n.d('kolom')} $column, '
          '$words ${l10n.d('woorden')}',
      child: Container(
        height: 24,
        color: AppTheme.slate100,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (slideNumber != null) ...[
                Text('${l10n.d('Dia')} $slideNumber', style: style),
                const SizedBox(width: 10),
              ],
              Text(
                '${l10n.d('Regel')} $line · ${l10n.d('kolom')} $column',
                style: style,
              ),
              const Spacer(),
              Text('$words ${l10n.d('woorden')}', style: style),
              if (constraints.maxWidth >= 420) ...[
                const SizedBox(width: 12),
                Text('${text.length} ${l10n.d('tekens')}', style: style),
                const SizedBox(width: 12),
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 12,
                  color: AppTheme.slate500,
                ),
                const SizedBox(width: 3),
                Text('± $duration', style: style),
              ],
              if (constraints.maxWidth >= 560 &&
                  writingSuggestionCount > 0) ...[
                const SizedBox(width: 12),
                InkWell(
                  onTap: onWritingSuggestions,
                  child: Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        size: 12,
                        color: AppTheme.warningFg,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$writingSuggestionCount ${l10n.d('schrijftips')}',
                        style: style.copyWith(color: AppTheme.warningFg),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Geanimeerde segmented-toggle waarmee de markdown-modus wisselt tussen de
/// hele presentatie en alleen de actieve slide. Een wit "pilletje" schuift
/// vloeiend onder het gekozen segment.
class _MarkdownScopeToggle extends StatelessWidget {
  final MarkdownScope scope;
  final int slideNumber;
  final int slideCount;
  final ValueChanged<MarkdownScope> onChanged;

  const _MarkdownScopeToggle({
    required this.scope,
    required this.slideNumber,
    required this.slideCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSlide = scope == MarkdownScope.slide;
    final fg = AppTheme.warningFg;
    return Container(
      height: 30,
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Het schuivende, gemarkeerde segment.
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: isSlide
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _segment(
                    icon: Icons.view_carousel_outlined,
                    label: l10n.d('Volledige presentatie'),
                    active: !isSlide,
                    onTap: () => onChanged(MarkdownScope.deck),
                  ),
                  _segment(
                    icon: Icons.crop_square_outlined,
                    label: '${l10n.d('Deze slide')} · $slideNumber/$slideCount',
                    active: isSlide,
                    onTap: () => onChanged(MarkdownScope.slide),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final fg = AppTheme.warningFg;
    final color = active ? fg : fg.withValues(alpha: 0.6);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showIcon = constraints.maxWidth >= 48;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth >= 80 ? 8 : 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (showIcon) ...[
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DocumentStatus extends StatelessWidget {
  final bool dirty;
  final bool validationPending;
  final MarkdownValidationResult? validation;
  final VoidCallback? onPressed;

  const _DocumentStatus({
    required this.dirty,
    required this.validationPending,
    required this.validation,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, label, color) = validation?.hasIssues == true
        ? (
            Icons.warning_amber_outlined,
            l10n.d('Problemen gevonden'),
            AppTheme.dangerFg,
          )
        : dirty
        ? (Icons.edit_outlined, l10n.d('Niet toegepast'), AppTheme.warningFg)
        : validationPending
        ? (Icons.sync, l10n.d('Controleren…'), AppTheme.slate500)
        : (Icons.check, l10n.d('Actueel'), AppTheme.successFg);
    return Semantics(
      liveRegion: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }
}

class _MarkdownOutlineButton extends StatelessWidget {
  final List<MarkdownOutlineEntry> entries;
  final ValueChanged<int> onSelected;

  const _MarkdownOutlineButton({
    required this.entries,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<int>(
      tooltip: l10n.d('Documentoverzicht'),
      enabled: entries.isNotEmpty,
      padding: EdgeInsets.zero,
      iconSize: 14,
      icon: const Icon(Icons.account_tree_outlined),
      color: AppTheme.paper,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 260),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in entries)
          PopupMenuItem<int>(
            value: entry.line,
            height: 36,
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    '${l10n.d('Dia')} ${entry.slideNumber}',
                    style: TextStyle(fontSize: 10, color: AppTheme.slate500),
                  ),
                ),
                SizedBox(width: (entry.level - 1) * 10.0),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: entry.level == 1
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _ApplyChoice { edit, cancel, applyAnyway }

class _ApplyChoiceResult {
  final _ApplyChoice choice;
  final int? focusLine;

  const _ApplyChoiceResult(this.choice, [this.focusLine]);
}

class _ValidationSummaryBar extends StatelessWidget {
  final MarkdownValidationResult result;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<int> onJumpToLine;
  final VoidCallback? Function(MarkdownValidationIssue) quickFixFor;

  const _ValidationSummaryBar({
    required this.result,
    required this.expanded,
    required this.onToggle,
    required this.onJumpToLine,
    required this.quickFixFor,
  });

  Future<void> _copyIssues(BuildContext context) async {
    final l10n = context.l10n;
    final buf = StringBuffer();
    for (final issue in result.issues) {
      buf.writeln('Regel ${issue.line}: ${issue.message}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.d('Syntaxproblemen gekopieerd naar klembord.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = result.isValid ? AppTheme.warningBg : AppTheme.dangerBg;
    final iconColor = result.isValid ? AppTheme.warningFg : AppTheme.dangerFg;
    final summary = result.hasIssues
        ? '${result.errorCount} ${l10n.d('fout(en),')} '
              '${result.warningCount} ${l10n.d('waarschuwing(en)')}'
        : l10n.d('Geen syntaxproblemen gevonden');

    return Material(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: result.hasIssues ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    result.hasIssues
                        ? Icons.warning_amber_outlined
                        : Icons.check_circle_outline,
                    size: 14,
                    color: iconColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      summary,
                      style: TextStyle(fontSize: 11, color: iconColor),
                    ),
                  ),
                  if (result.hasIssues) ...[
                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      iconSize: 14,
                      color: iconColor,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: l10n.d('Kopieer syntaxproblemen'),
                      onPressed: () => _copyIssues(context),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: iconColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (expanded && result.hasIssues)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: result.issues.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final issue = result.issues[index];
                  return _IssueTile(
                    issue: issue,
                    onTap: () => onJumpToLine(issue.line),
                    onQuickFix: quickFixFor(issue),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  final MarkdownValidationIssue issue;
  final VoidCallback onTap;
  final VoidCallback? onQuickFix;

  const _IssueTile({required this.issue, required this.onTap, this.onQuickFix});

  @override
  Widget build(BuildContext context) {
    final isError = issue.severity == MarkdownValidationSeverity.error;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              size: 14,
              color: isError ? AppTheme.dangerFg : AppTheme.warningFg,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${context.l10n.d('Regel')} ${issue.line}: ${issue.message}',
                style: TextStyle(
                  fontSize: 11,
                  color: isError ? AppTheme.dangerFg : AppTheme.warningFg,
                ),
              ),
            ),
            if (onQuickFix != null)
              IconButton(
                onPressed: onQuickFix,
                tooltip: context.l10n.d('Snel herstellen'),
                icon: const Icon(Icons.auto_fix_high, size: 14),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }
}
