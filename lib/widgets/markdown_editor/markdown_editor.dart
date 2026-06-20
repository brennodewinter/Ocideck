import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../utils/markdown_quill_codec.dart';
import 'markdown_editor_theme.dart';
import 'markdown_editor_toolbar.dart';
import 'notes_editor_mode.dart';
import 'notes_mode_toggle.dart';
import 'wysiwyg_notes_field.dart';
import 'wysiwyg_notes_toolbar.dart';

export 'markdown_editor_actions.dart';
export 'markdown_editor_theme.dart';
export 'markdown_editor_toolbar.dart';
export 'notes_editor_mode.dart';
export 'notes_mode_toggle.dart';

/// Notes editor with a visual (WYSIWYG) and a raw markdown mode side by side.
///
/// Markdown is the stored format; switching modes converts through [MarkdownQuillCodec].
class MarkdownNotesEditor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final MarkdownEditorTheme editorTheme;
  final String hintText;
  final int minLines;
  final int? maxLines;
  final bool expand;
  final EdgeInsetsGeometry contentPadding;
  final bool showToolbar;
  final bool compactToolbar;
  final InputDecoration? inputDecoration;
  final bool bordered;
  final NotesEditorMode initialMode;
  final NotesEditorMode? mode;
  final ValueChanged<NotesEditorMode>? onModeChanged;
  final bool showModeToggle;
  final NotesModeToggleStyle modeToggleStyle;

  const MarkdownNotesEditor({
    super.key,
    required this.controller,
    this.focusNode,
    required this.editorTheme,
    required this.hintText,
    this.minLines = 4,
    this.maxLines,
    this.expand = false,
    this.contentPadding = const EdgeInsets.all(10),
    this.showToolbar = true,
    this.compactToolbar = false,
    this.inputDecoration,
    this.bordered = true,
    this.initialMode = NotesEditorMode.visual,
    this.mode,
    this.onModeChanged,
    this.showModeToggle = true,
    this.modeToggleStyle = NotesModeToggleStyle.standard,
  });

  /// Convenience constructor using discrete color/style parameters.
  factory MarkdownNotesEditor.legacy({
    Key? key,
    required TextEditingController controller,
    FocusNode? focusNode,
    required TextStyle baseStyle,
    required Color linkColor,
    Color codeBackground = const Color(0x1A000000),
    required String hintText,
    InputDecoration? inputDecoration,
    int minLines = 4,
    int? maxLines,
    bool expand = false,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.all(10),
    bool borderedVisual = true,
    bool showToolbar = true,
    bool compactToolbar = false,
    NotesEditorMode initialMode = NotesEditorMode.visual,
    NotesEditorMode? mode,
    ValueChanged<NotesEditorMode>? onModeChanged,
    bool showModeToggle = true,
    NotesModeToggleStyle modeToggleStyle = NotesModeToggleStyle.standard,
  }) {
    final border = inputDecoration?.enabledBorder is OutlineInputBorder
        ? (inputDecoration!.enabledBorder as OutlineInputBorder)
              .borderSide
              .color
        : const Color(0xFFBFDBFE);
    return MarkdownNotesEditor(
      key: key,
      controller: controller,
      focusNode: focusNode,
      editorTheme: MarkdownEditorTheme.editorPanel(
        text: baseStyle.color ?? const Color(0xFF1E293B),
        link: linkColor,
        accent: linkColor,
        codeBackground: codeBackground,
        border: border,
        fontSize: baseStyle.fontSize ?? 12,
      ),
      hintText: hintText,
      inputDecoration: inputDecoration,
      minLines: minLines,
      maxLines: maxLines,
      expand: expand,
      contentPadding: contentPadding,
      bordered: borderedVisual,
      showToolbar: showToolbar,
      compactToolbar: compactToolbar,
      initialMode: initialMode,
      mode: mode,
      onModeChanged: onModeChanged,
      showModeToggle: showModeToggle,
      modeToggleStyle: modeToggleStyle,
    );
  }

  @override
  State<MarkdownNotesEditor> createState() => _MarkdownNotesEditorState();
}

class _MarkdownNotesEditorState extends State<MarkdownNotesEditor> {
  late NotesEditorMode _mode;
  QuillController? _quillController;
  ScrollController? _scrollController;
  FocusNode? _ownedFocusNode;
  bool _syncingMarkdown = false;
  String _markdownSnapshot = '';

  NotesEditorMode get _effectiveMode => widget.mode ?? _mode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _markdownSnapshot = widget.controller.text;
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
    if (_effectiveMode == NotesEditorMode.visual) {
      _openVisualEditor();
    }
  }

  @override
  void didUpdateWidget(MarkdownNotesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldMode = oldWidget.mode ?? _mode;
    final newMode = widget.mode ?? _mode;
    if (newMode != oldMode) {
      _transitionMode(from: oldMode, to: newMode);
      if (widget.mode == null) {
        _mode = newMode;
      }
    }
    if (widget.controller.text != _markdownSnapshot &&
        !_syncingMarkdown &&
        newMode == NotesEditorMode.visual) {
      _reloadVisualFromMarkdown();
    }
  }

  @override
  void dispose() {
    _closeVisualEditor(flush: false);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _openVisualEditor() {
    if (_quillController != null) return;
    _scrollController = ScrollController();
    _quillController = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(widget.controller.text),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _markdownSnapshot = widget.controller.text;
    _quillController!.addListener(_onQuillChanged);
  }

  void _closeVisualEditor({required bool flush}) {
    final quill = _quillController;
    if (quill == null) return;
    if (flush) {
      _flushQuillToController(quill);
    }
    quill.removeListener(_onQuillChanged);
    quill.dispose();
    _scrollController?.dispose();
    _quillController = null;
    _scrollController = null;
  }

  void _reloadVisualFromMarkdown() {
    final quill = _quillController;
    if (quill == null) return;
    _syncingMarkdown = true;
    _markdownSnapshot = widget.controller.text;
    quill.document = MarkdownQuillCodec.documentFromMarkdown(_markdownSnapshot);
    _syncingMarkdown = false;
  }

  void _flushQuillToController(QuillController quill) {
    final markdown = MarkdownQuillCodec.markdownFromDocument(quill.document);
    if (markdown == widget.controller.text) {
      _markdownSnapshot = markdown;
      return;
    }
    _syncingMarkdown = true;
    _markdownSnapshot = markdown;
    widget.controller.value = widget.controller.value.copyWith(text: markdown);
    _syncingMarkdown = false;
  }

  void _onQuillChanged() {
    if (_syncingMarkdown) return;
    final quill = _quillController;
    if (quill == null) return;
    final markdown = MarkdownQuillCodec.markdownFromDocument(quill.document);
    if (markdown == _markdownSnapshot) return;
    _syncingMarkdown = true;
    _markdownSnapshot = markdown;
    widget.controller.value = widget.controller.value.copyWith(text: markdown);
    _syncingMarkdown = false;
  }

  void _transitionMode({
    required NotesEditorMode from,
    required NotesEditorMode to,
  }) {
    if (from == to) return;
    if (from == NotesEditorMode.visual) {
      _closeVisualEditor(flush: true);
    }
    if (to == NotesEditorMode.visual) {
      _openVisualEditor();
    }
  }

  void _onModeSelected(NotesEditorMode mode) {
    final current = _effectiveMode;
    if (mode == current) return;
    _transitionMode(from: current, to: mode);
    if (widget.mode == null) {
      setState(() => _mode = mode);
    }
    widget.onModeChanged?.call(mode);
  }

  InputDecoration _markdownFieldDecoration() {
    final legacy = widget.inputDecoration;
    if (legacy != null) {
      return legacy.copyWith(
        fillColor: widget.editorTheme.surface,
        filled: true,
      );
    }
    return InputDecoration(
      hintText: widget.hintText,
      hintStyle: widget.editorTheme.hintStyle,
      filled: true,
      fillColor: widget.editorTheme.surface,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: widget.contentPadding,
      alignLabelWithHint: true,
    );
  }

  Widget _buildMarkdownField() {
    return Container(
      width: double.infinity,
      constraints: widget.expand
          ? null
          : BoxConstraints(minHeight: widget.minLines * 22.0),
      decoration: BoxDecoration(
        color: widget.editorTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: widget.bordered
            ? Border.all(color: widget.editorTheme.border)
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        expands: widget.expand,
        minLines: widget.expand ? null : widget.minLines,
        maxLines: widget.expand ? null : widget.maxLines,
        textAlignVertical: TextAlignVertical.top,
        autocorrect: false,
        enableSuggestions: false,
        style: widget.editorTheme.markdownStyle,
        decoration: _markdownFieldDecoration(),
        strutStyle: StrutStyle(
          fontSize: widget.editorTheme.fontSize - 0.5,
          height: widget.editorTheme.lineHeight,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
          forceStrutHeight: true,
        ),
      ),
    );
  }

  Widget _buildVisualField() {
    final quill = _quillController;
    final scroll = _scrollController;
    if (quill == null || scroll == null) {
      return const SizedBox.shrink();
    }
    return WysiwygNotesField(
      controller: quill,
      scrollController: scroll,
      focusNode: _focusNode,
      editorTheme: widget.editorTheme,
      hintText: widget.hintText,
      expand: widget.expand,
      contentPadding: widget.contentPadding,
      bordered: widget.bordered,
    );
  }

  Widget _buildEditorSurface() {
    final field = _effectiveMode == NotesEditorMode.visual
        ? _buildVisualField()
        : _buildMarkdownField();
    if (widget.expand) {
      return Expanded(child: field);
    }
    return field;
  }

  @override
  Widget build(BuildContext context) {
    final quill = _quillController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showModeToggle) ...[
          NotesModeToggle(
            mode: _effectiveMode,
            onModeChanged: _onModeSelected,
            style: widget.modeToggleStyle,
            foregroundColor: widget.editorTheme.toolbarIcon,
            accentColor: widget.editorTheme.accent,
          ),
          const SizedBox(height: 6),
        ],
        if (widget.showToolbar) ...[
          if (_effectiveMode == NotesEditorMode.markdown)
            MarkdownEditorToolbar(
              controller: widget.controller,
              focusNode: _focusNode,
              theme: widget.editorTheme,
              compact: widget.compactToolbar,
            )
          else if (quill != null)
            WysiwygNotesToolbar(
              controller: quill,
              focusNode: _focusNode,
              theme: widget.editorTheme,
              compact: widget.compactToolbar,
            ),
          const SizedBox(height: 6),
        ],
        _buildEditorSurface(),
      ],
    );
  }
}

/// Alias for the shared markdown editor.
typedef MarkdownEditor = MarkdownNotesEditor;
