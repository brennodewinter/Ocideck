// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

extension _GanttPreviewDispatch on SlidePreviewWidget {
  Widget _ganttContent(Slide slide, double w) => _GanttPreview(
    slide: slide,
    w: w,
    font: fontFamily,
    profile: themeProfile,
  );
}

/// Preview for a `gantt` slide: leidt Mermaid gantt-DSL af uit de tabelrijen en
/// rendert die via de bestaande [MermaidDiagram]-widget. De DSL wordt nooit
/// opgeslagen — net als flow's roll-up strip.
class _GanttPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _GanttPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07;
    final rows = slide.tableRows.length > 1
        ? slide.tableRows.sublist(1)
        : const <List<String>>[];
    final dsl = ganttTableToMermaid(
      rows: rows,
      scale: slide.ganttScale,
      sections: slide.ganttSections,
    );

    return _PreviewScaffold(
      width: w,
      slide: slide,
      profile: profile,
      horizontalPadding: pad,
      verticalPadding: pad,
      children: [MermaidDiagram(source: dsl, width: w - pad * 2)],
    );
  }
}
