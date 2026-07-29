// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// Procesverbetering `canvas` slides in the HTML export: replace the Markdown
// body with the same Scene SVG the preview draws.
part of '../marp_html_service.dart';

final _canvasClassComment = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _canvasTemplateComment = RegExp(
  r'<!--\s*ocideck_template:\s*([^>]*?)\s*-->',
);
final _canvasHeading = RegExp(r'^#\s+(.*)$');

String renderCanvasSlide(String slideMarkdown, {ThemeProfile? theme}) {
  final cssClass = _canvasClassComment
      .firstMatch(slideMarkdown)
      ?.group(1)
      ?.split(RegExp(r'\s+'))
      .firstWhere((t) => t == 'canvas', orElse: () => '');
  if (cssClass == null || cssClass.isEmpty) return slideMarkdown;

  var title = '';
  final bodyLines = <String>[];
  for (final line in slideMarkdown.split('\n')) {
    if (title.isEmpty) {
      final heading = _canvasHeading.firstMatch(line.trim());
      if (heading != null) {
        title = heading.group(1)!.trim();
        continue;
      }
    }
    // Keep region markdown; drop class/template/comment chrome later via kept.
    bodyLines.add(line);
  }

  // Reconstruct body without the leading # title and without directives —
  // region ## headings live in the remaining markdown.
  final regionMd = [
    for (final line in bodyLines)
      if (!line.trim().startsWith('<!--')) line,
  ].join('\n').trim();

  final templateId =
      _canvasTemplateComment.firstMatch(slideMarkdown)?.group(1)?.trim() ?? '';
  final id = templateId.isEmpty ? kDefaultCanvasTemplateId : templateId;
  final template = canvasTemplateById(id);
  final regions = canvasRegionsFromMarkdown(regionMd, templateId: id);
  final ink = theme?.textColor ?? '#0F172A';
  final accent = theme?.accentColor ?? '#003399';
  final scene = buildCanvasScene(
    template: template,
    regions: regions,
    measurer: const ApproximateTextMeasurer(),
    title: title,
    languageCode: 'en',
    palette: CanvasPalette(ink: ink, accent: accent),
  );
  final svg = sceneToSvg(scene);
  final kept = [
    for (final line in slideMarkdown.split('\n'))
      if (line.trim().startsWith('<!--') &&
          !isMarkdownTableLine(line) &&
          _canvasHeading.firstMatch(line.trim()) == null)
        line,
  ];
  // Keep class + template comments; drop the # title and ## body (replaced by SVG).
  final chrome = [
    for (final line in slideMarkdown.split('\n'))
      if (line.contains('_class:') || line.contains('ocideck_template:')) line,
  ];
  return '${chrome.isEmpty ? kept.join('\n') : chrome.join('\n')}\n\n$svg\n';
}
