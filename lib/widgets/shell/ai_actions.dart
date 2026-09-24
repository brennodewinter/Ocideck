part of '../app_shell.dart';

/// AI-related shell actions, split into a `part of` file to keep
/// `app_shell_main_layout.dart` under the line limit — and written as
/// top-level functions because members of an extension on `_MainLayoutState`
/// still count toward its class-size ceiling, while these do not.

/// Safety net (AI_ASSIST §6.4): wipe every still-unreviewed AI-generated image
/// alt-text, keeping human-written and reviewed ones. Confirmed and undoable.
Future<void> clearAiAltTexts(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final notifier = ref.read(deckProvider.notifier);
  final count = notifier.aiGeneratedAltTextCount;
  if (count == 0) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('AI-alt-teksten wissen')),
      content: Text(
        '${l10n.d('Verwijder alle nog niet-nagekeken AI-alt-teksten? Handmatige en nagekeken alt-teksten blijven staan.')} '
        '(${l10n.d('aantal')}: $count)',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.d('Wissen')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final cleared = notifier.clearAiGeneratedAltTexts();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$cleared ${l10n.d('AI-alt-teksten gewist.')}')),
  );
}

/// "Vertaal met AI…" — vertaalt het hele deck (zichtbare tekst én
/// speakernotities) en opent de vertaling als onopgeslagen kopie in een
/// nieuw tabblad. Het origineel blijft ongemoeid; de kopie krijgt
/// `aiAssistedFields`-markeringen zodat de vertaling als concept te
/// herkennen blijft.
Future<void> translateDeckWithAi(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final deck = ref.read(deckProvider).deck;
  if (deck == null || deck.slides.isEmpty) return;
  final result = await showAiTranslateDialog(
    context,
    // De doeltaal staat standaard op de interface-taal; is die toevallig
    // de deck-taal zelf, dan kiest de gebruiker zelf anders.
    initialLanguageCode: l10n.languageCode,
    translate: (code, name, onProgress, isCancelled) async {
      final settings = ref.read(settingsProvider).aiSettings;
      final client = AiClientService(
        settings: settings,
        hasOutboundConsent: ref.read(consentProvider).hasAccepted,
        apiKey: await ref
            .read(secretStoreProvider)
            .readAiApiKey(settings.baseUrl),
      );
      return AiTranslateService(client).translateDeck(
        deck: deck,
        languageCode: code,
        languageName: name,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    },
  );
  if (result == null || !context.mounted) return;
  openDeckCopyInTab(ref.read(tabsProvider.notifier), result.deck);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        result.failedSlides == 0
            ? l10n.d('Vertaalde kopie geopend in nieuw tabblad.')
            : '${l10n.d('Vertaalde kopie geopend in nieuw tabblad.')} '
                  '${result.failedSlides} '
                  "${l10n.d("dia's overgeslagen — originele tekst behouden.")}",
      ),
    ),
  );
}

/// De AI-commando's voor het commandopalet. Top-level zodat ze niet op het
/// plafond van `_MainLayoutState` drukken — zelfde patroon als
/// [collabPaletteCommands].
List<PaletteCommand> aiPaletteCommands(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  Deck deck,
  DeckNotifier deckNotifier,
) => [
  PaletteCommand(
    label: l10n.d('Wis AI-alt-teksten'),
    icon: Icons.auto_delete_outlined,
    keywords: const ['ai', 'alt', 'accessibility', 'undo'],
    enabled: deckNotifier.aiGeneratedAltTextCount > 0,
    onInvoke: () => clearAiAltTexts(context, ref),
  ),
  PaletteCommand(
    label: l10n.d('Vertaal met AI'),
    icon: Icons.translate,
    keywords: const ['ai', 'translate', 'vertalen', 'taal', 'language'],
    enabled:
        ref.read(settingsProvider).aiSettings.isConfigured &&
        deck.slides.isNotEmpty,
    onInvoke: () => translateDeckWithAi(context, ref),
  ),
];

/// De AI-items voor het ⋮-menu, top-level zoals [openKatShellMenuEntries].
/// Alleen zichtbaar als de optionele AI-backend aan én geconfigureerd staat —
/// dezelfde poort als de "Vat samen met AI"-knop.
List<PopupMenuEntry<String>> aiShellMenuEntries(
  WidgetRef ref,
  AppLocalizations l10n,
) {
  if (!ref.read(settingsProvider).aiSettings.isConfigured) return const [];
  return [
    shellMenuItem('translate_ai', Icons.translate, l10n.d('Vertaal met AI…')),
  ];
}
