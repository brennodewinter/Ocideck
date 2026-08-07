import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../markdown_editor/markdown_editor.dart';

/// Markdown that cannot round-trip losslessly through the visual editor, so the
/// dialog opens (and stays) in raw source mode for it.
///
/// A GFM table is deliberately **absent**: it round-trips as an `x-embed-table`
/// block embed (see `MarkdownQuillCodec` / `TableEmbedBuilder`), so it stays
/// editable in the visual editor instead of forcing raw source.
bool markdownNeedsSourceMode(String markdown) {
  final lines = markdown.split('\n');
  // `[^\]]` = "niet een `]`". Zónder de backslash leest Dart's (JS-achtige)
  // regex `[^]]` als "elk teken, gevolgd door een letterlijke `]`" en ving een
  // echte voetnoot `[^1]:` nooit — die viel dan alsnog terug via de binnenste
  // `markdownVisualLimitations`, maar deze poort hoort hem net zo te zien.
  return RegExp(r'^\[\^[^\]]+\]:', multiLine: true).hasMatch(markdown) ||
      RegExp(r'^---\s*$', multiLine: true).allMatches(markdown).length >= 2 ||
      lines.any((line) => line.trimLeft().startsWith('<!--'));
}

/// A roomy word-processor for one Markdown field.
///
/// Opens in the visual (WYSIWYG) editor by default — the friendly surface most
/// people want — with a switch to raw Markdown for those who prefer it. The
/// last-used mode is remembered locally.
class ExpandedMarkdownDialog extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController sourceController;
  final MarkdownEditorTheme editorTheme;

  const ExpandedMarkdownDialog({
    super.key,
    required this.label,
    required this.hint,
    required this.sourceController,
    required this.editorTheme,
  });

  @override
  State<ExpandedMarkdownDialog> createState() => _ExpandedMarkdownDialogState();
}

class _ExpandedMarkdownDialogState extends State<ExpandedMarkdownDialog> {
  static const _modeKey = 'markdownFieldEditorMode';
  static const _commitDelay = Duration(milliseconds: 120);

  late final TextEditingController _draft;
  late final bool _sourceModeRequired;
  Timer? _commitTimer;
  bool _syncing = false;
  bool _draftDirty = false;
  NotesEditorMode _mode = NotesEditorMode.visual;

  @override
  void initState() {
    super.initState();
    _draft = TextEditingController(text: widget.sourceController.text)
      ..addListener(_copyToSource);
    _sourceModeRequired = markdownNeedsSourceMode(_draft.text);
    if (_sourceModeRequired) _mode = NotesEditorMode.markdown;
    widget.sourceController.addListener(_copyToDraft);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _sourceModeRequired) return;
    final storedMode = prefs.getString(_modeKey);
    if (storedMode == NotesEditorMode.markdown.name) {
      setState(() => _mode = NotesEditorMode.markdown);
    } else if (storedMode == NotesEditorMode.visual.name) {
      setState(() => _mode = NotesEditorMode.visual);
    }
  }

  void _copyToSource() {
    if (_syncing || _draft.text == widget.sourceController.text) return;
    _draftDirty = true;
    _commitTimer?.cancel();
    _commitTimer = Timer(_commitDelay, _commitDraft);
  }

  void _commitDraft() {
    _commitTimer?.cancel();
    _commitTimer = null;
    if (_draft.text != widget.sourceController.text) {
      _syncing = true;
      widget.sourceController.value = _draft.value;
      _syncing = false;
    }
    _draftDirty = false;
  }

  void _copyToDraft() {
    if (_syncing ||
        _draftDirty ||
        _draft.text == widget.sourceController.text) {
      return;
    }
    _syncing = true;
    _draft.value = widget.sourceController.value;
    _syncing = false;
  }

  Future<void> _setMode(NotesEditorMode mode) async {
    if (_sourceModeRequired && mode == NotesEditorMode.visual) return;
    setState(() => _mode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  @override
  void dispose() {
    // A trailing debounce must never make closing the dialog lose input.
    _commitDraft();
    widget.sourceController.removeListener(_copyToDraft);
    _draft
      ..removeListener(_copyToSource)
      ..dispose();
    super.dispose();
  }

  void _wrap(String before, String after) {
    if (_mode != NotesEditorMode.markdown) return;
    MarkdownEditorActions.wrapSelection(
      _draft,
      before: before,
      after: after,
      placeholder: 'tekst',
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            _wrap('**', '**'),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            _wrap('**', '**'),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            _wrap('*', '*'),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
            _wrap('*', '*'),
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280, maxHeight: 860),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.d(widget.label),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.d('Sluiten'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: MarkdownNotesEditor(
                    controller: _draft,
                    editorTheme: widget.editorTheme,
                    hintText: widget.hint,
                    expand: true,
                    surfaceStyle: NotesSurfaceStyle.document,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 22,
                    ),
                    mode: _mode,
                    onModeChanged: _setMode,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.d('Esc'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.l10n.d('Klaar')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
