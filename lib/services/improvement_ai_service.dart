import 'ai_client_service.dart';
import 'finding_ai_service.dart';
import 'improvement_ai_guard.dart';

/// The Procesverbetering free-text drafting consumer of the shared AI backend
/// (PROCESS_IMPROVEMENT §9). Draft-only: callers mark the field
/// `ocideck_ai_assisted` so sealing blocks until a human reviews it.

/// Which improvement slide field is being drafted.
enum ImprovementAiField { canvasRegion, matrixCell, treeBullet, flowStep }

/// User facts the model may ground on — never invent beyond these.
class ImprovementAiContext {
  const ImprovementAiContext({
    this.slideTitle = '',
    this.templateId = '',
    this.layout = '',
    this.fieldLabel = '',
    this.existingText = '',
    this.siblingText = '',
  });

  final String slideTitle;
  final String templateId;
  final String layout;
  final String fieldLabel;
  final String existingText;
  final String siblingText;
}

/// Assemble the grounding block from [c].
String buildImprovementContext(ImprovementAiContext c) {
  String? line(String label, String value) =>
      value.trim().isEmpty ? null : '$label: ${value.trim()}';
  return [
    line('Slide', c.slideTitle),
    line('Template', c.templateId),
    line('Layout', c.layout),
    line('Field', c.fieldLabel),
    line('Current text', c.existingText),
    line('Other fields on this slide', c.siblingText),
  ].whereType<String>().join('\n');
}

/// Per-field instruction: wording only, no causes/conclusions/numbers.
String improvementInstruction(
  ImprovementAiField field,
  String languageName, {
  required bool treeOrFishbone,
}) {
  final where = switch (field) {
    ImprovementAiField.canvasRegion => 'a canvas region',
    ImprovementAiField.matrixCell => 'a matrix cell',
    ImprovementAiField.treeBullet => 'a tree slide bullet',
    ImprovementAiField.flowStep => 'a process-flow step label',
  };
  final extra = treeOrFishbone
      ? ' Do NOT brainstorm, list or name causes, categories or sub-causes.'
      : '';
  return 'Write concise wording for $where in $languageName, as one short '
      'paragraph or a single line. Use only the facts above; do NOT invent '
      'causes, conclusions, statistics, measurements, or Y-nn/X-nn identifiers '
      'that are not listed there.$extra Return only the text, with no preamble.';
}

bool improvementFieldIsTreeOrFishbone(ImprovementAiField field) =>
    field == ImprovementAiField.treeBullet;

/// Wraps a gated [AiClientService] as the improvement wording consumer.
class ImprovementAiService {
  ImprovementAiService(this._client);

  final AiClientService _client;

  Future<String> suggest({
    required ImprovementAiField field,
    required ImprovementAiContext context,
    required String languageName,
  }) async {
    final facts = buildImprovementContext(context);
    final treeOrFishbone = improvementFieldIsTreeOrFishbone(field);
    final draft = await _client.suggest(
      context: facts,
      instruction: improvementInstruction(
        field,
        languageName,
        treeOrFishbone: treeOrFishbone,
      ),
    );
    return filterImprovementDraft(
      cleanFindingDraft(draft),
      facts,
      treeOrFishbone: treeOrFishbone,
    );
  }
}
