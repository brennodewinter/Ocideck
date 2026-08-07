import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';

import '../../models/slide.dart';
import '../../services/markdown_table_codec.dart';
import '../editors/embed_editor_dialog.dart';
import '../editors/table_editor.dart';
import '../reader/document_markdown_view.dart';

/// Tekent een `x-embed-table`-blok in de visuele (Quill) editor als een échte,
/// gerenderde tabel — dezelfde weergave als de documentlezer, met potlood/
/// dubbelklik om de volwaardige [TableEditor] te openen. 'Toepassen' schrijft de
/// bewerkte tabel byte-getrouw terug in de embed; de markdown-round-trip
/// (`MarkdownQuillCodec`) serialiseert hem weer als GFM-tabel.
///
/// Dit is de reden dat een tabel geen visuele-modus-beperking meer is
/// (`markdownVisualLimitations`): waar de heen-en-terugweg door de platte
/// rijke-tekstlaag een tabel tot losse woorden maalde, blijft hij nu één blok.
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
    // Alleen-lezen (bijv. een niet-bewerkbare weergave): render zonder potlood.
    final onEdit = embedContext.readOnly
        ? null
        : (int _, List<String> _) => _editTable(context, embedContext, gfm);
    return DocumentMarkdownView(gfm, maxTextWidth: null, onEditTable: onEdit);
  }

  /// Open de [TableEditor] op de huidige tabel en schrijf het resultaat terug in
  /// de embed. De kolomuitlijning komt uit de scheidingsrij van [gfm]; bij
  /// 'Toepassen' serialiseren raster én uitlijning terug naar een GFM-tabel die
  /// exact dit embed-blok vervangt (lengte 1 in het Quill-document).
  Future<void> _editTable(
    BuildContext context,
    EmbedContext embedContext,
    String gfm,
  ) async {
    final decoded = decodeMarkdownTableWithAlignment(gfm.split('\n'));
    var rows = decoded.rows;
    var aligns = decoded.alignments;
    final slide = Slide.create(SlideType.table).copyWith(
      tableRows: decoded.rows,
      tableColumnAlignments: decoded.alignments,
    );
    final apply = await showEmbedEditorDialog(
      context,
      TableEditor(
        slide: slide,
        nestedInScrollView: true,
        documentContext: true,
        onUpdate: (s) {
          rows = s.tableRows;
          aligns = s.tableColumnAlignments;
        },
      ),
    );
    if (apply != true) return;
    final offset = embedContext.node.documentOffset;
    embedContext.controller.replaceText(
      offset,
      1,
      EmbeddableTable(encodeMarkdownTable(rows, alignments: aligns)),
      TextSelection.collapsed(offset: offset + 1),
    );
  }
}
