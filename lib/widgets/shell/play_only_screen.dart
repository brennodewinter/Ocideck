// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Vergrendeld 'alleen afspelen'-scherm. Wordt door [_TabContent] getoond in
/// plaats van [_MainLayout] wanneer het open deck `playOnly` is: geen editor,
/// toolbar, menu's of sneltoetsen — enkel de eerste slide met een afspeelknop.
/// De presentatie start in volledig scherm (via [presentDeck]); sluiten van het
/// tabblad geeft de normale werking terug.
class _PlayOnlyScreen extends ConsumerWidget {
  const _PlayOnlyScreen({this.resumeFromSelection = false});

  /// Een gewone vergrendelde presentatie begint vooraan. Bij een cursus heeft
  /// het geopende tabblad juist de door OciServe teruggegeven hervatdia als
  /// selectie; die selectie mag de afspeelknop niet opnieuw naar dia één wissen.
  final bool resumeFromSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final deck = ref.watch(deckProvider.select((s) => s.deck));
    if (deck == null) return const SizedBox.shrink();

    // Ook de voorvertoning is een publieksoppervlak. Projecteer dus vóór het
    // renderen en toon bij hervatten dezelfde geselecteerde dia als de speler.
    final settings = ref.watch(settingsProvider);
    final audience = PrivacyProjection.forAudience(
      deck,
      disabledRules: settings.privacyDisabledRules,
      regions: settings.privacyRegions,
      ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
    );
    final slides = audience.slides;
    final selectedIndex = ref.watch(
      editorProvider.select((state) => state.selectedIndex),
    );
    final selectedId = selectedIndex >= 0 && selectedIndex < deck.slides.length
        ? deck.slides[selectedIndex].id
        : null;
    final projectedIndex = resumeFromSelection && selectedId != null
        ? slides.indexWhere((slide) => slide.id == selectedId)
        : 0;
    final previewIndex = projectedIndex < 0 ? 0 : projectedIndex;
    final previewSlide = slides.isEmpty ? null : slides[previewIndex];
    final isResume = resumeFromSelection && previewIndex > 0;
    final learningSession = ref.watch(learningSessionProvider);

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
                        if (previewSlide != null)
                          _firstSlideHero(
                            audience.deck,
                            previewSlide,
                            previewIndex,
                            slides.length,
                            settings,
                          )
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
                        if (previewSlide != null) ...[
                          _slidePosition(l10n, palette, previewIndex, slides),
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
                              onPressed: previewSlide == null
                                  ? null
                                  : () => presentDeck(
                                      context,
                                      ref,
                                      fromStart: !resumeFromSelection,
                                    ),
                              icon: const Icon(Icons.play_arrow),
                              label: Text(
                                l10n.d(isResume ? 'Verdergaan' : 'Afspelen'),
                              ),
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
                            _exitButton(context, ref, learningSession),
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

  Widget _exitButton(
    BuildContext context,
    WidgetRef ref,
    LearningSessionRef? learningSession,
  ) => OutlinedButton.icon(
    onPressed: () => learningSession == null
        ? requestCloseTab(context, ref, ref.read(tabsProvider).clampedIndex)
        : _returnToCourses(context, ref),
    icon: Icon(learningSession == null ? Icons.close : Icons.arrow_back),
    label: Text(
      context.l10n.d(
        learningSession == null ? 'Sluiten' : 'Terug naar mijn cursussen',
      ),
    ),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    ),
  );

  Widget _slidePosition(
    AppLocalizations l10n,
    AppPalette palette,
    int previewIndex,
    List<Slide> slides,
  ) => Text(
    '${l10n.d('Dia')} ${previewIndex + 1} / ${slides.length}',
    key: const Key('learning-slide-position'),
    style: TextStyle(color: palette.mutedText, fontWeight: FontWeight.w600),
  );

  /// Toont de eerste slide als statische hero (16:9, met slagschaduw). Bewust
  /// niet-interactief: geen media, geen links — enkel een voorproefje.
  Widget _firstSlideHero(
    Deck deck,
    Slide slide,
    int slideIndex,
    int slideCount,
    AppSettings settings,
  ) {
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
          slideNumber: slideIndex + 1,
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
