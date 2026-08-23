import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_client_service.dart';
import '../../services/finding_ai_service.dart';
import '../../services/secret_store.dart';
import '../../state/consent_provider.dart';
import '../../state/settings_provider.dart';
import 'ai_suggest_control.dart';

/// A control row under a free-text finding field: a **Tekst voorstellen (AI)**
/// button (when the optional AI backend is on) and, once a draft has been
/// inserted, an **AI-concept** badge + **Nagekeken** button. Draft-only
/// (PENTEST_MIAUW §16): suggesting marks the field `ocideck_ai_assisted` (via
/// [onSuggested]) so the seal step blocks until the tester clears it with
/// "Nagekeken" ([onAccepted]). The field's own controller stays in the editor;
/// this widget only drives the AI call and the provenance chrome.
class AiSuggestField extends ConsumerWidget {
  const AiSuggestField({
    super.key,
    required this.field,
    required this.contextBuilder,
    required this.hasExistingText,
    required this.isAiDraft,
    required this.onSuggested,
    required this.onAccepted,
  });

  final FindingAiField field;
  final FindingAiContext Function() contextBuilder;
  final bool hasExistingText;
  final bool isAiDraft;
  final ValueChanged<String> onSuggested;
  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(settingsProvider).aiSettings;
    return AiSuggestControl(
      isAvailable: ai.enabled && ai.isConfigured,
      hasExistingText: hasExistingText,
      isAiDraft: isAiDraft,
      loadSuggestion: () async {
        final l10n = context.l10n;
        final settings = ref.read(settingsProvider).aiSettings;
        final client = AiClientService(
          settings: settings,
          hasOutboundConsent: ref.read(consentProvider).hasAccepted,
          apiKey: await SecretStore().readAiApiKey(settings.baseUrl),
        );
        return FindingAiService(client).suggest(
          field: field,
          context: contextBuilder(),
          languageName:
              AppLocalizations.languageNames[l10n.languageCode] ?? 'English',
        );
      },
      onSuggested: onSuggested,
      onAccepted: onAccepted,
    );
  }
}
