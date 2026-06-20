import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/markdown_validation.dart';
import '../../services/markdown_validator.dart';
import '../../state/editor_provider.dart';
import '../../utils/text_search.dart';
import 'markdown_find_bar.dart';

class MarkdownDeckEditor extends ConsumerStatefulWidget {
  final String initialContent;
  final bool Function(String) onApply;
  final bool parseError;
  final VoidCallback onExitMarkdown;

  const MarkdownDeckEditor({
    super.key,
    required this.initialContent,
    required this.onApply,
    required this.parseError,
    required this.onExitMarkdown,
  });

  @override
  ConsumerState<MarkdownDeckEditor> createState() => _MarkdownDeckEditorState();
}

class _MarkdownDeckEditorState extends ConsumerState<MarkdownDeckEditor> {
  static const _lineHeight = 19.5;

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
    final issueLines = <int, MarkdownValidationSeverity>{
      for (final issue in _validation?.issues ?? const [])
        issue.line: issue.severity,
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
            Container(
              color: const Color(0xFFFFF9E6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 14, color: Color(0xFF92400E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.d(
                        'Markdown modus — bewerk de volledige presentatie als Marp Markdown',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF92400E),
                      ),
                    ),
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
                    onPressed: widget.onExitMarkdown,
                    child: Text(l10n.t('cancel')),
                  ),
                ],
              ),
            ),
            if (_validation != null)
              _ValidationSummaryBar(
                result: _validation!,
                expanded: _showIssues,
                onToggle: () => setState(() => _showIssues = !_showIssues),
                onJumpToLine: _jumpToLine,
              ),
            if (widget.parseError)
              Container(
                color: const Color(0xFFFEE2E2),
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
                    child: TextField(
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
                        contentPadding: EdgeInsets.fromLTRB(8, 16, 16, 16),
                        border: InputBorder.none,
                        filled: true,
                        fillColor: Color(0xFFF8FAFC),
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
                  ),
                ],
              ),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = result.isValid
        ? const Color(0xFFFEF3C7)
        : const Color(0xFFFEE2E2);
    final iconColor = result.isValid
        ? const Color(0xFF92400E)
        : Colors.red.shade700;
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
                  if (result.hasIssues)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: iconColor,
                    ),
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
              color: isError ? Colors.red.shade700 : const Color(0xFF92400E),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Regel ${issue.line}: ${issue.message}',
                style: TextStyle(
                  fontSize: 11,
                  color: isError
                      ? Colors.red.shade700
                      : const Color(0xFF92400E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      color: const Color(0xFFEEF2F7),
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
      MarkdownValidationSeverity.error => const Color(0xFFFECACA),
      MarkdownValidationSeverity.warning => const Color(0xFFFDE68A),
      MarkdownValidationSeverity.informational => const Color(0xFFE2E8F0),
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
                ? const Color(0xFF92400E)
                : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}
