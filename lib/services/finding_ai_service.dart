import 'ai_client_service.dart';

/// The finding free-text drafting consumer of the shared, optional AI backend
/// (PENTEST_MIAUW §16). It drafts a single free-text finding field (description /
/// possible impact / recommendation) with the gated local model, grounded only
/// on the pentester's own facts, and enforces the hard guardrail: the model may
/// never emit a CWE/CVE/CVSS identifier that is not already in those facts —
/// [stripFabricatedIds] removes any it does. Draft-only: the caller marks the
/// field `ocideck_ai_assisted`, so the seal step blocks until a human reviews it.
/// The pure helpers ([buildFindingContext], [findingInstruction],
/// [stripFabricatedIds], [cleanFindingDraft]) are network-free and unit-testable.

/// The free-text finding fields the assistant can draft (never the identifiers).
enum FindingAiField { description, impact, recommendation }

/// The pentester's own facts for one finding — the only grounding the model gets.
class FindingAiContext {
  const FindingAiContext({
    this.heading = '',
    this.scopeObject = '',
    this.cvssVector = '',
    this.cwe = '',
    this.cveIds = const [],
    this.description = '',
    this.confirmation = '',
    this.impact = '',
    this.recommendation = '',
  });

  final String heading;
  final String scopeObject;
  final String cvssVector;
  final String cwe;
  final List<String> cveIds;
  final String description;
  final String confirmation;
  final String impact;
  final String recommendation;
}

/// Assemble the grounding facts block from [c] (only the non-empty lines), which
/// the client frames as untrusted data.
String buildFindingContext(FindingAiContext c) {
  String? line(String label, String value) =>
      value.trim().isEmpty ? null : '$label: ${value.trim()}';
  return [
    line('Finding', c.heading),
    line('Scope object', c.scopeObject),
    line('CVSS 4.0 vector', c.cvssVector),
    line('CWE', c.cwe),
    if (c.cveIds.isNotEmpty) 'CVE: ${c.cveIds.join(', ')}',
    line('Description', c.description),
    line('Reproduction', c.confirmation),
    line('Possible impact', c.impact),
    line('Recommendation', c.recommendation),
  ].whereType<String>().join('\n');
}

/// The per-field instruction, asking for output in [languageName] and forbidding
/// invented identifiers.
String findingInstruction(FindingAiField field, String languageName) {
  final what = switch (field) {
    FindingAiField.description =>
      'a concise, factual technical description of this vulnerability',
    FindingAiField.impact =>
      'the possible business and technical impact of this vulnerability',
    FindingAiField.recommendation =>
      'a concrete remediation recommendation for this vulnerability',
  };
  return 'Write $what in $languageName, as one short paragraph. Use only the '
      'facts above; do NOT invent or mention any CWE, CVE or CVSS identifier '
      'that is not listed there. Return only the text, with no preamble.';
}

final _reIds = RegExp(
  r'CWE-\d+|CVE-\d{4,}-\d+|CVSS:[0-9.]+/[A-Za-z0-9:/.]+',
  caseSensitive: false,
);

/// Strip fabricated identifiers (§16.3): remove any CWE/CVE/CVSS token in [draft]
/// that does not literally appear in [context] (the pentester's facts), then tidy
/// the whitespace and empty brackets a removal leaves behind.
String stripFabricatedIds(String draft, String context) {
  final ctx = context.toLowerCase();
  var out = draft.replaceAllMapped(_reIds, (m) {
    final token = m.group(0)!;
    return ctx.contains(token.toLowerCase()) ? token : '';
  });
  out = out
      .replaceAll(RegExp(r'\(\s*\)'), '')
      .replaceAll(RegExp(r'\[\s*\]'), '')
      .replaceAllMapped(RegExp(r' +([.,;:])'), (m) => m.group(1)!)
      .replaceAll(RegExp(r' {2,}'), ' ');
  return out.trim();
}

/// Tidy a raw model draft: unwrap surrounding quotes and collapse runs of spaces.
String cleanFindingDraft(String raw) {
  var t = raw.trim();
  if (t.length >= 2 &&
      ((t.startsWith('"') && t.endsWith('"')) ||
          (t.startsWith('“') && t.endsWith('”')))) {
    t = t.substring(1, t.length - 1).trim();
  }
  return t.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}

/// Wraps a gated [AiClientService] as the finding free-text drafting consumer.
class FindingAiService {
  FindingAiService(this._client);

  final AiClientService _client;

  /// Draft [field] for the finding described by [context] in [languageName].
  /// Returns the cleaned, id-filtered draft (empty = no suggestion). Propagates
  /// the client's `AiGateException` / `AiRequestException` so the caller can fall
  /// back gracefully.
  Future<String> suggest({
    required FindingAiField field,
    required FindingAiContext context,
    required String languageName,
  }) async {
    final facts = buildFindingContext(context);
    final draft = await _client.suggest(
      context: facts,
      instruction: findingInstruction(field, languageName),
    );
    return stripFabricatedIds(cleanFindingDraft(draft), facts);
  }
}
