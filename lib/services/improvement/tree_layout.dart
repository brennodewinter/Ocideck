// Tree / fishbone engine → Scene (PROCESS_IMPROVEMENT §3.3).
library;

import 'dart:math' as math;

import '../../models/slide.dart';
import '../scene/scene.dart';
import 'tree_spec.dart';

part 'tree_layout_hierarchy.dart';

class TreePalette {
  const TreePalette({
    this.ink = '#0F172A',
    this.muted = '#64748B',
    this.rule = '#CBD5E1',
    this.accent = '#003399',
    this.bone = '#334155',
    this.box = '#F4F7FB',
    this.onAccent = '#FFFFFF',
  });

  final String ink;
  final String muted;
  final String rule;
  final String accent;
  final String bone;

  /// Vulling van een knoop. Los van de dia-achtergrond, zodat de kaart
  /// leesbaar blijft wanneer de dia zelf licht of donker is.
  final String box;

  /// Tekst op [accent] — wit op een donker accent, donker op een licht accent.
  final String onAccent;
}

/// Palet dat de dia-kleuren volgt. De kaart is alleen een lichte afwijking
/// van de dia-achtergrond, zodat [text] leesbaar blijft op de kaart én in de
/// titel. Een vaste lichte kaart zou op een donkere dia witte tekst op wit
/// zetten.
TreePalette treePaletteFromTheme({
  required String background,
  required String text,
  required String accent,
}) {
  if (_hexChannel(background, 0) == null ||
      _hexChannel(text, 0) == null ||
      _hexChannel(accent, 0) == null) {
    return TreePalette(ink: text, accent: accent);
  }
  final dark = _relativeLuminance(background) < 0.45;
  final box = dark
      ? _mixHex(background, '#FFFFFF', 0.10)
      : _mixHex(background, '#E4EAF3', 0.72);
  final rule = dark
      ? _mixHex(background, '#FFFFFF', 0.34)
      : _mixHex(accent, background, 0.78);
  final onAccent = _relativeLuminance(accent) < 0.30 ? '#FFFFFF' : '#0F172A';
  return TreePalette(
    ink: text,
    muted: _mixHex(text, background, 0.38),
    rule: rule,
    accent: accent,
    bone: dark ? _mixHex(text, background, 0.25) : '#334155',
    box: box,
    onAccent: onAccent,
  );
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
  final top = _paintTreeHeader(
    nodes,
    title: title,
    guidance: guidance,
    palette: palette,
  );
  _paintHierarchy(
    nodes: nodes,
    bullets: bullets,
    measurer: measurer,
    palette: palette,
    top: top,
    width: width,
    height: height,
  );
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

int? _hexChannel(String hex, int index) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length < 6) return null;
  return int.tryParse(h.substring(index * 2, index * 2 + 2), radix: 16);
}

double _relativeLuminance(String hex) {
  final channels = [
    _hexChannel(hex, 0),
    _hexChannel(hex, 1),
    _hexChannel(hex, 2),
  ];
  if (channels.any((c) => c == null)) return 1;
  double linear(int channel) {
    final s = channel / 255;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(channels[0]!) +
      0.7152 * linear(channels[1]!) +
      0.0722 * linear(channels[2]!);
}

String _mixHex(String a, String b, double t) {
  String channel(int index) {
    final from = _hexChannel(a, index);
    final to = _hexChannel(b, index);
    if (from == null || to == null) return '00';
    final mixed = (from + (to - from) * t).round().clamp(0, 255);
    return mixed.toRadixString(16).padLeft(2, '0');
  }

  return '#${channel(0)}${channel(1)}${channel(2)}'.toUpperCase();
}
