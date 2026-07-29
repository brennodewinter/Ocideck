// Canvas engine: CanvasTemplate + region bodies → Scene (PROCESS_IMPROVEMENT §3.2).
//
// One layout pass, two backends — same contract as the matrix engine.
library;

import '../scene/scene.dart';
import 'canvas_spec.dart';

class CanvasPalette {
  const CanvasPalette({
    this.ink = '#0F172A',
    this.muted = '#64748B',
    this.rule = '#CBD5E1',
    this.boxFill = '#F8FAFC',
    this.headerFill = '#E2E8F0',
    this.accent = '#003399',
  });

  final String ink;
  final String muted;
  final String rule;
  final String boxFill;
  final String headerFill;
  final String accent;
}

/// Build the scene for one canvas slide.
Scene buildCanvasScene({
  required CanvasTemplate? template,
  required List<CanvasRegionContent> regions,
  required TextMeasurer measurer,
  String title = '',
  String languageCode = 'nl',
  CanvasPalette palette = const CanvasPalette(),
  double width = 960,
  double height = 540,
}) {
  final layout = template?.layout ?? CanvasLayout.regions;
  return switch (layout) {
    CanvasLayout.regions => _regionsScene(
      template: template,
      regions: regions,
      measurer: measurer,
      title: title,
      languageCode: languageCode,
      palette: palette,
      width: width,
      height: height,
    ),
    CanvasLayout.quadrant => _quadrantScene(
      template: template,
      regions: regions,
      measurer: measurer,
      title: title,
      languageCode: languageCode,
      palette: palette,
      width: width,
      height: height,
    ),
    CanvasLayout.board => _boardScene(
      template: template,
      regions: regions,
      measurer: measurer,
      title: title,
      languageCode: languageCode,
      palette: palette,
      width: width,
      height: height,
    ),
  };
}

Scene _regionsScene({
  required CanvasTemplate? template,
  required List<CanvasRegionContent> regions,
  required TextMeasurer measurer,
  required String title,
  required String languageCode,
  required CanvasPalette palette,
  required double width,
  required double height,
}) {
  final nodes = <SceneNode>[];
  const margin = 28.0;
  var top = margin;

  if (title.trim().isNotEmpty) {
    const titleSize = 26.0;
    nodes.add(
      SceneText(
        x: margin,
        y: top + titleSize,
        text: title.trim(),
        fontSize: titleSize,
        fill: palette.ink,
        fontWeight: 700,
      ),
    );
    top += titleSize * 1.35;
  }

  final guidance = template?.guidance(languageCode) ?? '';
  if (guidance.isNotEmpty) {
    nodes.add(
      SceneText(
        x: margin,
        y: top + 12,
        text: guidance,
        fontSize: 12,
        fill: palette.muted,
      ),
    );
    top += 20;
  }

  final count = regions.isEmpty ? 1 : regions.length;
  // Prefer a readable grid: 2 columns when many regions, else one column.
  final cols = count >= 4 ? 2 : 1;
  final rows = (count / cols).ceil();
  final gap = 10.0;
  final availH = height - top - margin;
  final availW = width - 2 * margin;
  final cellW = (availW - gap * (cols - 1)) / cols;
  final cellH = (availH - gap * (rows - 1)) / rows;

  for (var i = 0; i < regions.length; i++) {
    final r = regions[i];
    final col = i % cols;
    final row = i ~/ cols;
    final x = margin + col * (cellW + gap);
    final y = top + row * (cellH + gap);
    _regionBox(
      nodes,
      measurer: measurer,
      x: x,
      y: y,
      w: cellW,
      h: cellH,
      heading: template == null
          ? r.heading
          : template.regions
                .firstWhere(
                  (t) => t.key == r.key,
                  orElse: () => CanvasRegion(
                    key: r.key,
                    labelNl: r.heading,
                    labelEn: r.heading,
                  ),
                )
                .label(languageCode),
      body: r.body,
      palette: palette,
    );
  }

  return Scene(width: width, height: height, nodes: nodes);
}

Scene _quadrantScene({
  required CanvasTemplate? template,
  required List<CanvasRegionContent> regions,
  required TextMeasurer measurer,
  required String title,
  required String languageCode,
  required CanvasPalette palette,
  required double width,
  required double height,
}) {
  final nodes = <SceneNode>[];
  const margin = 28.0;
  var top = margin;

  if (title.trim().isNotEmpty) {
    const titleSize = 26.0;
    nodes.add(
      SceneText(
        x: margin,
        y: top + titleSize,
        text: title.trim(),
        fontSize: titleSize,
        fill: palette.ink,
        fontWeight: 700,
      ),
    );
    top += titleSize * 1.4;
  }

  final plotLeft = margin + 36;
  final plotTop = top + 8;
  final plotRight = width - margin;
  final plotBottom = height - margin - 24;
  final midX = (plotLeft + plotRight) / 2;
  final midY = (plotTop + plotBottom) / 2;

  // Axes.
  nodes
    ..add(
      SceneLine(
        x1: midX,
        y1: plotTop,
        x2: midX,
        y2: plotBottom,
        stroke: palette.rule,
        strokeWidth: 1.5,
      ),
    )
    ..add(
      SceneLine(
        x1: plotLeft,
        y1: midY,
        x2: plotRight,
        y2: midY,
        stroke: palette.rule,
        strokeWidth: 1.5,
      ),
    );

  if (template != null) {
    nodes
      ..add(
        SceneText(
          x: plotLeft,
          y: plotBottom + 16,
          text: template.axisXLow(languageCode),
          fontSize: 11,
          fill: palette.muted,
        ),
      )
      ..add(
        SceneText(
          x:
              plotRight -
              measurer.widthOf(template.axisXHigh(languageCode), fontSize: 11),
          y: plotBottom + 16,
          text: template.axisXHigh(languageCode),
          fontSize: 11,
          fill: palette.muted,
        ),
      )
      ..add(
        SceneText(
          x: margin,
          y: plotBottom - 4,
          text: template.axisYLow(languageCode),
          fontSize: 11,
          fill: palette.muted,
        ),
      )
      ..add(
        SceneText(
          x: margin,
          y: plotTop + 12,
          text: template.axisYHigh(languageCode),
          fontSize: 11,
          fill: palette.muted,
        ),
      );
  }

  // Quadrant order for impact-effort: NW quick-wins, NE major, SW fill-ins, SE thankless.
  // For SWOT: NW strengths, NE opportunities, SW weaknesses, SE threats.
  final pads = [
    (plotLeft + 6, plotTop + 6, midX - plotLeft - 12, midY - plotTop - 12),
    (midX + 6, plotTop + 6, plotRight - midX - 12, midY - plotTop - 12),
    (plotLeft + 6, midY + 6, midX - plotLeft - 12, plotBottom - midY - 12),
    (midX + 6, midY + 6, plotRight - midX - 12, plotBottom - midY - 12),
  ];

  for (var i = 0; i < regions.length && i < 4; i++) {
    final r = regions[i];
    final (x, y, w, h) = pads[i];
    final heading = template == null
        ? r.heading
        : template.regions
              .firstWhere(
                (t) => t.key == r.key,
                orElse: () => CanvasRegion(
                  key: r.key,
                  labelNl: r.heading,
                  labelEn: r.heading,
                ),
              )
              .label(languageCode);
    _regionBox(
      nodes,
      measurer: measurer,
      x: x,
      y: y,
      w: w,
      h: h,
      heading: heading,
      body: r.body,
      palette: palette,
      compact: true,
    );
  }

  return Scene(width: width, height: height, nodes: nodes);
}

Scene _boardScene({
  required CanvasTemplate? template,
  required List<CanvasRegionContent> regions,
  required TextMeasurer measurer,
  required String title,
  required String languageCode,
  required CanvasPalette palette,
  required double width,
  required double height,
}) {
  final nodes = <SceneNode>[];
  const margin = 28.0;
  var top = margin;

  if (title.trim().isNotEmpty) {
    const titleSize = 26.0;
    nodes.add(
      SceneText(
        x: margin,
        y: top + titleSize,
        text: title.trim(),
        fontSize: titleSize,
        fill: palette.ink,
        fontWeight: 700,
      ),
    );
    top += titleSize * 1.4;
  }

  final cols = regions.isEmpty ? 1 : regions.length;
  final gap = 12.0;
  final colW = (width - 2 * margin - gap * (cols - 1)) / cols;
  final colH = height - top - margin;

  for (var i = 0; i < regions.length; i++) {
    final r = regions[i];
    final x = margin + i * (colW + gap);
    final heading = template == null
        ? r.heading
        : template.regions
              .firstWhere(
                (t) => t.key == r.key,
                orElse: () => CanvasRegion(
                  key: r.key,
                  labelNl: r.heading,
                  labelEn: r.heading,
                ),
              )
              .label(languageCode);
    nodes.add(
      SceneRect(
        x: x,
        y: top,
        width: colW,
        height: colH,
        fill: palette.boxFill,
        stroke: palette.rule,
        cornerRadius: 6,
      ),
    );
    nodes.add(
      SceneRect(
        x: x,
        y: top,
        width: colW,
        height: 28,
        fill: palette.headerFill,
        cornerRadius: 6,
      ),
    );
    nodes.add(
      SceneText(
        x: x + 10,
        y: top + 20,
        text: heading,
        fontSize: 13,
        fill: palette.ink,
        fontWeight: 700,
      ),
    );
    _bodyLines(
      nodes,
      measurer: measurer,
      text: r.body,
      x: x + 10,
      y: top + 40,
      maxWidth: colW - 20,
      maxBottom: top + colH - 10,
      palette: palette,
      asCards: true,
    );
  }

  return Scene(width: width, height: height, nodes: nodes);
}

void _regionBox(
  List<SceneNode> nodes, {
  required TextMeasurer measurer,
  required double x,
  required double y,
  required double w,
  required double h,
  required String heading,
  required String body,
  required CanvasPalette palette,
  bool compact = false,
}) {
  nodes.add(
    SceneRect(
      x: x,
      y: y,
      width: w,
      height: h,
      fill: palette.boxFill,
      stroke: palette.rule,
      cornerRadius: 4,
    ),
  );
  final headerH = compact ? 22.0 : 26.0;
  nodes.add(
    SceneRect(
      x: x,
      y: y,
      width: w,
      height: headerH,
      fill: palette.headerFill,
      cornerRadius: 4,
    ),
  );
  nodes.add(
    SceneText(
      x: x + 8,
      y: y + headerH - 6,
      text: heading,
      fontSize: compact ? 12 : 13,
      fill: palette.accent,
      fontWeight: 700,
    ),
  );
  _bodyLines(
    nodes,
    measurer: measurer,
    text: body,
    x: x + 8,
    y: y + headerH + 14,
    maxWidth: w - 16,
    maxBottom: y + h - 8,
    palette: palette,
  );
}

void _bodyLines(
  List<SceneNode> nodes, {
  required TextMeasurer measurer,
  required String text,
  required double x,
  required double y,
  required double maxWidth,
  required double maxBottom,
  required CanvasPalette palette,
  bool asCards = false,
}) {
  if (text.trim().isEmpty) return;
  const fontSize = 12.0;
  final lineH = measurer.lineHeight(fontSize: fontSize);
  var cy = y;
  final rawLines = text.split('\n');
  for (final raw in rawLines) {
    final line = raw.trimRight();
    if (line.isEmpty) {
      cy += lineH * 0.4;
      continue;
    }
    final display = line.startsWith('- ') || line.startsWith('* ')
        ? '• ${line.substring(2).trim()}'
        : line;
    if (asCards) {
      final cardH = lineH + 10;
      if (cy + cardH > maxBottom) break;
      nodes.add(
        SceneRect(
          x: x,
          y: cy - lineH + 2,
          width: maxWidth,
          height: cardH,
          fill: '#FFFFFF',
          stroke: palette.rule,
          cornerRadius: 3,
        ),
      );
      nodes.add(
        SceneText(
          x: x + 6,
          y: cy + 2,
          text: _ellipsis(display, measurer, maxWidth - 12, fontSize),
          fontSize: fontSize,
          fill: palette.ink,
        ),
      );
      cy += cardH + 6;
    } else {
      if (cy > maxBottom) break;
      nodes.add(
        SceneText(
          x: x,
          y: cy,
          text: _ellipsis(display, measurer, maxWidth, fontSize),
          fontSize: fontSize,
          fill: palette.ink,
        ),
      );
      cy += lineH;
    }
  }
}

String _ellipsis(
  String text,
  TextMeasurer measurer,
  double maxWidth,
  double fontSize,
) {
  if (measurer.widthOf(text, fontSize: fontSize) <= maxWidth) return text;
  var t = text;
  while (t.length > 1 &&
      measurer.widthOf('$t…', fontSize: fontSize) > maxWidth) {
    t = t.substring(0, t.length - 1);
  }
  return '$t…';
}
