// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// Procesverbetering `flow` slides in the HTML export: replace the Markdown
// body with the same Scene SVG the preview draws.
part of '../marp_html_service.dart';

final _flowClassComment = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _flowTemplateComment = RegExp(
  r'<!--\s*ocideck_template:\s*([^>]*?)\s*-->',
);
final _flowLayoutComment = RegExp(r'<!--\s*ocideck_layout:\s*([^>]*?)\s*-->');
final _flowHeading = RegExp(r'^#\s+(.*)$');

String renderFlowSlide(String slideMarkdown, {ThemeProfile? theme}) {
  final cssClass = _flowClassComment
      .firstMatch(slideMarkdown)
      ?.group(1)
      ?.split(RegExp(r'\s+'))
      .firstWhere((t) => t == 'flow', orElse: () => '');
  if (cssClass == null || cssClass.isEmpty) return slideMarkdown;

  var title = '';
  final bulletLines = <String>[];
  for (final line in slideMarkdown.split('\n')) {
    if (title.isEmpty) {
      final heading = _flowHeading.firstMatch(line.trim());
      if (heading != null) {
        title = heading.group(1)!.trim();
        continue;
      }
    }
    final trimmed = line.trim();
    if (trimmed.startsWith('<!--')) continue;
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      bulletLines.add(line);
    } else if (trimmed.startsWith(RegExp(r'\d+\.'))) {
      bulletLines.add(line);
    }
  }

  final bullets = <String>[];
  for (final line in bulletLines) {
    var rest = line.trimLeft();
    if (rest.startsWith('- ') || rest.startsWith('* ')) {
      rest = rest.substring(2);
    } else {
      final dot = rest.indexOf('. ');
      if (dot >= 0) rest = rest.substring(dot + 2);
    }
    bullets.add(rest);
  }

  final templateId =
      _flowTemplateComment.firstMatch(slideMarkdown)?.group(1)?.trim() ?? '';
  final layoutToken =
      _flowLayoutComment.firstMatch(slideMarkdown)?.group(1)?.trim() ?? '';
  final id = templateId.isEmpty ? kDefaultFlowTemplateId : templateId;
  final template = flowTemplateById(id);
  final layout = layoutToken.isNotEmpty
      ? flowLayoutFromToken(layoutToken)
      : template?.defaultLayout ?? FlowLayout.flow;
  final ink = theme?.textColor ?? '#0F172A';
  final accent = theme?.accentColor ?? '#003399';
  final scene = buildFlowScene(
    steps: flowStepsFromBullets(bullets),
    layout: layout,
    measurer: const ApproximateTextMeasurer(),
    title: title,
    guidance: template?.guidance('en') ?? '',
    palette: FlowPalette(ink: ink, accent: accent),
  );
  final svg = sceneToSvg(scene);
  final chrome = [
    for (final line in slideMarkdown.split('\n'))
      if (line.contains('_class:') ||
          line.contains('ocideck_template:') ||
          line.contains('ocideck_layout:'))
        line,
  ];
  return '${chrome.join('\n')}\n\n$svg\n';
}
