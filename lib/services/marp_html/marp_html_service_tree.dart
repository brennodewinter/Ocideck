// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// Procesverbetering `tree` slides in the HTML export: replace the Markdown
// body with the same Scene SVG the preview draws.
part of '../marp_html_service.dart';

final _treeClassComment = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _treeTemplateComment = RegExp(
  r'<!--\s*ocideck_template:\s*([^>]*?)\s*-->',
);
final _treeLayoutComment = RegExp(r'<!--\s*ocideck_layout:\s*([^>]*?)\s*-->');
final _treeHeading = RegExp(r'^#\s+(.*)$');

String renderTreeSlide(String slideMarkdown, {ThemeProfile? theme}) {
  final cssClass = _treeClassComment
      .firstMatch(slideMarkdown)
      ?.group(1)
      ?.split(RegExp(r'\s+'))
      .firstWhere((t) => t == 'tree', orElse: () => '');
  if (cssClass == null || cssClass.isEmpty) return slideMarkdown;

  var title = '';
  final bulletLines = <String>[];
  for (final line in slideMarkdown.split('\n')) {
    if (title.isEmpty) {
      final heading = _treeHeading.firstMatch(line.trim());
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
    final tabs = '\t' * ((line.length - line.trimLeft().length) ~/ 2);
    bullets.add('$tabs$rest');
  }

  final templateId =
      _treeTemplateComment.firstMatch(slideMarkdown)?.group(1)?.trim() ?? '';
  final layoutToken =
      _treeLayoutComment.firstMatch(slideMarkdown)?.group(1)?.trim() ?? '';
  final id = templateId.isEmpty ? kDefaultTreeTemplateId : templateId;
  final template = treeTemplateById(id);
  final layout = layoutToken.isNotEmpty
      ? treeLayoutFromToken(layoutToken)
      : template?.defaultLayout ?? TreeLayout.tree;
  final ink = theme?.textColor ?? '#0F172A';
  final accent = theme?.accentColor ?? '#003399';
  final scene = buildTreeScene(
    bullets: bullets,
    layout: layout,
    measurer: const ApproximateTextMeasurer(),
    title: title,
    guidance: template?.guidance('en') ?? '',
    palette: TreePalette(ink: ink, accent: accent, bone: ink),
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
