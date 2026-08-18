import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/footnote_embed_syntax.dart';
import '../reader/document_markdown_view.dart';

/// De volgnummers van de voetnoten in [document], op leesvolgorde.
///
/// Uit het Quill-document zelf en niet uit de bron: tijdens het typen ís het
/// Quill-document de waarheid, en een nummer dat een halve seconde achterloopt
/// op wat je net hebt ingevoegd leest als een fout. Dezelfde regel als in de
/// weergave — doornummeren in de volgorde waarin de tekst verwijst.
Map<String, int> footnoteNumbersInDocument(Document document) {
  final numbers = <String, int>{};
  for (final node in document.root.children) {
    for (final leaf in node is Line ? node.children : const <Node>[]) {
      if (leaf is! Embed) continue;
      if (leaf.value.type != EmbeddableFootnoteRef.footnoteRefType) continue;
      final label = EmbeddableFootnoteRef.labelOf(leaf.value);
      if (label.isEmpty) continue;
      numbers.putIfAbsent(label, () => numbers.length + 1);
    }
  }
  return numbers;
}

/// Tekent `[^1]` in de visuele editor als het volgnummer in superscript.
///
/// Zonder deze builder — en de embed eronder — viel het hele document terug op
/// brontekst zodra iemand een voetnoot maakte: `[^1]` viel door de
/// rijke-tekstlaag uiteen in losse tekens.
class FootnoteRefEmbedBuilder extends EmbedBuilder {
  const FootnoteRefEmbedBuilder();

  @override
  String get key => EmbeddableFootnoteRef.footnoteRefType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final label = EmbeddableFootnoteRef.labelOf(embedContext.node.value);
    final number = footnoteNumbersInDocument(
      embedContext.controller.document,
    )[label];
    final style = DefaultTextStyle.of(context).style;
    final scheme = Theme.of(context).colorScheme;
    return Transform.translate(
      // Een merkteken hoort hoog op de regel te staan; zonder deze verschuiving
      // zakt de kleinere letter naar de basislijn en leest hij als een getal in
      // de tekst.
      offset: Offset(0, -(style.fontSize ?? 15) * 0.35),
      child: Text(
        '${number ?? label}',
        style: style.copyWith(
          fontSize: (style.fontSize ?? 15) * 0.72,
          height: 1,
          color: scheme.primary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Tekent `[^1]: de noot` in de visuele editor als een invulbare notenregel.
///
/// De definitie blijft staan waar de auteur hem in het bestand zette — dat is
/// waarom de verwijzing en de definitie twee embeds zijn en niet één. Wat je
/// hier typt gaat byte-getrouw terug de bron in.
class FootnoteDefEmbedBuilder extends EmbedBuilder {
  const FootnoteDefEmbedBuilder();

  @override
  String get key => EmbeddableFootnoteDef.footnoteDefType;

  /// Een definitie is een blok: hij vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final note = EmbeddableFootnoteDef.parse(embedContext.node.value);
    final number = footnoteNumbersInDocument(
      embedContext.controller.document,
    )[note.label];
    if (embedContext.readOnly) {
      return _FootnoteRow(
        number: number,
        label: note.label,
        child: Text(note.text, style: _noteStyle(context)),
      );
    }
    return _EditableFootnoteDef(
      key: ValueKey(note.label),
      label: note.label,
      text: note.text,
      number: number,
      embedContext: embedContext,
    );
  }
}

TextStyle _noteStyle(BuildContext context) {
  final style = DefaultTextStyle.of(context).style;
  return style.copyWith(
    fontSize: (style.fontSize ?? kDocumentBodyFontSize) * 0.85,
    height: 1.35,
  );
}

/// De vaste vorm van een notenregel: het nummer in de kantlijn, de tekst
/// ernaast. Gedeeld door de lees- en de bewerkstand zodat de regel niet
/// verspringt op het moment dat je erin klikt.
class _FootnoteRow extends StatelessWidget {
  const _FootnoteRow({
    required this.number,
    required this.label,
    required this.child,
  });

  final int? number;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 20,
            margin: const EdgeInsets.only(right: 8, top: 2),
            color: scheme.outlineVariant,
          ),
          SizedBox(
            width: 22,
            child: Text(
              // Geen nummer betekent: er verwijst niets (meer) naar deze noot.
              // Dan het label tonen, want dat is het enige aanknopingspunt om
              // hem terug te vinden in de tekst.
              number == null ? label : '$number',
              style: _noteStyle(context).copyWith(
                color: number == null ? scheme.error : scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _EditableFootnoteDef extends StatefulWidget {
  const _EditableFootnoteDef({
    super.key,
    required this.label,
    required this.text,
    required this.number,
    required this.embedContext,
  });

  final String label;
  final String text;
  final int? number;
  final EmbedContext embedContext;

  @override
  State<_EditableFootnoteDef> createState() => _EditableFootnoteDefState();
}

class _EditableFootnoteDefState extends State<_EditableFootnoteDef> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  final FocusNode _focus = FocusNode();

  /// De tekst die nog naar het document moet; `null` als er niets wacht.
  String? _pending;
  bool _flushScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_write);
    // Een verse noot is leeg en staat er omdat je er net om vroeg: dan hoort de
    // cursor er ook meteen in te staan.
    if (widget.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(_EditableFootnoteDef old) {
    super.didUpdateWidget(old);
    // Komt er van buiten een andere tekst binnen (ongedaan maken,
    // samenwerking), dan wint die — maar niet terwijl je zelf typt.
    if (widget.text != _controller.text && !_focus.hasFocus) {
      _controller
        ..removeListener(_write)
        ..text = widget.text
        ..addListener(_write);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Plant het terugschrijven ná deze frame in plaats van er middenin.
  ///
  /// Dezelfde reden als bij de tabel-embed: terugschrijven vervangt de
  /// embed-knoop, en twee schrijfacties in één frame laten de tweede op een
  /// losgekoppelde knoop landen — die heeft `documentOffset` 0, en dan plakt de
  /// noot bovenaan het document dwars door de tekst heen.
  void _write() {
    _pending = _controller.text;
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted) _flush();
    });
  }

  void _flush() {
    final text = _pending;
    _pending = null;
    if (text == null || text == widget.text) return;
    final node = widget.embedContext.node;
    if (node.parent == null) return;
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableFootnoteDef(widget.label, text),
      null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _noteStyle(context);
    return _FootnoteRow(
      number: widget.number,
      label: widget.label,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: style,
        maxLines: null,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: context.l10n.d('De tekst van de voetnoot'),
          hintStyle: style.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
