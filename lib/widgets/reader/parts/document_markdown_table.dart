// Part of the document-markdown-view library — see ../document_markdown_view.dart.
//
// Het tabelblok van de documentweergave: de breedtebeslissing (past hij, of
// scrollt hij), de gestileerde tabel (zebra, randstijl, koprij-accent) en de
// cel — zowel de gelezen cel als de ter plekke invulbare. Losgeknipt van
// document_markdown_view.dart om dat bestand onder het regelplafond te houden;
// één library, dus de weergave gebruikt ze ongewijzigd.
part of '../document_markdown_view.dart';

/// De horizontale uitlijning voor kolom [c] uit de GFM-scheidingsrij; buiten
/// bereik → links (de GFM-default).
TextAlign _columnTextAlign(List<TableAlign> aligns, int c) {
  if (c >= aligns.length) return TextAlign.start;
  return switch (aligns[c]) {
    TableAlign.left => TextAlign.start,
    TableAlign.center => TextAlign.center,
    TableAlign.right => TextAlign.end,
  };
}

/// De tabelopbouw van [DocumentMarkdownView]. Een extensie op de weergave zelf
/// (zelfde library), zodat de methoden ongewijzigd blijven werken.
extension _DocumentMarkdownTable on DocumentMarkdownView {
  Widget _table(
    _Theme t,
    List<String> rows,
    List<TableAlign> sourceAligns,
    int tableOrdinal,
  ) {
    // Controller loopt voor op de bron: die volgt pas ná de celwijziging.
    final editor =
        tableEditorFor?.call(tableOrdinal) ??
        (tableOrdinal == 0 ? tableEditController : null);
    if (editor != null) {
      // Geen potlood: je klikt in de cel. Hertekenen houdt de kolombreedtes bij.
      return TableEditScaffold(
        editor: editor,
        onSort: onSortTableColumn,
        extraToolbarItems: tableToolbarExtras,
        builder: (_) => _tableBody(t, editor.rows, editor.alignments, editor),
      );
    }
    return _tableBody(
      t,
      rows.map(splitMarkdownTableRow).toList(),
      sourceAligns,
      null,
    );
  }

  /// Het tabelblok zelf: de kolomverdeling en de gestileerde tabel, los van de
  /// vraag of hij invulbaar is. Eén opbouw voor lezen en voor invullen — zo
  /// kán de invulbare tabel er niet anders uitzien dan de gelezen.
  Widget _tableBody(
    _Theme t,
    List<List<String>> cells,
    List<TableAlign> aligns,
    TableEditController? editor,
  ) {
    final columns = cells.isEmpty
        ? 0
        : cells.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    if (columns == 0) return const SizedBox.shrink();

    // Feature 1: een tabel past binnen de beschikbare breedte met optimale
    // kolomverdeling (hergebruik tableColumnWidths uit de slide-preview). Pas
    // horizontaal scrollen toe wanneer de kolomminima samen breder zijn dan de
    // beschikbare breedte — de inhoud past dan echt niet kleiner.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avail = constraints.maxWidth;
          // Document-tabellen lezen op een vaste, leesbare celmaat (geen
          // slide-fitting): body 14px, kop 13px. Een document is geen 16:9-dia.
          const cellSize = 14.0;
          const headerCellSize = 13.0;
          final font = t.body.fontFamily ?? 'sans-serif';
          // De marge waarmee de cel écht getekend wordt (zie [_tableCell]).
          // Meten met de preview-marge rekende de kolom een paar pixels rijker
          // dan ze is, en dan schoof er alsnog een letter naar de volgende
          // regel.
          final hPad = t.tableCellPad + 4;
          final minSum = tableColumnMinimumsWidth(
            rows: cells,
            colCount: columns,
            cellSize: cellSize,
            font: font,
            hPad: hPad,
          );
          final fits = avail.isFinite && avail > 0 && minSum <= avail * 0.95;
          final colWidths = fits
              ? tableColumnWidths(
                  rows: cells,
                  colCount: columns,
                  tableWidth: avail,
                  cellSize: cellSize,
                  font: font,
                  hPad: hPad,
                )
              : null;
          final tableWidget = _styledTable(
            t,
            cells,
            columns,
            aligns,
            colWidths,
            cellSize,
            headerCellSize,
            editor,
          );
          // Past de tabel niet binnen de breedte, dan valt hij terug op
          // horizontale scroll met intrinsieke kolombreedtes — het bestaande
          // gedrag, voor het uitzonderingsgeval dat de inhoud niet kleiner kan.
          if (fits) return tableWidget;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: tableWidget,
          );
        },
      ),
    );
  }

  /// De gestileerde tabel zelf, los van de breedte-beslissing. Feature 5:
  /// zebrastrepen, randstijl (lined/boxed/none), celopvulling en een
  /// accentkleurige onderrand onder de koprij — allemaal huisstijl uit het
  /// ThemeProfile.
  Widget _styledTable(
    _Theme t,
    List<List<String>> cells,
    int columns,
    List<TableAlign> aligns,
    List<double>? colWidths,
    double cellSize,
    double headerCellSize,
    TableEditController? editor,
  ) {
    final pad = t.tableCellPad;
    final border = t.tableBorder;
    final hasBox = t.tableBorderStyle == TableBorderStyle.boxed;
    final hasLines = t.tableBorderStyle == TableBorderStyle.lined;
    // Buitenrand alleen bij boxed; lined en none leunen op binnenlijnen of
    // witruimte.
    final outer = hasBox
        ? Border.all(color: border)
        : hasLines
        ? Border(bottom: BorderSide(color: border))
        : null;
    final inside = switch (t.tableBorderStyle) {
      TableBorderStyle.boxed => TableBorder.symmetric(
        inside: BorderSide(color: border.withValues(alpha: 0.5)),
      ),
      TableBorderStyle.lined => TableBorder(
        horizontalInside: BorderSide(color: border.withValues(alpha: 0.5)),
        top: BorderSide(color: border),
        // de koprij krijgt een eigen accentlijn hieronder; voorkom dubbel.
        bottom: BorderSide(color: border),
      ),
      TableBorderStyle.none => TableBorder.all(
        width: 0,
        color: Colors.transparent,
      ),
    };
    final accentHeaderLine = t.tableAccentHeaderBorder
        ? Border(bottom: BorderSide(color: t.tableAccent, width: 2))
        : null;
    return Container(
      decoration: BoxDecoration(
        border: outer,
        borderRadius: hasBox ? BorderRadius.circular(8) : null,
      ),
      clipBehavior: hasBox ? Clip.antiAlias : Clip.none,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        columnWidths: colWidths == null
            ? null
            : {
                for (var c = 0; c < columns; c++)
                  c: FixedColumnWidth(colWidths[c]),
              },
        border: inside,
        children: [
          for (var r = 0; r < cells.length; r++)
            TableRow(
              decoration: BoxDecoration(
                color: r == 0
                    ? t.tableHeaderBg
                    : t.tableZebraStriped && r.isEven
                    ? t.tableZebraBg
                    : null,
                border: r == 0 ? accentHeaderLine : null,
              ),
              children: [
                for (var c = 0; c < columns; c++)
                  if (editor != null)
                    TableEditableCell(
                      editor: editor,
                      row: r,
                      column: c,
                      linkColor: t.link,
                      codeBackground: t.inlineCodeBg,
                      style: _cellStyle(
                        t,
                        header: r == 0,
                        cellSize: r == 0 ? headerCellSize : cellSize,
                      ),
                      textAlign: _columnTextAlign(aligns, c),
                      pad: pad,
                      caretColor: t.tableAccent,
                    )
                  else
                    _tableCell(
                      t,
                      c < cells[r].length ? cells[r][c] : '',
                      header: r == 0,
                      textAlign: _columnTextAlign(aligns, c),
                      pad: pad,
                      cellSize: r == 0 ? headerCellSize : cellSize,
                    ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tableCell(
    _Theme t,
    String text, {
    required bool header,
    TextAlign textAlign = TextAlign.start,
    double pad = 8.0,
    double cellSize = 14.0,
  }) => Padding(
    padding: EdgeInsets.symmetric(horizontal: pad + 4, vertical: pad * 0.6),
    child: _inline(
      text,
      _cellStyle(t, header: header, cellSize: cellSize),
      t,
      textAlign: textAlign,
    ),
  );
}

/// De tekststijl van een cel — gedeeld door de gelezen cel en de invulbare,
/// zodat typen er precies zo uitziet als lezen.
///
/// Top-level en niet in de weergave-extensie: hij gebruikt geen enkel veld van
/// [DocumentMarkdownView], en de klasse staat op zijn plafond.
TextStyle _cellStyle(
  _Theme t, {
  required bool header,
  required double cellSize,
}) => header
    ? t.body.copyWith(
        fontSize: cellSize,
        fontWeight: FontWeight.w700,
        color: t.tableHeaderText,
      )
    : t.body.copyWith(fontSize: cellSize, color: t.tableText);

/// Een run `<!-- ocideck:* -->`-markers op regel [i] van [lines]. Markers zijn
/// machine-metadata: het contract belooft dat een lezer ze negeert, dus is de
/// run onzichtbaar — behalve als een `bowtie`-drager aan een tabel bindt: die
/// tabel wordt dan een [_Block] mét bron (marker + tabel), zodat
/// [_tableOrBowtie] hem elders als afgeleid diagram kan tonen (#2496).
/// Geeft de regelindex ná de run terug.
///
/// Top-level, zoals [_parseTableAt] zelf: puur over de regellijst, en de
/// klasse staat op haar plafond.
int _skipOciMarkers(List<String> lines, int i, List<_Block> blocks) {
  var mEnd = i;
  String? carrier;
  while (mEnd < lines.length && isOciTableMarkerLine(lines[mEnd])) {
    final m = parseOciTableMarker(lines[mEnd]);
    if (carrier == null && m != null && m.kind != OciMarkerKinds.calc) {
      carrier = m.kind;
    }
    mEnd++;
  }
  var j = mEnd;
  while (j < lines.length && lines[j].trim().isEmpty) {
    j++;
  }
  final boundTable =
      j + 1 < lines.length &&
      isMarkdownTableLine(lines[j]) &&
      isMarkdownTableDelimiterRow(lines[j + 1]);
  if (carrier == OciMarkerKinds.bowtie && boundTable) {
    final parsed = _parseTableAt(lines, j);
    blocks.add(
      _Block(
        _Kind.table,
        rows: parsed.block.rows,
        aligns: parsed.block.aligns,
        source: lines.sublist(i, parsed.end).join('\n'),
      ),
    );
    return parsed.end;
  }
  return mEnd;
}

/// Een `<!-- ocideck:bowtie -->`-tabel (#2496): waar geen cel-editor aan hangt
/// (lezer, Pagina's, niet-bewerkbare voorvertoning) is dit het afgeleide
/// diagram; in de bewerkbare Bron-preview blijft het de tabel. [b.source]
/// draagt dan marker+tabel-bron, de zoektekst blijft die van de tabelrijen en
/// de schermlezer krijgt de paden als tekst.
///
/// Top-level: samengesteld uit publieke velden en [view._table], en de klasse
/// staat op haar plafond.
Widget _tableOrBowtie(
  DocumentMarkdownView view,
  _Theme t,
  _Block b,
  int ordinal,
) {
  if (b.source.isEmpty) return view._table(t, b.rows, b.aligns, ordinal);
  final editor =
      view.tableEditorFor?.call(ordinal) ??
      (ordinal == 0 ? view.tableEditController : null);
  if (editor != null) return view._table(t, b.rows, b.aligns, ordinal);
  final marked = scanOciMarkedTables(b.source).tables.firstOrNull;
  final mmd = marked == null ? null : ociBowtieMermaid(marked);
  final fallback = view._table(t, b.rows, b.aligns, ordinal);
  if (marked == null || mmd == null) return fallback;
  return Semantics(
    label: ociBowtieSemanticsLabel(marked),
    child: DocMermaidView(
      source: mmd,
      fallback: fallback,
      dark: t.dark,
      scaleToFit: view.scaleMermaidToFit,
      renderer: view.mermaidRenderer,
    ),
  );
}
