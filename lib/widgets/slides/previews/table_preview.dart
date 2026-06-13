// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

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
    final pad = w * 0.06;
    final safe = slide.showLogo
        ? _splitTextLogoSafeInsets(w, profile)
        : EdgeInsets.zero;
    final titleSize = w * 0.038;
    final rows = slide.tableRows.where((r) => r.isNotEmpty).toList();
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

    // Scale cell text down as the table grows so it keeps fitting nicely.
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

    Widget cell(String value, {required bool header}) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: cellSize * 0.55,
          vertical: cellSize * 0.36,
        ),
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

    TableRow buildRow(List<String> row, {required bool header}) {
      return TableRow(
        decoration: BoxDecoration(color: header ? headerBackground : null),
        children: List.generate(colCount, (c) {
          final value = c < row.length ? row[c] : '';
          return TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: cell(value, header: header),
          );
        }),
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
                if (rows.isNotEmpty && colCount > 0)
                  Table(
                    border: TableBorder.all(
                      color: borderColor,
                      width: w * 0.0012,
                    ),
                    defaultColumnWidth: const FlexColumnWidth(),
                    children: [
                      buildRow(rows.first, header: true),
                      for (var i = 1; i < rows.length; i++)
                        buildRow(rows[i], header: false),
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
