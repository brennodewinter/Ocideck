import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../models/slide.dart';
import '../../services/improvement_ai_service.dart';
import '../../services/privacy/privacy_own_identity.dart';
import '../../services/privacy/privacy_projection.dart';
import '../../state/settings_provider.dart';
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
          context: _projectForExternal(ref, contextBuilder()),
          languageName:
              AppLocalizations.languageNames[l10n.languageCode] ?? 'English',
        );
      },
      onSuggested: onSuggested,
      onAccepted: onAccepted,
      padding: const EdgeInsets.only(top: 2, bottom: 6),
    );
  }

  ImprovementAiContext _projectForExternal(
    WidgetRef ref,
    ImprovementAiContext source,
  ) {
    final settings = ref.read(settingsProvider);
    // Project all grounding fields together so the scanner can combine facts
    // across fields (for example a name in the title and a diagnosis below).
    final projected = PrivacyProjection.forExternalProcessing(
      Deck(
        title: '',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: source.slideTitle,
            subtitle: source.templateId,
            columnTitle1: source.layout,
            columnTitle2: source.fieldLabel,
            customMarkdown: source.existingText,
            notes: source.siblingText,
          ),
        ],
      ),
      disabledRules: settings.privacyDisabledRules,
      ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
    ).deck.slides.single;

    return ImprovementAiContext(
      slideTitle: projected.title,
      templateId: projected.subtitle,
      layout: projected.columnTitle1,
      fieldLabel: projected.columnTitle2,
      existingText: projected.customMarkdown,
      siblingText: projected.notes,
    );
  }
}
