// Tree / fishbone engine → Scene (PROCESS_IMPROVEMENT §3.3).
library;

import '../../models/slide.dart';
import '../scene/scene.dart';
import 'tree_spec.dart';

class TreePalette {
  const TreePalette({
    this.ink = '#0F172A',
    this.muted = '#64748B',
    this.rule = '#CBD5E1',
    this.accent = '#003399',
    this.bone = '#334155',
  });

  final String ink;
  final String muted;
  final String rule;
  final String accent;
  final String bone;
}

Scene buildTreeScene({
  required List<String> bullets,
  required TreeLayout layout,
  required TextMeasurer measurer,
  String title = '',
  String guidance = '',
  TreePalette palette = const TreePalette(),
  double width = 960,
  double height = 540,
}) {
  return switch (layout) {
    TreeLayout.fishbone => _fishbone(
      bullets: bullets,
      measurer: measurer,
      title: title,
      guidance: guidance,
      palette: palette,
      width: width,
      height: height,
    ),
    TreeLayout.tree => _tree(
      bullets: bullets,
      measurer: measurer,
      title: title,
      guidance: guidance,
      palette: palette,
      width: width,
      height: height,
    ),
  };
}

Scene _tree({
  required List<String> bullets,
  required TextMeasurer measurer,
  required String title,
  required String guidance,
  required TreePalette palette,
  required double width,
  required double height,
}) {
  final nodes = <SceneNode>[];
  const margin = 32.0;
  var y = margin;

  if (title.trim().isNotEmpty) {
    nodes.add(
      SceneText(
        x: margin,
        y: y + 24,
        text: title.trim(),
        fontSize: 26,
        fill: palette.ink,
        fontWeight: 700,
      ),
    );
    y += 36;
  }
  if (guidance.isNotEmpty) {
    nodes.add(
      SceneText(
        x: margin,
        y: y + 12,
        text: guidance,
        fontSize: 12,
        fill: palette.muted,
      ),
    );
    y += 22;
  }

  const fontSize = 14.0;
  final lineH = measurer.lineHeight(fontSize: fontSize);
  for (final b in bullets) {
    if (y > height - margin) break;
    final level = bulletLevel(b);
    final text = bulletText(b).trim();
    if (text.isEmpty) continue;
    final x = margin + level * 28.0;
    nodes.add(
      SceneText(
        x: x,
        y: y + fontSize,
        text: '• $text',
        fontSize: fontSize,
        fill: palette.ink,
        fontWeight: level == 0 ? 600 : 400,
      ),
    );
    y += lineH + 4;
  }

  return Scene(width: width, height: height, nodes: nodes);
}

Scene _fishbone({
  required List<String> bullets,
  required TextMeasurer measurer,
  required String title,
  required String guidance,
  required TreePalette palette,
  required double width,
  required double height,
}) {
  final nodes = <SceneNode>[];
  const margin = 28.0;
  var top = margin;

  if (title.trim().isNotEmpty) {
    nodes.add(
      SceneText(
        x: margin,
        y: top + 22,
        text: title.trim(),
        fontSize: 24,
        fill: palette.ink,
        fontWeight: 700,
      ),
    );
    top += 32;
  }

  // Spine from left to head on the right.
  final spineY = (top + height - margin) / 2;
  final spineLeft = margin + 20;
  final spineRight = width - margin - 100;
  nodes.add(
    SceneLine(
      x1: spineLeft,
      y1: spineY,
      x2: spineRight,
      y2: spineY,
      stroke: palette.bone,
      strokeWidth: 3,
    ),
  );
  // Head (effect box).
  nodes.add(
    SceneRect(
      x: spineRight,
      y: spineY - 28,
      width: 90,
      height: 56,
      fill: '#FEF3C7',
      stroke: palette.accent,
      cornerRadius: 6,
    ),
  );
  nodes.add(
    SceneText(
      x: spineRight + 10,
      y: spineY + 6,
      text: 'Effect',
      fontSize: 13,
      fill: palette.accent,
      fontWeight: 700,
    ),
  );

  // Group bullets into top-level categories + children.
  final categories = <({String label, List<String> kids})>[];
  String? current;
  var kids = <String>[];
  void flush() {
    final label = current;
    if (label == null) return;
    categories.add((label: label, kids: List<String>.from(kids)));
    kids = [];
  }

  for (final b in bullets) {
    final level = bulletLevel(b);
    final text = bulletText(b).trim();
    if (level == 0) {
      flush();
      current = text.isEmpty ? '—' : text;
    } else if (text.isNotEmpty) {
      kids.add(text);
    }
  }
  flush();

  final n = categories.isEmpty ? 1 : categories.length;
  for (var i = 0; i < categories.length; i++) {
    final cat = categories[i];
    final above = i.isEven;
    final t = (i + 0.5) / n;
    final joinX = spineLeft + (spineRight - spineLeft) * t;
    final tipY = above ? top + 24 : height - margin - 16;
    nodes.add(
      SceneLine(
        x1: joinX,
        y1: spineY,
        x2: joinX - 40,
        y2: tipY,
        stroke: palette.bone,
        strokeWidth: 2,
      ),
    );
    nodes.add(
      SceneText(
        x: joinX - 38,
        y: tipY + (above ? 14 : -4),
        text: cat.label,
        fontSize: 12,
        fill: palette.accent,
        fontWeight: 700,
      ),
    );
    var cy = tipY + (above ? 28 : -18);
    for (final kid in cat.kids.take(4)) {
      nodes.add(
        SceneText(
          x: joinX - 36,
          y: cy,
          text: '• $kid',
          fontSize: 11,
          fill: palette.ink,
        ),
      );
      cy += above ? 14 : -14;
    }
  }

  return Scene(width: width, height: height, nodes: nodes);
}
