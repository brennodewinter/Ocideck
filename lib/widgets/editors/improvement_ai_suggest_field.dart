import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/improvement_ai_service.dart';
import '../../state/improvement_ai_provider.dart';
import 'ai_suggest_control.dart';

/// Per-field AI suggest control for Procesverbetering slides (§9). Requires
/// both the AI and Procesverbetering modules; marks the field `ocideck_ai_assisted`.
class ImprovementAiSuggestField extends ConsumerWidget {
  const ImprovementAiSuggestField({
    super.key,
    required this.field,
    required this.fieldKey,
    required this.contextBuilder,
    required this.hasExistingText,
    required this.isAiDraft,
    required this.onSuggested,
    required this.onAccepted,
  });

  final ImprovementAiField field;
  final String fieldKey;
  final ImprovementAiContext Function() contextBuilder;
  final bool hasExistingText;
  final bool isAiDraft;
  final ValueChanged<String> onSuggested;
  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return AiSuggestControl(
      isAvailable: ref.watch(improvementAiAvailableProvider),
      hasExistingText: hasExistingText,
      isAiDraft: isAiDraft,
      loadSuggestion: () async {
        final client = await ref.read(improvementAiClientFactoryProvider)();
        return ImprovementAiService(client).suggest(
          field: field,
          context: contextBuilder(),
          languageName:
              AppLocalizations.languageNames[l10n.languageCode] ?? 'English',
        );
      },
      onSuggested: onSuggested,
      onAccepted: onAccepted,
      padding: const EdgeInsets.only(top: 2, bottom: 6),
    );
  }
}
