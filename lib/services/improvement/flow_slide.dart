// Bridge: bullets ↔ FlowStep + derived roll-ups (PROCESS_IMPROVEMENT §3.4/§11).
library;

import '../../models/slide.dart';
import 'flow_spec.dart';

final _attr = RegExp(r'([a-zA-Z]+)\s*=\s*([^;]+)');

List<String> flowStarterBullets(String templateId) => List<String>.from(
  flowTemplateById(templateId)?.starterBullets ??
      bundledFlowTemplates.first.starterBullets,
);

FlowLayout flowLayoutOf(Slide slide) {
  if (slide.improvementLayout.isNotEmpty) {
    return flowLayoutFromToken(slide.improvementLayout);
  }
  return flowTemplateById(slide.improvementTemplateId)?.defaultLayout ??
      FlowLayout.flow;
}

/// Parse `title :: kind :: attrs` (timeline convention). Missing parts allowed.
FlowStep parseFlowBullet(String raw) {
  final text = bulletText(raw).trim();
  final parts = text.split('::').map((s) => s.trim()).toList();
  final title = parts.isNotEmpty ? parts[0] : '';
  final kind = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'process';
  final attrs = parts.length > 2 ? parts[2] : (parts.length == 2 ? '' : '');
  // When only two parts and second looks like attrs (has =), treat as attrs.
  var kindOut = kind;
  var attrStr = attrs;
  if (parts.length == 2 && kind.contains('=')) {
    kindOut = 'process';
    attrStr = kind;
  }
  double pt = 0, lt = 0, wip = 0, fte = 0, fpy = 0;
  var lane = '';
  for (final m in _attr.allMatches(attrStr)) {
    final key = m.group(1)!.toLowerCase();
    final val = m.group(2)!.trim();
    switch (key) {
      case 'pt':
        pt = parseDurationMinutes(val);
      case 'lt':
        lt = parseDurationMinutes(val);
      case 'wip':
        wip = double.tryParse(val.replaceAll(',', '.')) ?? 0;
      case 'fte':
        fte = double.tryParse(val.replaceAll(',', '.')) ?? 0;
      case 'fpy':
        fpy = double.tryParse(val.replaceAll(',', '.')) ?? 0;
      case 'lane':
        lane = val;
    }
  }
  return FlowStep(
    title: title,
    kind: kindOut.toLowerCase(),
    processMinutes: pt,
    leadMinutes: lt,
    wip: wip,
    fte: fte,
    fpy: fpy,
    lane: lane,
  );
}

List<FlowStep> flowStepsFromBullets(List<String> bullets) => [
  for (final b in bullets)
    if (bulletText(b).trim().isNotEmpty) parseFlowBullet(b),
];

/// Parse `12m`, `2d`, `1h`, `30` (minutes) → minutes.
double parseDurationMinutes(String raw) {
  final s = raw.trim().toLowerCase().replaceAll(',', '.');
  if (s.isEmpty) return 0;
  final m = RegExp(r'^([0-9]*\.?[0-9]+)\s*([a-z]*)$').firstMatch(s);
  if (m == null) return double.tryParse(s) ?? 0;
  final n = double.tryParse(m.group(1)!) ?? 0;
  return switch (m.group(2)!) {
    'd' || 'day' || 'days' => n * 24 * 60,
    'h' || 'hr' || 'hrs' || 'hour' || 'hours' => n * 60,
    's' || 'sec' || 'secs' => n / 60,
    _ => n, // minutes default
  };
}

FlowRollup deriveFlowRollup(List<FlowStep> steps) {
  var pt = 0.0;
  var lt = 0.0;
  var wip = 0.0;
  FlowStep? bottleneck;
  for (final s in steps) {
    pt += s.processMinutes;
    lt += s.leadMinutes;
    wip += s.wip;
    if (s.isProcess &&
        (bottleneck == null || s.processMinutes > bottleneck.processMinutes)) {
      bottleneck = s;
    }
  }
  final pce = lt <= 0 ? 0.0 : pt / lt;
  // Little's Law: WIP ≈ throughput × lead time. Rough check using total LT
  // in days and assuming one unit/day throughput when WIP is set.
  var warning = '';
  if (wip > 0 && lt > 0) {
    final ltDays = lt / (24 * 60);
    // If WIP is wildly larger than LT-days (e.g. > 20×), flag it.
    if (wip > ltDays * 20 && ltDays > 0) {
      warning =
          'WIP $wip vs lead ${ltDays.toStringAsFixed(1)}d — check Little\'s Law';
    }
  }
  return FlowRollup(
    totalProcessMinutes: pt,
    totalLeadMinutes: lt,
    pce: pce,
    bottleneckTitle: bottleneck?.title ?? '',
    littlesLawWarning: warning,
  );
}

String formatMinutes(double minutes) {
  if (minutes <= 0) return '0m';
  if (minutes >= 24 * 60) {
    return '${(minutes / (24 * 60)).toStringAsFixed(1)}d';
  }
  if (minutes >= 60) return '${(minutes / 60).toStringAsFixed(1)}h';
  return '${minutes.round()}m';
}
