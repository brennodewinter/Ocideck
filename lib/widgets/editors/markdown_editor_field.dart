import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/editor_provider.dart';
import '../../theme/app_theme.dart';
import '../markdown_editor/markdown_editor.dart';
import '_editor_field.dart';
import 'expanded_markdown_dialog.dart';

/// A quiet, form-sized Markdown field that reveals formatting controls while
/// it is being used and can be expanded into the full visual/Markdown editor.
class MarkdownEditorField extends ConsumerStatefulWidget {
  static VoidCallback? openActiveEditor;
  final String label;
  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  final String? qualityField;

  const MarkdownEditorField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.minLines = 3,
    this.maxLines = 5,
    this.qualityField,
  });

  @override
  ConsumerState<MarkdownEditorField> createState() =>
      _MarkdownEditorFieldState();
}

class _MarkdownEditorFieldState extends ConsumerState<MarkdownEditorField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyQualityFocus());
  }

  @override
  void didUpdateWidget(MarkdownEditorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyQualityFocus();
  }

  void _applyQualityFocus() {
    if (!mounted || widget.qualityField == null) return;
    final editor = ref.read(editorProvider);
    if (editor.focusQualityField != widget.qualityField) return;
    _focusNode.requestFocus();
    applyQualitySpanSelection(widget.controller, editor.focusQualitySpan);
    Scrollable.ensureVisible(
      context,
      alignment: 0.25,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    ref.read(editorProvider.notifier).clearFocusQualityField();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      MarkdownEditorField.openActiveEditor = _openExpandedEditor;
    }
  }

  @override
  void dispose() {
    if (MarkdownEditorField.openActiveEditor == _openExpandedEditor) {
      MarkdownEditorField.openActiveEditor = null;
    }
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  MarkdownEditorTheme _editorTheme(
    BuildContext context, {
    double fontSize = 13,
  }) {
    return MarkdownEditorTheme.documentSurface(
      scheme: Theme.of(context).colorScheme,
      fontSize: fontSize,
    );
  }

  Future<void> _openExpandedEditor() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ExpandedMarkdownDialog(
        label: widget.label,
        hint: widget.hint.isEmpty
            ? dialogContext.l10n.d('Tekst...')
            : dialogContext.l10n.d(widget.hint),
        sourceController: widget.controller,
        editorTheme: _editorTheme(dialogContext, fontSize: 15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          shift: true,
        ): _openExpandedEditor,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          shift: true,
        ): _openExpandedEditor,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.d(widget.label),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate500,
                  ),
                ),
              ),
              Tooltip(
                message: l10n.d('Bewerken'),
                child: TextButton.icon(
                  onPressed: _openExpandedEditor,
                  icon: const Icon(Icons.open_in_full, size: 14),
                  label: Text(l10n.d('Bewerken')),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: widget.hint.isEmpty ? '' : l10n.d(widget.hint),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}
