import 'finding_ai_service.dart';
import 'improvement/tree_slide.dart';

/// Guardrails for Procesverbetering AI drafting (PROCESS_IMPROVEMENT §9).
///
/// The model may polish wording only — never emit a cause, conclusion,
/// statistic, or golden-thread id that is not already in the user's facts.
/// Mirrors [stripFabricatedIds] from the MIAUW finding consumer.

/// Bare **Y-nn** / **X-nn** tokens (without the Markdown bold wrapper).
final RegExp improvementIdBarePattern = RegExp(
  r'(?<![A-Za-z0-9])([YX]-\d+)\b',
  caseSensitive: false,
);

/// Whether [draft] looks like a cause list — forbidden on tree/fishbone fields.
bool containsCauseListPattern(String draft) {
  final t = draft.trim();
  if (t.isEmpty) return false;

  final lines = t.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length >= 2) {
    final listLines = lines.where((l) {
      final s = l.trimLeft();
      return s.startsWith('- ') ||
          s.startsWith('* ') ||
          s.startsWith('• ') ||
          RegExp(r'^\d+[.)]\s').hasMatch(s);
    }).length;
    if (listLines >= 2) return true;

    final categoryLines = lines.where((l) {
      return RegExp(r'^\s*\w[\w\s]{0,40}:\s').hasMatch(l);
    }).length;
    if (categoryLines >= 2) return true;
  }

  return RegExp(
    r'\b(?:possible causes?|root causes?|likely causes?|'
    r'mogelijke oorzaken|hoofdoorzaken|visgraat|fishbone|ishikawa)\b',
    caseSensitive: false,
  ).hasMatch(t);
}

/// Whether [draft] states a conclusion the model must not invent.
bool containsConclusionPattern(String draft) {
  return RegExp(
    r'\b(?:therefore|thus|hence|conclude|conclusion|conclusie|gevolg|'
    r'bewezen|proven|root cause is|hoofdoorzaak is|waarschijnlijk de oorzaak)\b',
    caseSensitive: false,
  ).hasMatch(draft);
}

/// Strip **Y-nn** / **X-nn** ids absent from [context] (the user's facts).
String stripFabricatedImprovementIds(String draft, String context) {
  final ctx = context.toLowerCase();
  var out = draft.replaceAllMapped(improvementIdPattern, (m) {
    final id = m.group(1)!;
    return ctx.contains(id.toLowerCase()) ? m.group(0)! : '';
  });
  out = out.replaceAllMapped(improvementIdBarePattern, (m) {
    final id = m.group(1)!;
    return ctx.contains(id.toLowerCase()) ? id : '';
  });
  return _tidyAfterRemoval(out);
}

/// Remove statistic-like numeric claims (Cpk, RPN, %, measurements, …).
String stripStatisticClaims(String draft) {
  var out = draft.replaceAll(_reStatisticClaims, '');
  return _tidyAfterRemoval(out);
}

final _reStatisticClaims = RegExp(
  r'\b(?:C[pP][kK]|P[pP][kK]|RPN|sigma\s+level|σ\s+level|'
  r'UCL|LCL|USL|LSL|DPMO|ppm)\s*(?:[=:]\s*)?\d+(?:[.,]\d+)?'
  r'|\b\d+(?:[.,]\d+)?\s*%(?!\w)'
  r'|\b\d+(?:[.,]\d+)?\s*(?:ppm|ppb|mg|kg|g|mm|cm|m|s|ms|min|uur|hours?)\b'
  r'|\b\d+(?:[.,]\d+)?\s*(?:sigma|σ)\b'
  r'|\b\d+(?:[.,]\d+)?\s*(?:C[pP][kK]|P[pP][kK]|RPN)\b',
  caseSensitive: false,
);

String _tidyAfterRemoval(String out) {
  return out
      .replaceAll(RegExp(r'\(\s*\)'), '')
      .replaceAll(RegExp(r'\[\s*\]'), '')
      .replaceAllMapped(RegExp(r' +([.,;:])'), (m) => m.group(1)!)
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

/// Apply all Procesverbetering guardrails to a raw model [draft].
///
/// When [treeOrFishbone] is true, cause-list patterns reject the whole draft.
/// Returns empty when nothing safe remains.
String filterImprovementDraft(
  String draft,
  String context, {
  required bool treeOrFishbone,
}) {
  var out = cleanFindingDraft(draft);
  if (out.isEmpty) return '';
  if (treeOrFishbone && containsCauseListPattern(out)) return '';
  if (containsConclusionPattern(out)) return '';
  out = stripFabricatedImprovementIds(out, context);
  out = stripStatisticClaims(out);
  return out.trim();
}
