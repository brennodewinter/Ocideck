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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TableEditCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(
      horizontal: widget.cellSize * 0.55,
      vertical: widget.cellSize * 0.36,
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
                autofocus: true,
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

  const _TablePreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final edit = _TableEditScope.maybeOf(context);
    final pad = w * 0.06;
    final safe = slide.showLogo
        ? _splitTextLogoSafeInsets(w, profile)
        : EdgeInsets.zero;
    final titleSize = w * 0.038;
    final rows = slide.tableRows.where((r) => r.isNotEmpty).toList();
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

    final density = (rows.length + colCount).clamp(2, 24);
    final cellSize = (w * 0.025 * (10 / (density + 6))).clamp(
      w * 0.010,
      w * 0.021,
    );

    final accent = _hexColor(profile.accentColor);
    final textColor = _hexColor(profile.tableTextColor);
    final headerTextColor = _hexColor(profile.tableHeaderTextColor);
    final headerBackground = _hexColor(profile.tableHeaderBackgroundColor);
    final borderColor = accent.withValues(alpha: 0.35);
    final editing = edit?.enabled == true;

    Widget cell(
      String value, {
      required bool header,
      required int row,
      required int col,
    }) {
      final padding = EdgeInsets.symmetric(
        horizontal: cellSize * 0.55,
        vertical: cellSize * 0.36,
      );

      if (!editing) {
        return Padding(
          padding: padding,
          child: _md(
            context,
            value,
            _applyFont(
              font,
              TextStyle(
                fontSize: cellSize,
                color: header ? headerTextColor : textColor,
                fontWeight: header ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            linkColor: header ? headerTextColor : accent,
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

    Widget tableWidget = Table(
      border: TableBorder.all(
        color: editing ? accent.withValues(alpha: 0.55) : borderColor,
        width: editing ? w * 0.002 : w * 0.0012,
      ),
      defaultColumnWidth: const FlexColumnWidth(),
      children: [
        buildRow(rows.first, header: true, rowIndex: 0),
        for (var i = 1; i < rows.length; i++)
          buildRow(rows[i], header: false, rowIndex: i),
      ],
    );

    if (editing) {
      tableWidget = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.94, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
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

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
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
              pad + safe.bottom,
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
                        color: _hexColor(profile.textColor),
                      ),
                    ),
                    linkColor: _hexColor(profile.accentColor),
                  ),
                  SizedBox(height: pad * 0.35),
                ],
                if (rows.isNotEmpty && colCount > 0) tableWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
