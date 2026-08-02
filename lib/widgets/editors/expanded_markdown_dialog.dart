import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/shortcut_label.dart';
import '../markdown_editor/markdown_editor.dart';

typedef MarkdownPreviewBuilder =
    Widget Function(BuildContext context, String markdown);

bool markdownNeedsSourceMode(String markdown) {
  final lines = markdown.split('\n');
  return RegExp(r'^\s*\|.+\|\s*$', multiLine: true).hasMatch(markdown) ||
      RegExp(r'^\[\^[^]]+\]:', multiLine: true).hasMatch(markdown) ||
      RegExp(r'^---\s*$', multiLine: true).allMatches(markdown).length >= 2 ||
      lines.any((line) => line.trimLeft().startsWith('<!--'));
}

class ExpandedMarkdownDialog extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController sourceController;
  final MarkdownEditorTheme editorTheme;
  final MarkdownPreviewBuilder? previewBuilder;

  const ExpandedMarkdownDialog({
    super.key,
    required this.label,
    required this.hint,
    required this.sourceController,
    required this.editorTheme,
    this.previewBuilder,
  });

  @override
  State<ExpandedMarkdownDialog> createState() => _ExpandedMarkdownDialogState();
}

class _ExpandedMarkdownDialogState extends State<ExpandedMarkdownDialog> {
  static const _modeKey = 'markdownFieldEditorMode';
  static const _ratioKey = 'markdownFieldPreviewRatio';
  static const _previewDelay = Duration(milliseconds: 120);

  late final TextEditingController _draft;
  late final ValueNotifier<String> _previewMarkdown;
  late final bool _sourceModeRequired;
  Timer? _commitTimer;
  bool _syncing = false;
  bool _draftDirty = false;
  bool _showPreviewTab = false;
  NotesEditorMode _mode = NotesEditorMode.markdown;
  double _editorRatio = 0.56;

  @override
  void initState() {
    super.initState();
    _draft = TextEditingController(text: widget.sourceController.text)
      ..addListener(_copyToSource);
    _previewMarkdown = ValueNotifier(_draft.text);
    _sourceModeRequired = markdownNeedsSourceMode(_draft.text);
    widget.sourceController.addListener(_copyToDraft);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final storedMode = prefs.getString(_modeKey);
    setState(() {
      if (!_sourceModeRequired && storedMode == NotesEditorMode.visual.name) {
        _mode = NotesEditorMode.visual;
      }
      _editorRatio = (prefs.getDouble(_ratioKey) ?? _editorRatio).clamp(
        0.35,
        0.75,
      );
    });
  }

  void _copyToSource() {
    if (_syncing || _draft.text == widget.sourceController.text) return;
    _draftDirty = true;
    _commitTimer?.cancel();
    _commitTimer = Timer(_previewDelay, _commitDraft);
  }

  void _commitDraft({bool refreshPreview = true}) {
    _commitTimer?.cancel();
    _commitTimer = null;
    if (_draft.text != widget.sourceController.text) {
      _syncing = true;
      widget.sourceController.value = _draft.value;
      _syncing = false;
    }
    _draftDirty = false;
    if (refreshPreview && _previewMarkdown.value != _draft.text) {
      _previewMarkdown.value = _draft.text;
    }
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

  void _setRatio(double value) {
    setState(() => _editorRatio = value.clamp(0.35, 0.75));
  }

  Future<void> _saveRatio() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ratioKey, _editorRatio);
  }

  @override
  void dispose() {
    // A trailing debounce must never make closing the dialog lose input.
    _commitDraft(refreshPreview: false);
    widget.sourceController.removeListener(_copyToDraft);
    _previewMarkdown.dispose();
    _draft
      ..removeListener(_copyToSource)
      ..dispose();
    super.dispose();
  }

  Widget _editor(BuildContext context) {
    final warning = context.l10n.d('Waarschuwing');
    final markdownMode = context.l10n.t('markdownMode');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sourceModeRequired)
          Semantics(
            liveRegion: true,
            child: MaterialBanner(
              content: Text('$warning — $markdownMode'),
              actions: const [SizedBox.shrink()],
            ),
          ),
        Expanded(
          child: MarkdownNotesEditor(
            controller: _draft,
            editorTheme: widget.editorTheme,
            hintText: widget.hint,
            expand: true,
            compactToolbar: false,
            mode: _mode,
            onModeChanged: _setMode,
          ),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.l10n.d('Preview'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      Expanded(
        child: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: _previewMarkdown,
            builder: (context, markdown, _) => RepaintBoundary(
              child: widget.previewBuilder!(context, markdown),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _divider() => Semantics(
    label: context.l10n.d(
      'Sleep om de slide-preview breder of smaller te maken',
    ),
    value: '${(_editorRatio * 100).round()}%',
    increasedValue:
        '${((_editorRatio + 0.05).clamp(0.35, 0.75) * 100).round()}%',
    decreasedValue:
        '${((_editorRatio - 0.05).clamp(0.35, 0.75) * 100).round()}%',
    onIncrease: () {
      _setRatio(_editorRatio + 0.05);
      _saveRatio();
    },
    onDecrease: () {
      _setRatio(_editorRatio - 0.05);
      _saveRatio();
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onDoubleTap: () {
          _setRatio(0.56);
          _saveRatio();
        },
        onHorizontalDragUpdate: (details) {
          final width = context.size?.width ?? 1000;
          _setRatio(_editorRatio + details.delta.dx / width);
        },
        onHorizontalDragEnd: (_) => _saveRatio(),
        child: const SizedBox(
          width: 20,
          child: Center(child: VerticalDivider(width: 1, thickness: 1)),
        ),
      ),
    ),
  );

  Widget _responsiveBody(BuildContext context, BoxConstraints constraints) {
    if (widget.previewBuilder == null) return _editor(context);
    if (constraints.maxWidth < 850) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _tabButton(
                  context,
                  preview: false,
                  icon: Icons.edit_outlined,
                  label: context.l10n.d('Bewerken'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tabButton(
                  context,
                  preview: true,
                  icon: Icons.slideshow_outlined,
                  label: context.l10n.d('Preview'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _showPreviewTab ? _preview(context) : _editor(context),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: (_editorRatio * 1000).round(), child: _editor(context)),
        _divider(),
        Expanded(
          flex: ((1 - _editorRatio) * 1000).round(),
          child: _preview(context),
        ),
      ],
    );
  }

  Widget _tabButton(
    BuildContext context, {
    required bool preview,
    required IconData icon,
    required String label,
  }) {
    final selected = _showPreviewTab == preview;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    return Semantics(
      selected: selected,
      button: true,
      child: selected
          ? FilledButton.tonal(
              onPressed: () => setState(() => _showPreviewTab = preview),
              child: child,
            )
          : OutlinedButton(
              onPressed: () => setState(() => _showPreviewTab = preview),
              child: child,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewShortcut = shortcutLabel(context.l10n, 'P', shift: true);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          if (_mode == NotesEditorMode.markdown) {
            MarkdownEditorActions.wrapSelection(
              _draft,
              before: '**',
              after: '**',
              placeholder: 'tekst',
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () {
          if (_mode == NotesEditorMode.markdown) {
            MarkdownEditorActions.wrapSelection(
              _draft,
              before: '**',
              after: '**',
              placeholder: 'tekst',
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
          if (_mode == NotesEditorMode.markdown) {
            MarkdownEditorActions.wrapSelection(
              _draft,
              before: '*',
              after: '*',
              placeholder: 'tekst',
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () {
          if (_mode == NotesEditorMode.markdown) {
            MarkdownEditorActions.wrapSelection(
              _draft,
              before: '*',
              after: '*',
              placeholder: 'tekst',
            );
          }
        },
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): () =>
            setState(() => _showPreviewTab = !_showPreviewTab),
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          meta: true,
          shift: true,
        ): () =>
            setState(() => _showPreviewTab = !_showPreviewTab),
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280, maxHeight: 800),
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
                Expanded(child: LayoutBuilder(builder: _responsiveBody)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$previewShortcut · ${context.l10n.d('Esc')}',
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
