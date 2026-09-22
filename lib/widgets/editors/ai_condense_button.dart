import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_condense_service.dart';
import '../../services/secret_store.dart';
import '../../state/consent_provider.dart';
import '../../state/deck_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../dialogs/ai_condense_dialog.dart';

/// De "Vat samen met AI…"-knop onder het tekstveld van een vrije-tekstdia.
///
/// Zichtbaar alleen als de optionele AI-backend aan én geconfigureerd staat
/// (`ai.enabled && ai.isConfigured`, dezelfde poort als [AiSuggestField]) en
/// er tekst is om in te korten. De dialoog levert het concept; het toepassen
/// is één `updateSlide` met `bumpRevision` — een eigen ongedaan-stap (geen
/// coalescing met het typen ervoor) én een editor-remount die de velden met
/// de nieuwe inhoud laadt.
class AiCondenseButton extends ConsumerWidget {
  const AiCondenseButton({super.key, required this.slide});

  final Slide slide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(settingsProvider.select((s) => s.aiSettings));
    if (!(ai.enabled && ai.isConfigured) ||
        slide.customMarkdown.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _open(context, ref),
        icon: Icon(
          Icons.auto_awesome_outlined,
          size: 16,
          color: AppTheme.accentFg,
        ),
        label: Text(
          l10n.d('Vat samen met AI…'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    // De prompt volgt de deck-taal, niet de interface-taal; is die niet
    // vastgelegd dan is de interface-taal de beste schatting.
    final deckLanguage = ref.read(
      deckProvider.select((s) => s.deck?.language ?? ''),
    );
    final languageName =
        AppLocalizations.languageNames[deckLanguage.isNotEmpty
            ? deckLanguage
            : l10n.languageCode] ??
        'English';
    final result = await showAiCondenseDialog(
      context,
      generate: (mode, style) async {
        final settings = ref.read(settingsProvider).aiSettings;
        final client = AiClientService(
          settings: settings,
          hasOutboundConsent: ref.read(consentProvider).hasAccepted,
          apiKey: await SecretStore().readAiApiKey(settings.baseUrl),
        );
        return AiCondenseService(client).condense(
          mode: mode,
          listStyle: style,
          sourceText: slide.customMarkdown,
          languageName: languageName,
        );
      },
    );
    if (result == null || !context.mounted) return;
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final idx = deck.slides.indexWhere((s) => s.id == slide.id);
    if (idx < 0) return;
    ref
        .read(deckProvider.notifier)
        .updateSlide(
          idx,
          applyCondenseToSlide(
            slide,
            result,
            notesHeading: l10n.d('Oorspronkelijke tekst'),
          ),
          bumpRevision: true,
        );
  }
}
