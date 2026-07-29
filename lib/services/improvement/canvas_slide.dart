// Bridge between a `canvas` slide and the canvas model (PROCESS_IMPROVEMENT §3.2).
//
// On disk a canvas is ordinary Markdown: `#` title (slide title) and `##`
// headings as regions. `<!-- ocideck_template: a3 -->` says which artefact it
// is. The engine only lays those regions out — it invents nothing.
library;

import '../../models/slide.dart';
import 'canvas_spec.dart';

final _h2 = RegExp(r'^##\s+(.*)$');

/// Parse [markdown] into region bodies keyed by template region, or by the
/// heading text when the template is unknown.
///
/// Matching is case-insensitive against both NL and EN labels so a deck saved
/// in Dutch still opens against an English template contract (and the reverse).
List<CanvasRegionContent> canvasRegionsFromMarkdown(
  String markdown, {
  String templateId = '',
}) {
  final template = canvasTemplateById(templateId);
  final sections = _splitH2(markdown);
  if (template == null) {
    return [
      for (final s in sections)
        CanvasRegionContent(
          key: _keyFor(s.heading),
          heading: s.heading,
          body: s.body,
        ),
    ];
  }

  final byNorm = <String, ({String heading, String body})>{};
  for (final s in sections) {
    byNorm[_norm(s.heading)] = s;
  }

  return [
    for (final region in template.regions)
      CanvasRegionContent(
        key: region.key,
        heading: region.labelEn,
        body:
            byNorm[_norm(region.labelEn)]?.body ??
            byNorm[_norm(region.labelNl)]?.body ??
            '',
      ),
  ];
}

/// Rebuild the Markdown body from [regions] — English headings (file contract).
String canvasMarkdownFromRegions(List<CanvasRegionContent> regions) {
  if (regions.isEmpty) return '';
  return [
    for (final r in regions) '## ${r.heading}\n\n${r.body.trim()}\n',
  ].join('\n').trimRight();
}

/// Remap [slide]'s body onto [templateId], keeping text for matching region
/// keys so a mis-click in the template picker does not wipe work.
String canvasMarkdownForTemplate(Slide slide, String templateId) {
  final target = canvasTemplateById(templateId);
  if (target == null) return slide.customMarkdown;
  final current = canvasRegionsFromMarkdown(
    slide.customMarkdown,
    templateId: slide.improvementTemplateId,
  );
  final byKey = {for (final r in current) r.key: r.body};
  return canvasMarkdownFromRegions([
    for (final region in target.regions)
      CanvasRegionContent(
        key: region.key,
        heading: region.labelEn,
        body: byKey[region.key] ?? '',
      ),
  ]);
}

List<({String heading, String body})> _splitH2(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final out = <({String heading, String body})>[];
  String? heading;
  final body = StringBuffer();

  void flush() {
    final h = heading;
    if (h == null) return;
    out.add((heading: h, body: body.toString().trim()));
    body.clear();
  }

  for (final line in lines) {
    final m = _h2.firstMatch(line.trimRight());
    if (m != null) {
      flush();
      heading = m.group(1)!.trim();
      continue;
    }
    if (heading != null) {
      if (body.isNotEmpty) body.writeln();
      body.write(line);
    }
  }
  flush();
  return out;
}

String _norm(String s) => s.trim().toLowerCase();

String _keyFor(String label) => label
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
