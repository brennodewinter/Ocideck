import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';

import '../../models/settings.dart' show ThemeProfile;
import '../../models/slide.dart';
import '../../services/markdown_table_codec.dart';
import '../reader/document_markdown_view.dart';
import '../reader/table_edit_controller.dart';
import 'markdown_editor_theme.dart';

/// Tekent een `x-embed-table`-blok in de visuele (Quill) editor als een échte,
/// gerenderde tabel — dezelfde weergave als de documentlezer — en laat je er
/// rechtstreeks in typen: klik in een cel en vul hem in, zoals in een rekenblad.
///
/// Dat verving een dialoog met losse velden van gelijke breedte. Daar zag je
/// niet wat je kreeg, terwijl juist bij een tabel de vorm de helft van de
/// leesbaarheid is. Nu herschikt de tabel terwijl je typt — de kolombreedtes
/// worden per toetsaanslag opnieuw gekozen, precies zoals ze in het document
/// komen te staan. Dat is het voordeel van Markdown als drager: de tabel heeft
/// geen vaste kolommaten die je met de hand goed moet zetten.
///
/// Elke wijziging schrijft de tabel byte-getrouw terug in de embed; de
/// markdown-round-trip (`MarkdownQuillCodec`) serialiseert hem weer als
/// GFM-tabel. Dit is ook de reden dat een tabel geen visuele-modus-beperking
/// meer is (`markdownVisualLimitations`): waar de heen-en-terugweg door de
/// platte rijke-tekstlaag een tabel tot losse woorden maalde, blijft hij nu één
/// blok.
class TableEmbedBuilder extends EmbedBuilder {
  const TableEmbedBuilder();

  @override
  String get key => EmbeddableTable.tableType;

  /// Een tabel is een blok, geen inline-teken: hij vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final gfm = (embedContext.node.value.data ?? '').toString().trimRight();
    final profile = DocumentStyleScope.maybeOf(context);
    // Alleen-lezen (bijv. een niet-bewerkbare weergave): render de tabel zonder
    // invulbare cellen.
    if (embedContext.readOnly) {
      return DocumentMarkdownView(
        gfm,
        maxTextWidth: null,
        themeProfile: profile,
        chartTheme: profile,
      );
    }
    return _EditableTableEmbed(
      gfm: gfm,
      profile: profile,
      embedContext: embedContext,
    );
  }
}

/// Houdt de [TableEditController] van één embed vast — die leeft zolang de
/// tabel in beeld is, niet per opbouw, anders zou elke toetsaanslag de cursor
/// en de focus kwijtraken.
class _EditableTableEmbed extends StatefulWidget {
  const _EditableTableEmbed({
    super.key,
    required this.gfm,
    required this.profile,
    required this.embedContext,
  });

  final String gfm;
  final ThemeProfile? profile;
  final EmbedContext embedContext;

  @override
  State<_EditableTableEmbed> createState() => _EditableTableEmbedState();
}

class _EditableTableEmbedState extends State<_EditableTableEmbed> {
  late TableEditController _editor;

  @override
  void initState() {
    super.initState();
    _editor = _makeController(widget.gfm);
  }

  @override
  void didUpdateWidget(_EditableTableEmbed old) {
    super.didUpdateWidget(old);
    // De bron verandert normaal alleen dóór ons eigen terugschrijven; komt er
    // van buiten een andere tabel binnen (ongedaan maken, samenwerking), dan
    // begint de bewerkstaat opnieuw.
    if (widget.gfm !=
        encodeMarkdownTable(_editor.rows, alignments: _editor.alignments)) {
      _editor.dispose();
      _editor = _makeController(widget.gfm);
    }
  }

  TableEditController _makeController(String gfm) {
    final decoded = decodeMarkdownTableWithAlignment(gfm.split('\n'));
    return TableEditController(
      rows: decoded.rows,
      alignments: decoded.alignments,
      onChanged: _writeBack,
    );
  }

  /// De tabel die nog naar het document moet; `null` als er niets wacht.
  String? _pending;
  bool _flushScheduled = false;

  /// Plant het terugschrijven ná deze frame in plaats van er middenin.
  ///
  /// Terugschrijven vervángt de embed-knoop, en koppelt daarmee de knoop los
  /// waar dit blok aan hangt. Twee schrijfacties in dezelfde frame zouden de
  /// tweede dus op een losgekoppelde knoop laten landen: die heeft
  /// `documentOffset` 0, en de tabel werd bovenaan het document geplakt, dwars
  /// door de tekst heen. Eén schrijfactie per frame, met de laatste stand,
  /// houdt de knoop heel — en scheelt bovendien een ongedaan-stap per aanslag.
  void _writeBack(List<List<String>> rows, List<TableAlign> alignments) {
    _pending = encodeMarkdownTable(rows, alignments: alignments);
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted) _flush();
    });
  }

  void _flush() {
    final gfm = _pending;
    _pending = null;
    if (gfm == null || gfm == widget.gfm) return;
    final node = widget.embedContext.node;
    if (node.parent == null) return;
    // De embed heeft lengte 1 in het Quill-document: dit vervangt exact dit
    // blok en laat de rest van de tekst — en de cursor daarbuiten — met rust.
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableTable(gfm),
      null,
    );
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DocumentMarkdownView(
    widget.gfm,
    maxTextWidth: null,
    themeProfile: widget.profile,
    chartTheme: widget.profile,
    tableEditController: _editor,
  );
}
