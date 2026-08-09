// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Vergrendeld 'alleen afspelen'-scherm. Wordt door [_TabContent] getoond in
/// plaats van [_MainLayout] wanneer het open deck `playOnly` is: geen editor,
/// toolbar, menu's of sneltoetsen — enkel de eerste slide met een afspeelknop.
/// De presentatie start in volledig scherm (via [presentDeck]); sluiten van het
/// tabblad geeft de normale werking terug.
class _PlayOnlyScreen extends ConsumerWidget {
  const _PlayOnlyScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final deck = ref.watch(deckProvider.select((s) => s.deck));
    if (deck == null) return const SizedBox.shrink();

    // Dezelfde slide-set als bij het presenteren, zodat de getoonde eerste slide
    // exact overeenkomt met wat afgespeeld wordt.
    final slides = _slidesForPresentationOrExport(deck);
    final firstSlide = slides.isNotEmpty
        ? slides.first
        : (deck.slides.isNotEmpty ? deck.slides.first : null);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (firstSlide != null)
                          _firstSlideHero(deck, firstSlide, slides.length, ref)
                        else
                          _emptyHero(l10n, palette, deck),
                        const SizedBox(height: 28),
                        if (deck.title.trim().isNotEmpty) ...[
                          Text(
                            deck.title.trim(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 15,
                              color: palette.mutedText,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                l10n.d(
                                  'Deze presentatie is vergrendeld op alleen afspelen.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.mutedText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: firstSlide == null
                                  ? null
                                  : () => presentDeck(
                                      context,
                                      ref,
                                      fromStart: true,
                                    ),
                              icon: const Icon(Icons.play_arrow),
                              label: Text(l10n.d('Afspelen')),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 18,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => requestCloseTab(
                                context,
                                ref,
                                ref.read(tabsProvider).clampedIndex,
                              ),
                              icon: const Icon(Icons.close),
                              label: Text(l10n.d('Sluiten')),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Toont de eerste slide als statische hero (16:9, met slagschaduw). Bewust
  /// niet-interactief: geen media, geen links — enkel een voorproefje.
  Widget _firstSlideHero(
    Deck deck,
    Slide slide,
    int slideCount,
    WidgetRef ref,
  ) {
    final settings = ref.watch(settingsProvider);
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRect(
        child: SlidePreviewWidget(
          slide: slide,
          projectPath: deck.projectPath,
          themeProfile: deck.themeProfile,
          deckMarpStyle: deck.marpStyle,
          cockpitColorScheme: settings.cockpitColorScheme,
          allowRemoteMedia: settings.allowRemoteMedia,
          onLinkTap: openExternalUrl,
          slideNumber: 1,
          slideCount: slideCount,
          scopeCia: deckScopeCiaIndex(deck.slides),
          reportLanguage: deck.language,
          tlp: deck.tlp,
          organization: deck.organization,
          showClassificationWatermark: settings.classificationWatermarkEnabled,
          improvementY01: deck.improvementY01Metric,
        ),
      ),
    );
  }

  Widget _emptyHero(AppLocalizations l10n, AppPalette palette, Deck deck) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.mutedText.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            emptyAudienceReason(l10n, deck, forExport: false),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.mutedText),
          ),
        ),
      ),
    );
  }
}
