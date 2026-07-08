import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/markdown_validation.dart';
import '../../services/markdown_validator.dart';
import '../../state/editor_provider.dart';
import '../../utils/text_search.dart';
import 'markdown_find_bar.dart';
import '../../theme/app_theme.dart';

class MarkdownDeckEditor extends ConsumerStatefulWidget {
  final String initialContent;
  final bool Function(String) onApply;
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
    required this.onApply,
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

  late final TextEditingController _ctrl;
  late final ScrollController _scrollController;
  final _validator = MarkdownValidator();
  MarkdownValidationResult? _validation;
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
    _ctrl = TextEditingController(text: widget.initialContent);
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(MarkdownDeckEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Bij het wisselen van omvang (hele presentatie ↔ slide) of van de actieve
    // slide levert het paneel verse [initialContent]. De widget blijft bestaan
    // (zodat de toggle animeert), dus laden we de nieuwe inhoud hier in en
    // ruimen we validatie/zoekstaat op. Eigen tikwerk verandert alleen
    // [_ctrl.text], niet [initialContent], dus dat blijft ongemoeid.
    if (widget.initialContent != oldWidget.initialContent) {
      _ctrl.text = widget.initialContent;
      setState(() {
        _validation = null;
        _showIssues = false;
        _matches = const [];
        _matchIndex = -1;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollController.dispose();
    super.dispose();
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
  }

  void _goToNextMatch() {
    if (_matches.isEmpty) return;
    final next = nextMatchIndex(_matchIndex, _matches.length);
    setState(() => _matchIndex = next);
    _jumpToRange(_matches[next]);
  }

  void _goToPreviousMatch() {
    if (_matches.isEmpty) return;
    final prev = previousMatchIndex(_matchIndex, _matches.length);
    setState(() => _matchIndex = prev);
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
  }

  MarkdownValidationResult _runValidation() {
    final result = _validator.validate(_ctrl.text);
    setState(() {
      _validation = result;
      _showIssues = result.hasIssues;
    });
    return result;
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
    if (ok) widget.onExitMarkdown();
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
      },
      child: Focus(
        onKeyEvent: _handleEscape,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _modeBanner(l10n),
            if (_validation != null)
              _ValidationSummaryBar(
                result: _validation!,
                expanded: _showIssues,
                onToggle: () => setState(() => _showIssues = !_showIssues),
                onJumpToLine: _jumpToLine,
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
                    const Icon(
                      Icons.warning_amber_outlined,
                      size: 14,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.d(
                          'Markdown kon niet worden verwerkt. Controleer de syntax.',
                        ),
                        style: const TextStyle(fontSize: 11, color: Colors.red),
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
              onChanged: widget.onScopeChanged,
            ),
          ),
          const Spacer(),
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
            onPressed: widget.onExitMarkdown,
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
                // Backdrop + the coloured finding bands sit behind the text; the
                // TextField's own fill is transparent so they show through while
                // the text, caret and selection stay on top and readable.
                Positioned.fill(child: ColoredBox(color: AppTheme.slate50)),
                Positioned.fill(
                  child: _IssueHighlightLayer(
                    scrollController: _scrollController,
                    issueLines: issueLines,
                    topPadding: _editorTopPadding,
                  ),
                ),
                TextField(
                  controller: _ctrl,
                  scrollController: _scrollController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
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
                  onChanged: (_) {
                    setState(() {
                      _validation = null;
                    });
                    if (_findVisible && _findQuery.isNotEmpty) {
                      _recountMatches(selectFirst: false);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
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
        ),
      ),
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

  const _ValidationSummaryBar({
    required this.result,
    required this.expanded,
    required this.onToggle,
    required this.onJumpToLine,
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
    final iconColor = result.isValid ? AppTheme.warningFg : Colors.red.shade700;
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

  const _IssueTile({required this.issue, required this.onTap});

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
              color: isError ? Colors.red.shade700 : AppTheme.warningFg,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${context.l10n.d('Regel')} ${issue.line}: ${issue.message}',
                style: TextStyle(
                  fontSize: 11,
                  color: isError ? Colors.red.shade700 : AppTheme.warningFg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a full-width coloured band (plus a stronger left accent bar) behind
/// every line that carries a validation issue, so findings are visible in the
/// code itself — red for errors, amber for warnings — not only in the gutter.
/// It scrolls in lock-step with the text via [scrollController].
class _IssueHighlightLayer extends StatelessWidget {
  final ScrollController scrollController;
  final Map<int, MarkdownValidationSeverity> issueLines;
  final double topPadding;

  const _IssueHighlightLayer({
    required this.scrollController,
    required this.issueLines,
    required this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    if (issueLines.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: scrollController,
          builder: (context, _) {
            final offset = scrollController.hasClients
                ? scrollController.offset
                : 0.0;
            return CustomPaint(
              painter: _IssueHighlightPainter(
                issueLines: issueLines,
                lineHeight: _MarkdownDeckEditorState._lineHeight,
                topPadding: topPadding,
                scrollOffset: offset,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IssueHighlightPainter extends CustomPainter {
  final Map<int, MarkdownValidationSeverity> issueLines;
  final double lineHeight;
  final double topPadding;
  final double scrollOffset;

  _IssueHighlightPainter({
    required this.issueLines,
    required this.lineHeight,
    required this.topPadding,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in issueLines.entries) {
      final (band, accent) = switch (entry.value) {
        MarkdownValidationSeverity.error => (
          AppTheme.dangerBgSoft,
          Colors.red.shade700,
        ),
        MarkdownValidationSeverity.warning => (
          AppTheme.warningBgSoft,
          AppTheme.warningFg,
        ),
        MarkdownValidationSeverity.informational => (
          AppTheme.slate200,
          AppTheme.slate400,
        ),
      };
      final top = topPadding + (entry.key - 1) * lineHeight - scrollOffset;
      if (top + lineHeight < 0 || top > size.height) continue;
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, lineHeight),
        Paint()..color = band,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, top, 3, lineHeight),
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_IssueHighlightPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.topPadding != topPadding ||
      old.lineHeight != lineHeight ||
      !mapEquals(old.issueLines, issueLines);
}

class _LineNumberGutter extends StatelessWidget {
  final ScrollController scrollController;
  final int lineCount;
  final Map<int, MarkdownValidationSeverity> issueLines;
  final ValueChanged<int> onLineTap;

  const _LineNumberGutter({
    required this.scrollController,
    required this.lineCount,
    required this.issueLines,
    required this.onLineTap,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.iceBlue2,
      child: SizedBox(
        width: 44,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: scrollController,
            builder: (context, child) {
              final offset = scrollController.hasClients
                  ? scrollController.offset
                  : 0.0;
              return Transform.translate(
                offset: Offset(0, 16 - offset),
                child: child,
              );
            },
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxWidth: 44,
              minWidth: 44,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < lineCount; index++)
                    _LineNumberCell(
                      line: index + 1,
                      severity: issueLines[index + 1],
                      onTap: onLineTap,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineNumberCell extends StatelessWidget {
  final int line;
  final MarkdownValidationSeverity? severity;
  final ValueChanged<int> onTap;

  const _LineNumberCell({
    required this.line,
    required this.severity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = switch (severity) {
      MarkdownValidationSeverity.error => AppTheme.dangerBgSoft,
      MarkdownValidationSeverity.warning => AppTheme.warningBgSoft,
      MarkdownValidationSeverity.informational => AppTheme.slate200,
      null => Colors.transparent,
    };
    return GestureDetector(
      onTap: () => onTap(line),
      child: Container(
        height: _MarkdownDeckEditorState._lineHeight,
        color: bg,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          '$line',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.5,
            color: severity == MarkdownValidationSeverity.error
                ? Colors.red.shade700
                : severity == MarkdownValidationSeverity.warning
                ? AppTheme.warningFg
                : AppTheme.slate400,
          ),
        ),
      ),
    );
  }
}
