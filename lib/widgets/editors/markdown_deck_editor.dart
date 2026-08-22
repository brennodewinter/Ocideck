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
import 'find_replace_session.dart';
import 'markdown_find_bar.dart';
import 'markdown_command_palette.dart';
import 'markdown_smart_input_formatter.dart';
import 'markdown_source_controller.dart';
import '../../theme/app_theme.dart';

// De kantlijn en de gekleurde bevindingsbanden. Een part omdat ze op de private
// regelhoogte van de editor-state leunen — zie het bestand zelf.
part 'markdown_deck_editor_gutter.dart';
part 'markdown_deck_editor_widgets.dart';

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

  /// Het laatst afgeronde oordeel, ook terwijl er een nieuwe controle loopt.
  ///
  /// Apart van [_validation], dat tijdens het typen leegloopt zodat de
  /// markeringen in de code niet op verschoven regelnummers blijven staan. De
  /// balk mag juist niet leeglopen: die verdween dan uit de [Column] en trok de
  /// bovenrand van de editor 28 px mee (#1555).
  MarkdownValidationResult? _lastValidation;
  bool _validationPending = false;
  bool _syncingExternalContent = false;
  int? _lastReportedSlide;
  bool _showIssues = false;

  /// Zoek-/vervangbalk. De stand zelf leeft in [FindReplaceSession], gedeeld
  /// met de documenteditor; dit scherm levert alleen de controller en waar de
  /// cursor naartoe springt.
  late final FindReplaceSession _find;

  @override
  void initState() {
    super.initState();
    _ctrl = MarkdownSourceController(text: widget.initialContent);
    _sourceDocument = MarkdownSourceDocument.parse(widget.initialContent);
    _writingSuggestions = inspectMarkdownWriting(widget.initialContent);
    _observedText = widget.initialContent;
    _baselineContent = widget.baselineContent ?? widget.initialContent;
    _ctrl.addListener(_onDocumentChanged);
    _find = FindReplaceSession(
      controller: _ctrl,
      onChanged: () {
        if (mounted) setState(() {});
      },
      onReveal: _jumpToRange,
    );
    _scrollController = ScrollController();
    _editorFocusNode = FocusNode();
    _undoController = UndoHistoryController()..addListener(_onUndoChanged);
    // Meteen een oordeel voor de balk in plaats van de debounce af te wachten:
    // stond hij er de eerste 350 ms niet, dan schoof de editor bij het openen
    // alsnog een keer omhoog en weer terug (#1555). De markeringen in de code
    // wachten wel op de gewone ronde, zoals altijd.
    _lastValidation = _validator.validate(widget.initialContent);
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
        _lastValidation = _validator.validate(widget.initialContent);
        _showIssues = false;
      });
      // De balk blijft staan; alleen de gevonden plekken slaan nergens meer op.
      _find.clearMatches();
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
    _find.refreshWhileTyping();
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
        _lastValidation = result;
        _validationPending = false;
      });
    });
  }

  void _openFind({required bool showReplace}) =>
      _find.open(showReplace: showReplace);

  MarkdownValidationResult _runValidation() {
    _validationTimer?.cancel();
    final result = _validator.validate(_ctrl.text);
    setState(() {
      _validation = result;
      _lastValidation = result;
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
    if (!_find.visible) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _find.close();
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
            _formattingBar(this),
            if (_lastValidation != null)
              _ValidationSummaryBar(
                result: _lastValidation!,
                pending: _validationPending,
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
            if (_find.visible)
              MarkdownFindBar(
                key: ValueKey('find-${_find.showReplace}'),
                query: _find.query,
                replace: _find.replacement,
                caseSensitive: _find.caseSensitive,
                showReplace: _find.showReplace,
                matchCount: _find.matchCount,
                matchIndex: _find.matchIndex,
                onQueryChanged: _find.setQuery,
                onReplaceChanged: _find.setReplacement,
                onCaseSensitiveChanged: _find.setCaseSensitive,
                onNext: _find.next,
                onPrevious: _find.previous,
                onReplaceCurrent: _find.replaceCurrent,
                onReplaceAll: _find.replaceAll,
                onClose: _find.close,
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
          // Niet-interactief status-badge: het <>-icoon met het woord 'Bron'
          // maakt duidelijk dat je in de rauwe markdown-bron zit — een label,
          // geen knop (#1187). Een kale icoon las tussen de echte icoonknoppen
          // in deze balk als iets klikbaars. Hetzelfde woord 'Bron' als de chip
          // die hierheen leidt, dus instap en bestemming dragen één signaal.
          Icon(Icons.code, size: 14, color: AppTheme.warningFg),
          const SizedBox(width: 5),
          Text(
            l10n.d('Bron'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.warningFg,
            ),
          ),
          const SizedBox(width: 10),
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
