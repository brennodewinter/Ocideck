import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../utils/markdown_quill_codec.dart';
import '../../utils/markdown_paste_cleanup.dart';
import '../../utils/markdown_visual_compatibility.dart';
import '../../l10n/app_localizations.dart';
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

/// How the editor paints its chrome.
///
/// [panel] is the compact framed field used inside editor panels and presenter
/// notes. [document] is the roomy word-processor surface used by the expand
/// dialog: one clean toolbar header and a centred page you write on.
enum NotesSurfaceStyle { panel, document }

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
  final NotesSurfaceStyle surfaceStyle;

  /// Documentmodus: maximale schrijfbreedte in px, of `null` voor volledige
  /// breedte. Alleen van toepassing bij [NotesSurfaceStyle.document].
  /// Feature 2.
  final double? documentMaxWidth;

  /// Doorgegeven aan de Quill-editor in de visuele stand; zie
  /// [WysiwygNotesField.editorKey].
  final GlobalKey<EditorState>? editorKey;

  /// Verhoog om de editor naar [revealMarkdownOffset] / [revealTitle] te laten
  /// springen (Overzicht-rail). Quill zoekt op titel in platte tekst; markdown-
  /// modus zet de controller-cursor op de bron-offset.
  final int revealSignal;
  final int? revealMarkdownOffset;
  final String? revealTitle;

  /// Caret in Quill-modus (platte-tekst-offset + documenttekst), zodat de
  /// Overzicht-rail mee kan lopen. In markdown-modus luistert de ouder naar
  /// [controller].
  final void Function(String plain, int offset)? onVisualCaret;

  /// Verhoog om [insertMarkdownBlock] als eigen blok op de cursor in te voegen.
  ///
  /// Alleen voor de visuele stand: daar leeft de tekst in het Quill-document en
  /// staat de bron-cursor van de ouder stil, waardoor een invoeging via de bron
  /// altijd onderaan het document belandde in plaats van waar je stond. In de
  /// markdown-stand doet de ouder de invoeging zelf op de bron-cursor.
  final int insertSignal;
  final String? insertMarkdownBlock;

  /// Optioneel: vang plakken af (afbeelding/tabel) vóór de standaard tekstplak.
  final Future<bool> Function()? tryConsumePaste;

  /// Wanneer gezet: de Afbeelding-knop in de markdown-opmaakbalk opent de
  /// kiezer i.p.v. een placeholder in de bron te zetten.
  final VoidCallback? onInsertImage;

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
    this.surfaceStyle = NotesSurfaceStyle.panel,
    this.documentMaxWidth,
    this.editorKey,
    this.revealSignal = 0,
    this.revealMarkdownOffset,
    this.revealTitle,
    this.onVisualCaret,
    this.insertSignal = 0,
    this.insertMarkdownBlock,
    this.tryConsumePaste,
    this.onInsertImage,
  });

  /// Convenience constructor using discrete color/style parameters.
  factory MarkdownNotesEditor.legacy({
    Key? key,
    required TextEditingController controller,
    FocusNode? focusNode,
    required TextStyle baseStyle,
    required Color linkColor,
    Color codeBackground = AppTheme.shadow10,
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
        : AppTheme.userNotesBorder;
    return MarkdownNotesEditor(
      key: key,
      controller: controller,
      focusNode: focusNode,
      editorTheme: MarkdownEditorTheme.editorPanel(
        text: baseStyle.color ?? AppTheme.slate800,
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

  /// Of de gebruiker in de visuele stand echt iets heeft gewijzigd.
  ///
  /// De heen-en-terugweg door de rijke-tekstlaag is niet verliesvrij: een
  /// markdowntabel komt er als losse woorden uit en `\*` verliest zijn
  /// backslash. Zonder deze vlag schreef alleen al het aanzetten en weer
  /// uitzetten van de visuele stand die schade terug in de tekst. Wie niets
  /// wijzigt, houdt nu letterlijk wat er stond.
  bool _visualEdited = false;

  NotesEditorMode get _requestedMode => widget.mode ?? _mode;

  Set<MarkdownVisualLimitation> get _visualLimitations =>
      markdownVisualLimitations(widget.controller.text);

  NotesEditorMode get _effectiveMode =>
      _requestedMode == NotesEditorMode.visual && _visualLimitations.isNotEmpty
      ? NotesEditorMode.markdown
      : _requestedMode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  bool get _document => widget.surfaceStyle == NotesSurfaceStyle.document;

  /// The document surface frames the whole page itself, so the field inside
  /// drops its own border to read as one continuous sheet.
  bool get _fieldBordered => _document ? false : widget.bordered;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (widget.mode == null &&
        _mode == NotesEditorMode.visual &&
        _visualLimitations.isNotEmpty) {
      _mode = NotesEditorMode.markdown;
    }
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
    final target = _effectiveMode;
    if (target == NotesEditorMode.visual && _quillController == null) {
      _openVisualEditor();
    } else if (target == NotesEditorMode.markdown && _quillController != null) {
      // An externally supplied unsupported construct must never be overwritten
      // by flushing the older rich-text projection back to Markdown.
      _closeVisualEditor(flush: _visualLimitations.isEmpty);
    }
    if (widget.controller.text != _markdownSnapshot &&
        !_syncingMarkdown &&
        target == NotesEditorMode.visual) {
      _reloadVisualFromMarkdown();
    }
    if (widget.insertSignal != oldWidget.insertSignal) {
      // Na het build-frame: een documentwijziging tijdens didUpdateWidget mag
      // niet (zelfde reden als bij het springen hieronder).
      final block = widget.insertMarkdownBlock;
      final signal = widget.insertSignal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.insertSignal != signal || block == null) return;
        _insertMarkdownBlockAtCaret(block);
      });
    }
    if (widget.revealSignal != oldWidget.revealSignal) {
      // Na het build-frame: caret-sync in de ouder mag geen setState/edit
      // tijdens didUpdateWidget doen.
      final signal = widget.revealSignal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.revealSignal != signal) return;
        _revealFromOutline(widget.revealMarkdownOffset, widget.revealTitle);
      });
    }
  }

  /// Voeg [block] als eigen blok in op de Quill-cursor.
  ///
  /// De regel waarin de cursor staat blijft heel: het blok komt eronder, of
  /// óp de plek zelf als die regel leeg is. Zo landt een tabel niet halverwege
  /// een zin. Het blok gaat eerst door dezelfde markdown→Quill-omzetting als de
  /// rest, zodat een tabel of inhoudsopgave meteen als embed verschijnt.
  void _insertMarkdownBlockAtCaret(String block) {
    final quill = _quillController;
    if (quill == null) return;
    final blockDelta = MarkdownQuillCodec.documentFromMarkdown(block).toDelta();
    if (blockDelta.isEmpty) return;
    final (at, ownLine) = _blockInsertOffset(quill);
    final change = Delta()..retain(at);
    if (ownLine) change.insert('\n');
    quill.compose(
      change.concat(blockDelta),
      TextSelection.collapsed(
        offset: at + (ownLine ? 1 : 0) + blockDelta.length,
      ),
      ChangeSource.local,
    );
  }

  /// Waar een nieuw blok mag landen, en of het zelf nog een regel moet openen.
  ///
  /// Op de laatste regel van het document kan dat niet met een regelgrens: het
  /// document sluit af met een regelafsluiter en Quill weigert een invoeging
  /// dáárachter. Dan landt het blok vlak vóór die afsluiter, met een eigen
  /// regelafsluiter ervoor — anders plakt het aan de laatste zin vast.
  (int, bool) _blockInsertOffset(QuillController quill) {
    final end = quill.document.length - 1;
    final caret = quill.selection.isValid
        ? quill.selection.baseOffset.clamp(0, end)
        : end;
    final line = quill.document.queryChild(caret).node;
    if (line == null) return (end, true);
    // `length` telt de regelafsluiter mee: een lege regel is precies 1 lang.
    if (line.length <= 1) return (line.documentOffset, false);
    final next = line.documentOffset + line.length;
    return next <= end ? (next, false) : (end, true);
  }

  /// Spring naar een Overzicht-kop: in markdown-modus de bron-cursor, in Quill
  /// de eerste treffer van de titel in de platte tekst.
  void _revealFromOutline(int? markdownOffset, String? title) {
    if (_effectiveMode == NotesEditorMode.markdown) {
      final text = widget.controller.text;
      final offset = (markdownOffset ?? 0).clamp(0, text.length);
      widget.controller.selection = TextSelection.collapsed(offset: offset);
      _focusNode.requestFocus();
      return;
    }
    final quill = _quillController;
    if (quill == null) return;
    final plain = quill.document.toPlainText();
    var index = 0;
    if (title != null && title.isNotEmpty) {
      final found = plain.indexOf(title);
      if (found >= 0) index = found;
    }
    quill.updateSelection(
      TextSelection.collapsed(offset: index.clamp(0, plain.length)),
      ChangeSource.local,
    );
    _focusNode.requestFocus();
    widget.onVisualCaret?.call(plain, index);
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
      document: MarkdownQuillCodec.documentFromMarkdown(
        normalizeRichTextMarkdown(widget.controller.text),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _markdownSnapshot = widget.controller.text;
    _visualEdited = false;
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
    quill.document = MarkdownQuillCodec.documentFromMarkdown(
      normalizeRichTextMarkdown(_markdownSnapshot),
    );
    _visualEdited = false;
    _syncingMarkdown = false;
  }

  void _flushQuillToController(QuillController quill) {
    if (!_visualEdited) return;
    final markdown = MarkdownQuillCodec.markdownFromDocument(quill.document);
    if (markdown == widget.controller.text) {
      _markdownSnapshot = markdown;
      return;
    }
    _syncingMarkdown = true;
    _markdownSnapshot = markdown;
    widget.controller.value = _valueWithClampedSelection(markdown);
    _syncingMarkdown = false;
  }

  /// Nieuwe tekst met de bestaande cursorpositie, begrensd op de nieuwe
  /// lengte: `copyWith(text:)` zou een selectie buiten de tekst laten staan.
  TextEditingValue _valueWithClampedSelection(String text) {
    final sel = widget.controller.selection;
    final offset = sel.isValid
        ? sel.baseOffset.clamp(0, text.length)
        : text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  void _onQuillChanged() {
    if (_syncingMarkdown) return;
    final quill = _quillController;
    if (quill == null) return;
    final plain = quill.document.toPlainText();
    final caret = quill.selection.isValid ? quill.selection.baseOffset : 0;
    widget.onVisualCaret?.call(plain, caret.clamp(0, plain.length));
    final markdown = MarkdownQuillCodec.markdownFromDocument(quill.document);
    if (markdown == _markdownSnapshot) return;
    _visualEdited = true;
    _syncingMarkdown = true;
    _markdownSnapshot = markdown;
    widget.controller.value = _valueWithClampedSelection(markdown);
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
    if (mode == NotesEditorMode.visual && _visualLimitations.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d(
              'Visuele bewerking is uitgeschakeld omdat deze Markdown niet verliesvrij kan worden omgezet.',
            ),
          ),
        ),
      );
      return;
    }
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
    final field = Container(
      width: double.infinity,
      constraints: widget.expand
          ? null
          : BoxConstraints(minHeight: widget.minLines * 22.0),
      decoration: BoxDecoration(
        color: widget.editorTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: _fieldBordered
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
    if (widget.tryConsumePaste == null) return field;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _NotesSmartPasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            _NotesSmartPasteIntent(),
      },
      child: Actions(
        actions: {
          _NotesSmartPasteIntent: CallbackAction<_NotesSmartPasteIntent>(
            onInvoke: (_) {
              unawaited(_pasteMarkdownSmart());
              return null;
            },
          ),
        },
        child: field,
      ),
    );
  }

  Future<void> _pasteMarkdownSmart() async {
    if (widget.tryConsumePaste != null && await widget.tryConsumePaste!()) {
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final sel = widget.controller.selection;
    final start = sel.isValid ? sel.start : widget.controller.text.length;
    final end = sel.isValid ? sel.end : start;
    final value = widget.controller.text;
    final next = value.replaceRange(start, end, text);
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
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
      bordered: _fieldBordered,
      tryConsumePaste: widget.tryConsumePaste,
      editorKey: widget.editorKey,
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

  Widget _buildModeToggle() => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.5,
    child: NotesModeToggle(
      mode: _effectiveMode,
      onModeChanged: _onModeSelected,
      style: widget.modeToggleStyle,
      foregroundColor: widget.editorTheme.toolbarIcon,
      accentColor: widget.editorTheme.accent,
    ),
  );

  Widget? _buildToolbar({required bool bordered}) {
    if (!widget.showToolbar) return null;
    final quill = _quillController;
    final Widget bar;
    if (_effectiveMode == NotesEditorMode.markdown) {
      bar = MarkdownEditorToolbar(
        controller: widget.controller,
        focusNode: _focusNode,
        theme: widget.editorTheme,
        compact: widget.compactToolbar,
        bordered: bordered,
        onInsertImage: widget.onInsertImage,
      );
    } else if (quill != null) {
      bar = WysiwygNotesToolbar(
        controller: quill,
        focusNode: _focusNode,
        theme: widget.editorTheme,
        compact: widget.compactToolbar,
        bordered: bordered,
      );
    } else {
      return null;
    }
    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.5, child: bar);
  }

  Widget? _buildLimitationHint() {
    if (_visualLimitations.isEmpty ||
        _effectiveMode != NotesEditorMode.markdown) {
      return null;
    }
    return markdownSourceModeHint(context, widget.editorTheme);
  }

  @override
  Widget build(BuildContext context) =>
      _document ? _buildDocumentLayout() : _buildPanelLayout();

  Widget _buildPanelLayout() {
    final toolbar = _buildToolbar(bordered: true);
    final hint = _buildLimitationHint();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showModeToggle) ...[
          _buildModeToggle(),
          const SizedBox(height: 6),
        ],
        if (toolbar != null) ...[toolbar, const SizedBox(height: 6)],
        if (hint != null)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: hint),
        _buildEditorSurface(),
      ],
    );
  }

  /// Roomy word-processor surface: one clean header (switch + toolbar over a
  /// hairline) and a centred page you write on. Used by the expand dialog.
  Widget _buildDocumentLayout() {
    final toolbar = _buildToolbar(bordered: false);
    final hint = _buildLimitationHint();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: widget.editorTheme.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showModeToggle) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildModeToggle(),
                ),
                if (toolbar != null) const SizedBox(height: 8),
              ],
              ?toolbar,
            ],
          ),
        ),
        if (hint != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: hint),
        Expanded(child: _buildDocumentPage()),
      ],
    );
  }

  Widget _buildDocumentPage() {
    final field = _effectiveMode == NotesEditorMode.visual
        ? _buildVisualField()
        : _buildMarkdownField();
    final maxW = widget.documentMaxWidth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW ?? double.infinity),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.editorTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.editorTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: field,
          ),
        ),
      ),
    );
  }
}

/// The gentle "source mode protects formatting the visual editor can't yet
/// round-trip" note, shown when raw markdown is required.
Widget markdownSourceModeHint(BuildContext context, MarkdownEditorTheme theme) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.shield_outlined, size: 14, color: theme.toolbarIcon),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          context.l10n.d(
            'Bronmodus beschermt opmaak die de visuele editor nog niet verliesvrij ondersteunt.',
          ),
          style: theme.hintStyle.copyWith(fontSize: 10.5),
        ),
      ),
    ],
  );
}

class _NotesSmartPasteIntent extends Intent {
  const _NotesSmartPasteIntent();
}
