// Flow / swimlane / VSM → Scene (PROCESS_IMPROVEMENT §3.4).
library;

import '../scene/scene.dart';
import 'flow_slide.dart';
import 'flow_spec.dart';

class FlowPalette {
  const FlowPalette({
    this.ink = '#0F172A',
    this.muted = '#64748B',
    this.rule = '#CBD5E1',
    this.accent = '#003399',
    this.va = '#15803D',
    this.nva = '#B91C1C',
    this.box = '#F8FAFC',
  });

  final String ink;
  final String muted;
  final String rule;
  final String accent;
  final String va;
  final String nva;
  final String box;
}

Scene buildFlowScene({
  required List<FlowStep> steps,
  required FlowLayout layout,
  required TextMeasurer measurer,
  String title = '',
  String guidance = '',
  FlowPalette palette = const FlowPalette(),
  double width = 960,
  double height = 540,
}) {
  final rollup = deriveFlowRollup(steps);
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
    top += 34;
  }

  // Derived roll-up strip — never stored.
  final summary =
      'PT ${formatMinutes(rollup.totalProcessMinutes)} · '
      'LT ${formatMinutes(rollup.totalLeadMinutes)} · '
      'PCE ${(rollup.pce * 100).toStringAsFixed(0)}%'
      '${rollup.bottleneckTitle.isEmpty ? '' : ' · Bottleneck: ${rollup.bottleneckTitle}'}';
  nodes.add(
    SceneText(
      x: margin,
      y: top + 12,
      text: summary,
      fontSize: 12,
      fill: palette.accent,
      fontWeight: 600,
    ),
  );
  top += 22;
  if (rollup.littlesLawWarning.isNotEmpty) {
    nodes.add(
      SceneText(
        x: margin,
        y: top + 12,
        text: rollup.littlesLawWarning,
        fontSize: 11,
        fill: palette.nva,
      ),
    );
    top += 18;
  } else if (guidance.isNotEmpty) {
    nodes.add(
      SceneText(
        x: margin,
        y: top + 12,
        text: guidance,
        fontSize: 11,
        fill: palette.muted,
      ),
    );
    top += 18;
  }

  if (layout == FlowLayout.swimlane) {
    return _swimlane(
      nodes: nodes,
      steps: steps,
      top: top,
      width: width,
      height: height,
      palette: palette,
    );
  }

  // flow + vsm: horizontal chain
  final usable = width - 2 * margin;
  final n = steps.isEmpty ? 1 : steps.length;
  final boxW = (usable / n).clamp(70.0, 160.0);
  var x = margin;
  final y = top + 20;
  final boxH = layout == FlowLayout.vsm ? 70.0 : 56.0;

  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    final fill = layout == FlowLayout.vsm
        ? (s.isInventory
              ? '#FEE2E2'
              : (s.processMinutes >= s.leadMinutes * 0.5
                    ? '#DCFCE7'
                    : '#FEF3C7'))
        : palette.box;
    final stroke = layout == FlowLayout.vsm
        ? (s.isInventory ? palette.nva : palette.va)
        : palette.rule;
    nodes.add(
      SceneRect(
        x: x,
        y: y,
        width: boxW - 8,
        height: boxH,
        fill: fill,
        stroke: stroke,
        cornerRadius: 4,
      ),
    );
    final label = s.title.isEmpty ? s.kind : s.title;
    nodes.add(
      SceneText(
        x: x + 6,
        y: y + 18,
        text: label.length > 14 ? '${label.substring(0, 13)}…' : label,
        fontSize: 11,
        fill: palette.ink,
        fontWeight: 600,
      ),
    );
    if (layout == FlowLayout.vsm) {
      nodes.add(
        SceneText(
          x: x + 6,
          y: y + 36,
          text: 'PT ${formatMinutes(s.processMinutes)}',
          fontSize: 10,
          fill: palette.va,
        ),
      );
      nodes.add(
        SceneText(
          x: x + 6,
          y: y + 50,
          text: s.isInventory
              ? 'WIP ${s.wip.round()}'
              : 'LT ${formatMinutes(s.leadMinutes)}',
          fontSize: 10,
          fill: palette.nva,
        ),
      );
    }
    if (i < steps.length - 1) {
      final ax = x + boxW - 10;
      nodes.add(
        SceneLine(
          x1: ax,
          y1: y + boxH / 2,
          x2: ax + 10,
          y2: y + boxH / 2,
          stroke: palette.muted,
          strokeWidth: 1.5,
        ),
      );
    }
    x += boxW;
  }

  return Scene(width: width, height: height, nodes: nodes);
}

Scene _swimlane({
  required List<SceneNode> nodes,
  required List<FlowStep> steps,
  required double top,
  required double width,
  required double height,
  required FlowPalette palette,
}) {
  const margin = 28.0;
  final lanes = <String>[];
  for (final s in steps) {
    final lane = s.lane.isEmpty ? '—' : s.lane;
    if (!lanes.contains(lane)) lanes.add(lane);
  }
  if (lanes.isEmpty) lanes.add('—');
  final laneH = ((height - top - margin) / lanes.length).clamp(48.0, 120.0);

  for (var li = 0; li < lanes.length; li++) {
    final y = top + li * laneH;
    nodes.add(
      SceneRect(
        x: margin,
        y: y,
        width: width - 2 * margin,
        height: laneH - 6,
        fill: li.isEven ? '#F8FAFC' : '#FFFFFF',
        stroke: palette.rule,
      ),
    );
    nodes.add(
      SceneText(
        x: margin + 8,
        y: y + 16,
        text: lanes[li],
        fontSize: 12,
        fill: palette.accent,
        fontWeight: 700,
      ),
    );
    final inLane = [
      for (final s in steps)
        if ((s.lane.isEmpty ? '—' : s.lane) == lanes[li]) s,
    ];
    var x = margin + 100.0;
    for (final s in inLane) {
      nodes.add(
        SceneRect(
          x: x,
          y: y + 22,
          width: 110,
          height: 28,
          fill: palette.box,
          stroke: palette.rule,
          cornerRadius: 3,
        ),
      );
      nodes.add(
        SceneText(
          x: x + 6,
          y: y + 40,
          text: s.title.length > 14 ? '${s.title.substring(0, 13)}…' : s.title,
          fontSize: 11,
          fill: palette.ink,
        ),
      );
      x += 120;
    }
  }

  return Scene(width: width, height: height, nodes: nodes);
}
