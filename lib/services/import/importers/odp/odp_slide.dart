import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../models/body_block.dart';
import '../../models/source_chart.dart';
import '../../models/source_image.dart';
import '../../models/source_slide.dart';
import '../../models/source_table.dart';
import 'odp_chart.dart';
import 'odp_context.dart';
import 'odp_table.dart';
import 'odp_text.dart';

/// Parse one `<draw:page>` into a [SourceSlide].
///
/// This commit handles text frames (title/subtitle/body via
/// `presentation:class`, free text boxes as positioned text), images, and
/// speaker notes. Tables and charts are added in the next commit.
/// Frame classes that carry no meaningful slide content.
const _skipClasses = {
  'notes',
  'date',
  'footer',
  'header',
  'page-number',
  'page',
  'graphic',
  'chart',
  'object',
  'image',
  'table',
  'clipart',
  'orgchart',
  'diagram',
};

SourceSlide parsePage(
  OdpContext ctx,
  int index,
  XmlElement page, {
  bool isHidden = false,
}) {
  final (pageW, pageH) = ctx.pageSize(page);

  final title = StringBuffer();
  final subtitle = StringBuffer();
  final body = <BodyBlock>[];
  final links = <({String text, String url})>[];
  final positioned = <PositionedText>[];
  final images = <SourceImage>[];
  SourceTable? table;
  SourceChart? chart;

  // Only consider direct child frames; this avoids speaker notes and animation
  // nodes that are also descendants of the page.
  for (final frame in page.children.whereType<XmlElement>()) {
    if (frame.name.local != 'frame') continue;

    final presClass = _attr(frame, 'class');
    if (presClass != null && _skipClasses.contains(presClass)) continue;

    final textBox = descendantsLocal(frame, 'text-box').firstOrNull;
    if (textBox != null) {
      final parsed = parseTextBox(textBox);
      if (parsed.blocks.isEmpty) continue;

      final text = parsed.blocks.map((b) => b.text).join(' ').trim();
      final top = _cm(_attr(frame, 'y'));
      final isFooter = top > pageH * 0.85;

      if (isFooter) continue;

      if (presClass == 'title') {
        if (title.isEmpty) {
          title.write(text);
        } else {
          title.write(' $text');
        }
      } else if (presClass == 'subtitle') {
        if (subtitle.isEmpty) {
          subtitle.write(text);
        } else {
          subtitle.write(' $text');
        }
      } else if (presClass == 'outline' ||
          (presClass == null &&
              (title.isNotEmpty || top >= pageH * 0.5 || text.isEmpty))) {
        body.addAll(parsed.blocks);
        if (presClass == null && text.isNotEmpty) {
          positioned.add(_positionedText(frame, text, pageW, pageH));
        }
      } else if (presClass == null && title.isEmpty && top < pageH * 0.5) {
        // Free-form text box at the top of the title slide: split the first
        // paragraph(s) into title and subtitle.
        for (var i = 0; i < parsed.blocks.length; i++) {
          final block = parsed.blocks[i];
          if (i == 0) {
            title.write(block.text);
          } else if (i == 1) {
            subtitle.write(block.text);
          } else {
            body.add(block);
          }
        }
      }
      links.addAll(parsed.links);
      continue;
    }

    final img = descendantsLocal(frame, 'image').firstOrNull;
    if (img != null) {
      final source = _imageFromHref(ctx, img);
      if (source != null) images.add(source);
      continue;
    }

    final tbl = descendantsLocal(frame, 'table').firstOrNull;
    if (tbl != null) {
      table ??= parseOdpTable(tbl);
      continue;
    }

    // A draw:object xlink:href -> ObjectCharts/N is a chart sub-document.
    final obj = descendantsLocal(frame, 'object').firstOrNull;
    if (obj != null) {
      chart ??= _chartFromObject(ctx, obj);
    }
  }

  final notes = _readNotes(ctx, page);

  return SourceSlide(
    index: index,
    title: title.toString().trim(),
    subtitle: subtitle.toString().trim(),
    bodyBlocks: body,
    images: images,
    chart: chart,
    table: table,
    hyperlinks: links,
    positionedTexts: positioned,
    notes: notes,
    isHidden: isHidden,
  );
}

/// Resolve a `<draw:object>` chart reference to its `content.xml` and parse
/// it. Non-chart objects (e.g. embedded OLE) return `null`.
SourceChart? _chartFromObject(OdpContext ctx, XmlElement obj) {
  final href = xlinkHref(obj);
  if (href == null) return null;
  final base = ctx.resolveHref(href);
  final xml = ctx.readPart('$base/content.xml');
  if (xml == null) return null;
  return parseOdpChartXml(xml);
}

SourceImage? _imageFromHref(OdpContext ctx, XmlElement img) {
  final href = xlinkHref(img);
  if (href == null) return null;
  final path = ctx.resolveHref(href);
  final bytes = ctx.readPartBytes(path);
  if (bytes == null) return null;
  return SourceImage(
    bytes: Uint8List.fromList(bytes),
    ext: _extFromPath(path),
    name: path.split('/').last,
  );
}

PositionedText _positionedText(
  XmlElement frame,
  String text,
  double pageW,
  double pageH,
) {
  return PositionedText(
    text: text,
    left: _cm(_attr(frame, 'x')) / pageW,
    top: _cm(_attr(frame, 'y')) / pageH,
    width: _cm(_attr(frame, 'width')) / pageW,
    height: _cm(_attr(frame, 'height')) / pageH,
  );
}

String _readNotes(OdpContext ctx, XmlElement page) {
  final buf = StringBuffer();
  for (final notes in descendantsLocal(page, 'notes')) {
    for (final textBox in descendantsLocal(notes, 'text-box')) {
      final parsed = parseTextBox(textBox);
      for (final b in parsed.blocks) {
        if (buf.isNotEmpty) buf.write('\n');
        buf.write(b.text);
      }
    }
  }
  return buf.toString().trim();
}

double _cm(String? value) {
  if (value == null) return 0;
  final num = double.tryParse(value.replaceAll(RegExp(r'[a-z%]'), '')) ?? 0;
  return num;
}

String _extFromPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return 'png';
  final ext = path.substring(dot + 1).toLowerCase();
  return ext.isEmpty ? 'png' : ext;
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
