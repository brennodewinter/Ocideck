// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// Procesverbetering `matrix` slides in the HTML export. On disk they are a
// Markdown table plus `<!-- ocideck_template: … -->`; on screen the matrix
// engine lays out a Scene. Export must show that Scene, not the raw table —
// otherwise a customer reading the HTML never sees the derived RPN column or
// the RPN-sorted order the author approved in the preview.
part of '../marp_html_service.dart';

final _matrixClassComment = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _matrixTemplateComment = RegExp(
  r'<!--\s*ocideck_template:\s*([^>]*?)\s*-->',
);
final _matrixHeading = RegExp(r'^#\s+(.*)$');

/// Replace a `matrix` slide's Markdown table with the scene SVG the preview
/// draws. Leaves every other slide unchanged.
String renderMatrixSlide(String slideMarkdown, {ThemeProfile? theme}) {
  final cssClass = _matrixClassComment
      .firstMatch(slideMarkdown)
      ?.group(1)
      ?.split(RegExp(r'\s+'))
      .firstWhere((t) => t == 'matrix', orElse: () => '');
  if (cssClass == null || cssClass.isEmpty) return slideMarkdown;

  var title = '';
  final tableLines = <String>[];
  for (final line in slideMarkdown.split('\n')) {
    if (title.isEmpty) {
      final heading = _matrixHeading.firstMatch(line.trim());
      if (heading != null) {
        title = heading.group(1)!.trim();
        continue;
      }
    }
    if (isMarkdownTableLine(line)) tableLines.add(line);
  }
  final rows = decodeMarkdownTableRows(tableLines);
  final templateId =
      _matrixTemplateComment.firstMatch(slideMarkdown)?.group(1)?.trim() ?? '';
  final slide = Slide.create(SlideType.matrix).copyWith(
    title: title,
    tableRows: rows,
    improvementTemplateId: templateId.isEmpty
        ? kDefaultImprovementTemplateId
        : templateId,
  );
  final ink = theme?.textColor ?? '#0F172A';
  final accent = theme?.accentColor ?? '#003399';
  final scene = buildMatrixScene(
    spec: matrixSpecFromSlide(slide),
    displayColumns: matrixDisplayColumns(slide),
    rows: matrixDisplayRows(slide),
    measurer: const ApproximateTextMeasurer(),
    title: title,
    languageCode: 'en',
    palette: MatrixPalette(ink: ink, accent: accent),
  );
  final svg = sceneToSvg(scene);
  final kept = [
    for (final line in slideMarkdown.split('\n'))
      if (!isMarkdownTableLine(line) &&
          _matrixHeading.firstMatch(line.trim()) == null)
        line,
  ];
  return '${kept.join('\n')}\n\n$svg\n';
}
