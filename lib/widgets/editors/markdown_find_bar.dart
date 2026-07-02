import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// In-editor find (and optional replace) bar for markdown mode.
class MarkdownFindBar extends StatefulWidget {
  final String query;
  final String replace;
  final bool caseSensitive;
  final bool showReplace;
  final int matchCount;
  final int matchIndex;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onReplaceChanged;
  final ValueChanged<bool> onCaseSensitiveChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onReplaceCurrent;
  final VoidCallback onReplaceAll;
  final VoidCallback onClose;

  const MarkdownFindBar({
    super.key,
    required this.query,
    required this.replace,
    required this.caseSensitive,
    required this.showReplace,
    required this.matchCount,
    required this.matchIndex,
    required this.onQueryChanged,
    required this.onReplaceChanged,
    required this.onCaseSensitiveChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onReplaceCurrent,
    required this.onReplaceAll,
    required this.onClose,
  });

  @override
  State<MarkdownFindBar> createState() => _MarkdownFindBarState();
}

class _MarkdownFindBarState extends State<MarkdownFindBar> {
  late final TextEditingController _queryCtrl;
  late final TextEditingController _replaceCtrl;
  late final FocusNode _queryFocus;
  late final FocusNode _replaceFocus;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.query);
    _replaceCtrl = TextEditingController(text: widget.replace);
    _queryFocus = FocusNode();
    _replaceFocus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.showReplace) {
        _replaceFocus.requestFocus();
      } else {
        _queryFocus.requestFocus();
        _queryCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _queryCtrl.text.length,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant MarkdownFindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _queryCtrl.text) {
      _queryCtrl.text = widget.query;
    }
    if (widget.replace != _replaceCtrl.text) {
      _replaceCtrl.text = widget.replace;
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _replaceCtrl.dispose();
    _queryFocus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleQueryKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.onPrevious();
      } else {
        widget.onNext();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleReplaceKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _statusText(AppLocalizations l10n) {
    if (widget.query.isEmpty) return const SizedBox.shrink();
    if (widget.matchCount == 0) {
      return Text(
        l10n.d('Geen resultaten'),
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.slate400,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final current = widget.matchIndex + 1;
    return Text(
      '$current / ${widget.matchCount}',
      style: const TextStyle(
        fontSize: 11,
        color: AppTheme.accent,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasQuery = widget.query.isNotEmpty;
    final hasMatches = widget.matchCount > 0;

    return Material(
      color: const Color(0xFFF1F5F9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleQueryKey,
                    child: TextField(
                      controller: _queryCtrl,
                      focusNode: _queryFocus,
                      onChanged: widget.onQueryChanged,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: l10n.d('Zoeken naar'),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: l10n.d('Vorige'),
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: hasMatches ? widget.onPrevious : null,
                ),
                IconButton(
                  tooltip: l10n.d('Volgende'),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: hasMatches ? widget.onNext : null,
                ),
                const SizedBox(width: 4),
                _statusText(l10n),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: l10n.t('close'),
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            if (widget.showReplace) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Focus(
                      onKeyEvent: _handleReplaceKey,
                      child: TextField(
                        controller: _replaceCtrl,
                        focusNode: _replaceFocus,
                        onChanged: widget.onReplaceChanged,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: l10n.d('Vervangen door'),
                          prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: hasMatches ? widget.onReplaceCurrent : null,
                    child: Text(l10n.d('Vervang')),
                  ),
                  FilledButton(
                    onPressed: (hasQuery && hasMatches)
                        ? widget.onReplaceAll
                        : null,
                    child: Text(l10n.d('Vervang alles')),
                  ),
                ],
              ),
            ],
            Row(
              children: [
                Checkbox(
                  value: widget.caseSensitive,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => widget.onCaseSensitiveChanged(v ?? false),
                ),
                Text(
                  l10n.d('Hoofdlettergevoelig'),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
