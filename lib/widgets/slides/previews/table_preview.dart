// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

class _TableEditScope extends InheritedWidget {
  final bool enabled;
  final int? selectedRow;
  final int? selectedCol;
  final void Function(int row, int col)? onCellSelected;
  final void Function(int row, int col, String value)? onCellChanged;

  const _TableEditScope({
    required this.enabled,
    required this.selectedRow,
    required this.selectedCol,
    required this.onCellSelected,
    required this.onCellChanged,
    required super.child,
  });

  static _TableEditScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_TableEditScope>();
  }

  @override
  bool updateShouldNotify(_TableEditScope oldWidget) =>
      oldWidget.enabled != enabled ||
      oldWidget.selectedRow != selectedRow ||
      oldWidget.selectedCol != selectedCol ||
      oldWidget.onCellSelected != onCellSelected ||
      oldWidget.onCellChanged != onCellChanged;
}

class _TableEditHost extends StatelessWidget {
  final bool enabled;
  final int? selectedRow;
  final int? selectedCol;
  final void Function(int row, int col)? onCellSelected;
  final void Function(int row, int col, String value)? onCellChanged;
  final Widget child;

  const _TableEditHost({
    required this.enabled,
    required this.selectedRow,
    required this.selectedCol,
    required this.onCellSelected,
    required this.onCellChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _TableEditScope(
      enabled: enabled,
      selectedRow: selectedRow,
      selectedCol: selectedCol,
      onCellSelected: onCellSelected,
      onCellChanged: onCellChanged,
      child: child,
    );
  }
}

class _TableEditCell extends StatefulWidget {
  final String value;
  final bool selected;
  final bool header;
  final int row;
  final int col;
  final double w;
  final double cellSize;
  final double extraVPad;
  final String font;
  final Color accent;
  final Color textColor;
  final Color headerTextColor;
  final Color headerBackground;
  final void Function(int row, int col)? onSelected;
  final void Function(int row, int col, String value)? onChanged;

  const _TableEditCell({
    required this.value,
    required this.selected,
    required this.header,
    required this.row,
    required this.col,
    required this.w,
    required this.cellSize,
    required this.extraVPad,
    required this.font,
    required this.accent,
    required this.textColor,
    required this.headerTextColor,
    required this.headerBackground,
    required this.onSelected,
    required this.onChanged,
  });

  @override
  State<_TableEditCell> createState() => _TableEditCellState();
}

class _TableEditCellState extends State<_TableEditCell> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    if (widget.selected) _requestFocusSoon();
  }

  @override
  void didUpdateWidget(_TableEditCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
    // Zodra deze cel geselecteerd raakt (via Tab, klik of de toggle) pakt het
    // tekstveld expliciet focus, zodat de pijltjes de tekstcursor sturen in
    // plaats van de presentatie. Enkel `autofocus` is onbetrouwbaar wanneer de
    // root-focusnode de focus nog vasthield.
    if (widget.selected && !oldWidget.selected) _requestFocusSoon();
  }

  /// Vraag focus ná de frame waarin het tekstveld is opgebouwd, zodat de
  /// [FocusNode] daadwerkelijk aan een veld hangt voordat we hem focussen.
  void _requestFocusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.selected) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(
      horizontal: widget.cellSize * kTableCellHPadFactor,
      vertical: widget.cellSize * kTableCellVPadFactor + widget.extraVPad,
    );
    final fieldStyle = _applyFont(
      widget.font,
      TextStyle(
        fontSize: widget.cellSize,
        color: widget.header ? widget.headerTextColor : widget.textColor,
        fontWeight: widget.header ? FontWeight.bold : FontWeight.normal,
        height: 1.25,
      ),
    );

    return GestureDetector(
      key: ValueKey('table-edit-cell-${widget.row}-${widget.col}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelected?.call(widget.row, widget.col),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: padding,
        decoration: BoxDecoration(
          color: widget.selected
              ? (widget.header
                    ? widget.headerBackground.withValues(alpha: 0.92)
                    : Colors.white.withValues(alpha: 0.96))
              : (widget.header
                    ? widget.headerBackground.withValues(alpha: 0.55)
                    : widget.accent.withValues(alpha: 0.04)),
          border: Border.all(
            color: widget.selected
                ? widget.accent
                : widget.accent.withValues(alpha: widget.header ? 0.25 : 0.14),
            width: widget.selected ? widget.w * 0.0028 : widget.w * 0.001,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: widget.accent.withValues(alpha: 0.28),
                    blurRadius: widget.w * 0.012,
                    spreadRadius: widget.w * 0.001,
                  ),
                ]
              : null,
        ),
        child: widget.selected
            ? TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                style: fieldStyle,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) =>
                    widget.onChanged?.call(widget.row, widget.col, v),
              )
            : _md(
                context,
                widget.value.isEmpty ? ' ' : widget.value,
                fieldStyle.copyWith(
                  color: widget.value.isEmpty
                      ? widget.textColor.withValues(alpha: 0.35)
                      : (widget.header
                            ? widget.headerTextColor
                            : widget.textColor),
                ),
                linkColor: widget.header
                    ? widget.headerTextColor
                    : widget.accent,
              ),
      ),
    );
  }
}

class _TablePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  /// De taal van het rapport (zie [Deck.language]), gebruikt voor
  /// taalbewuste getalnotatie in gemarkeerde kolommen. Leeg = geen
  /// notatie-toepassing (de celwaarde staat zoals hij in de .md staat).
  final String reportLanguage;

  const _TablePreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    this.reportLanguage = '',
  });

  @override
  Widget build(BuildContext context) {
    final edit = _TableEditScope.maybeOf(context);
    final pad = w * 0.06;
    // A table fills the slide's full width, so a bottom- or top-corner logo
    // overlaps its edge cells regardless of which side it sits on. Reserve the
    // whole strip (as for plain bullets) rather than the split-layout variant,
    // which skips the reserve for a right-side logo — correct only when the
    // text column sits away from it (bulletsImage), not for a full-width table.
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final titleSize = w * 0.038;
    final (rows, caption) = _rowsAndCaption(slide);
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

    final fit = _fit(
      rows: rows,
      colCount: colCount,
      pad: pad,
      safe: safe,
      titleSize: titleSize,
      caption: caption,
    );
    final cellSize = fit.cellSize;

    final accent = AppTheme.parseHexColor(profile.accentColor);
    final textColor = AppTheme.parseHexColor(profile.tableTextColor);
    final headerTextColor = AppTheme.parseHexColor(
      profile.tableHeaderTextColor,
    );
    final headerBackground = AppTheme.parseHexColor(
      profile.tableHeaderBackgroundColor,
    );
    final borderColor = accent.withValues(alpha: 0.35);
    final editing = edit?.enabled == true;
    // Tegen de dag waarop het deck getoond wordt, niet tegen een opgeslagen
    // vlag: een presentatie die twee maanden later opnieuw langskomt, markeert
    // haar eigen verlopen deadlines in plaats van te blijven beweren dat alles
    // op schema ligt. Uit tenzij de auteur het aanzet, dus een tabel met
    // historische datums kleurt niet vanzelf rood.
    final today = slide.tableMarkOverdue ? DateTime.now() : null;

    Widget cell(
      String value, {
      required bool header,
      required int row,
      required int col,
    }) {
      final padding = EdgeInsets.symmetric(
        horizontal: cellSize * kTableCellHPadFactor,
        vertical: cellSize * kTableCellVPadFactor + fit.extraVPad,
      );

      if (!editing) {
        final expired =
            today != null && !header && isPastDateCell(value, today);
        // Taalbewuste getalnotatie: als deze kolom gemarkeerd is en de cel
        // een getal bevat, formatteer het volgens de deck-taal. De ruwe
        // waarde blijft in de .md; dit is puur visueel.
        final displayValue = (!header && _isNumberColumn(slide, col))
            ? formatTableCellNumber(value, reportLanguage)
            : value;
        return Padding(
          padding: padding,
          child: _md(
            context,
            displayValue,
            _applyFont(
              font,
              TextStyle(
                fontSize: cellSize,
                color: expired
                    ? AppTheme.danger700
                    : (header ? headerTextColor : textColor),
                fontWeight: header || expired
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            linkColor: header ? headerTextColor : accent,
            textAlign: _tableAlign(slide, col),
          ),
        );
      }

      final selected = edit!.selectedRow == row && edit.selectedCol == col;
      return _TableEditCell(
        value: value,
        selected: selected,
        header: header,
        row: row,
        col: col,
        w: w,
        cellSize: cellSize,
        extraVPad: fit.extraVPad,
        font: font,
        accent: accent,
        textColor: textColor,
        headerTextColor: headerTextColor,
        headerBackground: headerBackground,
        onSelected: edit.onCellSelected,
        onChanged: edit.onCellChanged,
      );
    }

    TableRow buildRow(
      List<String> row, {
      required bool header,
      required int rowIndex,
    }) {
      return TableRow(
        decoration: BoxDecoration(
          color: header && !editing ? headerBackground : null,
        ),
        children: List.generate(colCount, (c) {
          final value = c < row.length ? row[c] : '';
          return TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: cell(value, header: header, row: rowIndex, col: c),
          );
        }),
      );
    }

    final columnWidths = _columnWidths(rows, colCount, pad, cellSize);

    Widget tableWidget = Table(
      border: TableBorder.all(
        color: editing ? accent.withValues(alpha: 0.55) : borderColor,
        width: editing ? w * 0.002 : w * 0.0012,
      ),
      columnWidths: columnWidths,
      children: [
        buildRow(rows.first, header: true, rowIndex: 0),
        for (var i = 1; i < rows.length; i++)
          buildRow(rows[i], header: false, rowIndex: i),
      ],
    );

    if (editing) {
      tableWidget = _editingGlow(tableWidget, accent);
    }

    return _outerLayout(
      context,
      tableWidget,
      pad: pad,
      safe: safe,
      titleSize: titleSize,
      rows: rows,
      colCount: colCount,
      caption: caption,
    );
  }

  /// De tabel vult de hoogte die de dia haar laat: de letter groeit tot ze past
  /// (of tot het leesbaarheidsplafond), en wat een korte tabel dan nog overhoudt
  /// gaat naar de rijen zelf. Een tekstrijke tabel krimpt juist, zodat hij op
  /// volle breedte past in plaats van door de FittedBox als geheel verkleind te
  /// worden — dat maakt hem ook smaller en laat de rechterrand leeg. availH
  /// spiegelt het kader van _outerLayout: de 16:9-doos min de logo-veilige
  /// randen, het titelblok en het bijschrift.
  ({double cellSize, double extraVPad}) _fit({
    required List<List<String>> rows,
    required int colCount,
    required double pad,
    required EdgeInsets safe,
    required double titleSize,
    required String caption,
  }) {
    final tableWidth = w - pad * 2;
    final titleBlock = slide.title.isNotEmpty
        ? measureTextHeight(
                slide.title,
                titleSize,
                tableWidth,
                bold: true,
                fontFamily: font,
              ) +
              pad * 0.35
        : 0.0;
    final availH =
        w * 9 / 16 -
        (pad + safe.top) -
        _logoAwareBottomPadding(pad, safe.bottom) -
        titleBlock -
        _captionBlockHeight(caption, w, tableWidth, font, pad);
    return memoizedRenderLayout<({double cellSize, double extraVPad})>(
      slide: slide,
      font: font,
      width: w,
      availW: tableWidth,
      availH: availH,
      compute: () => tableFit(
        rows: rows,
        colCount: colCount,
        slideWidth: w,
        tableWidth: tableWidth,
        availH: availH,
        font: font,
      ),
    );
  }

  /// Schaal-in-animatie plus accentgloed rond de tabel in bewerkmodus.
  Widget _editingGlow(Widget tableWidget, Color accent) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.012),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: w * 0.028,
              spreadRadius: w * 0.004,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(w * 0.012),
          child: tableWidget,
        ),
      ),
    );
  }

  /// Vaste kolombreedtes uit [tableColumnWidths] — dezelfde geometrie waarmee
  /// [tableBlockHeight] de hoogte meet. Niet `FlexColumnWidth` op tekenaantal:
  /// dat kende een kolom minder ruimte toe dan haar eigen kop breed is, waarna
  /// de kop letter voor letter afbrak en bij de smalste kolommen zelfs over de
  /// tabellijnen heen viel.
  Map<int, TableColumnWidth> _columnWidths(
    List<List<String>> rows,
    int colCount,
    double pad,
    double cellSize,
  ) {
    final widths = tableColumnWidths(
      rows: rows,
      colCount: colCount,
      tableWidth: w - pad * 2,
      cellSize: cellSize,
      font: font,
    );
    return <int, TableColumnWidth>{
      for (var c = 0; c < colCount; c++) c: FixedColumnWidth(widths[c]),
    };
  }

  /// The slide frame around the built [tableWidget]: background, logo-safe
  /// padding, optional title, and the FittedBox that scales an oversized table
  /// down to fit.
  Widget _outerLayout(
    BuildContext context,
    Widget tableWidget, {
    required double pad,
    required EdgeInsets safe,
    required double titleSize,
    required List<List<String>> rows,
    required int colCount,
    required String caption,
  }) {
    return Container(
      color: AppTheme.parseHexColor(profile.slideBackgroundColor),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: w,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              pad,
              pad + safe.top,
              pad,
              _logoAwareBottomPadding(pad, safe.bottom),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (slide.title.isNotEmpty) ...[
                  _md(
                    context,
                    slide.title,
                    _applyFont(
                      font,
                      TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.parseHexColor(profile.textColor),
                      ),
                    ),
                    linkColor: AppTheme.parseHexColor(profile.accentColor),
                  ),
                  SizedBox(height: pad * 0.35),
                ],
                if (rows.isNotEmpty && colCount > 0) tableWidget,
                if (caption.isNotEmpty) ...[
                  SizedBox(height: pad * _kCaptionGapFactor),
                  _md(
                    context,
                    caption,
                    _applyFont(
                      font,
                      TextStyle(
                        fontSize: w * _kCaptionSizeFactor,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.parseHexColor(
                          profile.textColor,
                        ).withValues(alpha: 0.7),
                      ),
                    ),
                    linkColor: AppTheme.parseHexColor(profile.accentColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Het bijschrift staat onder de tabel, niet erin: op één kolom breed leest het
/// als data en verbreedt het die kolom tot een kwart slide.
const double _kCaptionSizeFactor = 0.016;
const double _kCaptionGapFactor = 0.22;

/// Splitst de zichtbare rijen van het "N van totaal"-bijschrift dat een
/// weergavelimiet achteraan de tabel hangt.
(List<List<String>>, String) _rowsAndCaption(Slide slide) {
  final rows = slide.tableRows.where((r) => r.isNotEmpty).toList();
  final index = viewLimitCaptionRowIndex(slide, rows);
  if (index == null) return (rows, '');
  return (rows.sublist(0, index), rows[index].first.trim());
}

/// Hoogte die het bijschrift onder de tabel opeist, inclusief de tussenruimte.
double _captionBlockHeight(
  String caption,
  double w,
  double tableWidth,
  String font,
  double pad,
) {
  if (caption.isEmpty) return 0;
  return measureTextHeight(
        caption,
        w * _kCaptionSizeFactor,
        tableWidth,
        fontFamily: font,
      ) +
      pad * _kCaptionGapFactor;
}

/// De [TextAlign] voor kolom [col] van [slide], uit de GFM-scheidingsrij
/// gelezen. `start` (de Flutter-default voor links in LTR) als er geen
/// uitlijning is opgegeven — een oud deck zonder colons blijft links.
/// Of kolom [col] gemarkeerd is voor getalnotatie op deze slide.
bool _isNumberColumn(Slide slide, int col) =>
    col < slide.tableNumberColumns.length && slide.tableNumberColumns[col];

TextAlign _tableAlign(Slide slide, int col) {
  final aligns = slide.tableColumnAlignments;
  if (col >= aligns.length) return TextAlign.start;
  return switch (aligns[col]) {
    TableAlign.left => TextAlign.start,
    TableAlign.center => TextAlign.center,
    TableAlign.right => TextAlign.end,
  };
}
