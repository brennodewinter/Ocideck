// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Opent de fullscreen-presenter voor het open deck. Gedeeld door de
/// hoofd-toolbar en het 'alleen afspelen'-scherm zodat beide exact dezelfde
/// slide-filtering, annotatie-koppeling en fullscreen-overgang gebruiken.
///
/// Met [fromStart] begint de presentatie bij de eerste zichtbare slide; anders
/// bij de huidige selectie — sinds #846 ook wat de gewone startknop doet.
/// Toont een melding en doet niets als er (na filtering) geen slides zijn.
/// Presenteer vanaf een gekozen dia: selecteer hem eerst, dan [presentDeck].
void _presentFromSlide(BuildContext context, WidgetRef ref, int index) {
  ref.read(editorProvider.notifier).select(index);
  presentDeck(context, ref);
}

List<int> _visiblePresentationIndexes(Deck deck) => <int>[
  for (var i = 0; i < deck.slides.length; i++)
    if (slideReachesAudience(
      deck.slides[i],
      presentationTlp: deck.tlp,
      includeDetail: true,
    ))
      i,
];

int _presentationStartIndex(
  WidgetRef ref,
  List<int> visible, {
  required bool fromStart,
}) {
  if (fromStart) return 0;
  final selectedIndex = ref.read(editorProvider).selectedIndex;
  final next = visible.indexWhere((index) => index >= selectedIndex);
  if (next >= 0) return next;
  return visible.isEmpty ? 0 : visible.length - 1;
}

class _PresentationEdits {
  _PresentationEdits(this.deckNotifier);

  final DeckNotifier deckNotifier;
  final Map<String, Slide> sessionOriginals = {};
  bool liveEdited = false;

  void slideChanged(Slide updated) {
    final index = deckNotifier.currentState.deck?.slides.indexWhere(
      (slide) => slide.id == updated.id,
    );
    if (index != null && index >= 0) {
      deckNotifier.updateSlide(index, updated);
      liveEdited = true;
    }
  }

  void sessionEdited(Slide updated) {
    final index = deckNotifier.currentState.deck?.slides.indexWhere(
      (slide) => slide.id == updated.id,
    );
    if (index == null || index < 0) return;
    final current = deckNotifier.currentState.deck!.slides[index];
    sessionOriginals.putIfAbsent(updated.id, () => current);
    deckNotifier.updateSlide(index, updated);
    liveEdited = true;
  }

  void slideSplit(String slideId) {
    final index = deckNotifier.currentState.deck?.slides.indexWhere(
      (slide) => slide.id == slideId,
    );
    if (index != null && index >= 0) {
      deckNotifier.splitSlide(index);
      liveEdited = true;
    }
  }
}

Future<void> _reportCoursePlayback(
  WidgetRef ref,
  LearningSessionRef session,
  PlaybackReport report,
  DateTime startedAt,
) async {
  try {
    await ref
        .read(ociServeProvider.notifier)
        .reportPlayback(session: session, report: report, startedAt: startedAt);
    unawaited(
      ref
          .read(ociServeProvider.notifier)
          .flushPendingReports()
          .catchError((_) {}),
    );
  } catch (error, stack) {
    logError('OciServe: voortgang bewaren', error.runtimeType, stack);
    // A failed sync stays in the encrypted outbox when it was queued.
    // Leaving playback must never trap the learner in the presenter.
  }
}

void presentDeck(
  BuildContext context,
  WidgetRef ref, {
  bool fromStart = false,
}) {
  final deckNotifier = ref.read(deckProvider.notifier);
  final editorNotifier = ref.read(editorProvider.notifier);
  final deck = ref.read(deckProvider).deck;
  if (deck == null) return;
  final l10n = context.l10n;
  // Overgeslagen slides weglaten en de selectie naar de eerstvolgende
  // zichtbare slide vertalen.
  final visible = _visiblePresentationIndexes(deck);
  final slides = _slidesForPresentationOrExport(deck);
  if (slides.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(emptyAudienceReason(l10n, deck, forExport: false)),
      ),
    );
    return;
  }
  final initial = _presentationStartIndex(ref, visible, fromStart: fromStart);
  final settings = ref.read(settingsProvider);
  final learningSession = ref.read(learningSessionProvider);
  final canPersistPresentationEdits = learningSession == null && !deck.playOnly;
  // Render-time pagination: a long finding presents as several full-size slides
  // (matching the export). Remap the start index into the expanded list. A
  // finding never fires onSlideChanged (only checklist/table live-edits do), so
  // the callback below still resolves page-slides to their deck slide by id.
  final renderSlides = expandFindingsForRender(
    slides,
    profile: deck.themeProfile,
  );
  final renderInitial = expandFindingsForRender(
    slides.sublist(0, initial),
    profile: deck.themeProfile,
  ).length.clamp(0, renderSlides.length - 1);
  // Live bewerkingen (tabelcellen, checklists) komen buiten de editorvelden om
  // binnen; die cachen hun tekst tot [DeckState.revision] verandert. Zonder de
  // verversing hieronder blijft de editor na afloop de oude tekst tonen — en
  // schrijft de eerstvolgende toetsaanslag daarin de live bewerking stil terug.
  final edits = _PresentationEdits(deckNotifier);
  // Een blijvende [MaterialBanner] of [SnackBar] hoort niet mee de zaal in. De
  // gedeelde ScaffoldMessenger verhuist die anders naar het Scaffold van de
  // zojuist geduwde presenter-route. Bij een snackbar kan dat bovendien twee
  // Hero's met dezelfde tag in één overgang opleveren. Verwijder beide meteen,
  // zonder uitanimatie, vóór de presenter-route wordt gemaakt.
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentMaterialBanner();
  messenger.removeCurrentSnackBar();
  final playbackStartedAt = DateTime.now().toUtc();
  var courseCompleted = false;
  final presenting = FullscreenPresenter.present(
    context,
    // De projectiegrens. Presenteren is het ontvangende oppervlak bij uitstek:
    // wat hier op het scherm komt, ziet de zaal.
    audienceDeck: PrivacyProjection.forAudience(
      deck.copyWith(slides: renderSlides),
      disabledRules: settings.privacyDisabledRules,
      regions: settings.privacyRegions,
      ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
    ),
    cockpitColorScheme: settings.cockpitColorScheme,
    initialIndex: renderInitial,
    showClassificationWatermark: settings.classificationWatermarkEnabled,
    allowRemoteMedia: settings.allowRemoteMedia,
    showRehearsalSummary: deck.showRehearsalSummary,
    playOnly: deck.playOnly || learningSession != null,
    onPlaybackFinished: learningSession == null
        ? null
        : (report) async {
            courseCompleted = report.completed;
            await _reportCoursePlayback(
              ref,
              learningSession,
              report,
              playbackStartedAt,
            );
          },
    targetDuration: () {
      final secs = deck.presentationTargetSeconds;
      return secs > 0 ? Duration(seconds: secs) : null;
    }(),
    annotations: deck.annotations,
    onAnnotationsChanged: canPersistPresentationEdits
        ? deckNotifier.setAnnotations
        : null,
    initialUserNotes: deck.userNotes,
    onUserNotesChanged: canPersistPresentationEdits
        ? deckNotifier.setUserNotes
        : null,
    onSlideChanged: canPersistPresentationEdits ? edits.slideChanged : null,
    onSessionEdit: canPersistPresentationEdits ? edits.sessionEdited : null,
    // Live-fix tijdens presenteren (#914): de presenter knipt een te volle dia
    // lokaal al op; hier wordt de knip op de bron doorgeschreven, op dezelfde
    // dia (via het id, net als onSlideChanged). Eén ongedaan-stap.
    onSlideSplit: canPersistPresentationEdits ? edits.slideSplit : null,
  );
  // Pas ná afloop verversen: tijdens het presenteren staat de editor toch
  // achter de presentatie, en per toetsaanslag verversen zou elke aanslag een
  // eigen ongedaan-stap maken (de coalescing in [updateSlide] hangt aan het
  // uitblijven van een revisiesprong).
  presenting.then((endSlideId) async {
    if (!context.mounted) return;
    await _afterPresentation(
      context,
      ref,
      endSlideId: endSlideId,
      liveEdited: edits.liveEdited,
      sessionOriginals: edits.sessionOriginals,
      deckNotifier: deckNotifier,
      editorNotifier: editorNotifier,
    );
    if (courseCompleted && context.mounted) {
      await _showCourseCompletion(context, ref);
    }
  });
}

/// Afloop na een presentatie: editor verversen, selectie volgen naar de
/// eind-dia, en session-data-edits aanbieden als losse bestanden (#1235).
/// Aparte functie zodat [presentDeck] onder de method-length-ratchet blijft.
Future<void> _afterPresentation(
  BuildContext context,
  WidgetRef ref, {
  required String? endSlideId,
  required bool liveEdited,
  required Map<String, Slide> sessionOriginals,
  required DeckNotifier deckNotifier,
  required EditorNotifier editorNotifier,
}) async {
  if (liveEdited) deckNotifier.refreshEditorFields();
  // De editor volgt de presenter naar de dia waar die stopte (#1111). De
  // presenter geeft het bron-dia-id terug (niet de render-index — findings
  // klappen uit tot meerdere render-pagina's met hetzelfde id); zoek dat id
  // terug in het actuele deck. Een tijdens het presenteren verwijderde dia is
  // niet meer te vinden (< 0) → laat de selectie dan staan.
  if (endSlideId != null) {
    final current = deckNotifier.currentState.deck;
    if (current != null) {
      final sourceIndex = current.slides.indexWhere((s) => s.id == endSlideId);
      if (sourceIndex >= 0) editorNotifier.select(sourceIndex);
    }
  }
  // Pas ná de editor-verversing en selectie: bied session-data-edits aan als
  // losse bestanden (#1235). Geen edits → geen dialoog.
  if (sessionOriginals.isNotEmpty && context.mounted) {
    await offerSessionExport(
      context,
      ref,
      deckNotifier: deckNotifier,
      sessionOriginals: sessionOriginals,
    );
  }
}

/// Rondt een OciServe-les zichtbaar af en brengt de cursist desgewenst terug
/// naar het cursusoverzicht. De serverrapportage is op dit punt al veilig in de
/// versleutelde wachtrij gezet; een trage verbinding houdt dit scherm dus niet
/// tegen.
Future<void> _showCourseCompletion(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  final palette = AppPalette.of(theme);
  final returnToCourses = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.emoji_events_outlined,
          size: 34,
          color: AppTheme.labelOn(theme.colorScheme.secondary),
        ),
      ),
      title: Text(l10n.d('Les afgerond')),
      content: Text(
        l10n.d('Mooi gedaan! Uw voortgang is bewaard.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.mutedText),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.d('Doorgaan in de les')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.school_outlined),
          label: Text(l10n.d('Terug naar mijn cursussen')),
        ),
      ],
    ),
  );
  if (returnToCourses != true || !context.mounted) return;

  final navigatorContext = Navigator.of(context, rootNavigator: true).context;
  final tabs = ref.read(tabsProvider);
  final index = tabs.clampedIndex;
  final learningTab = tabs.tabs[index];
  if (learningTab.learningSession == null) return;
  await requestCloseTab(context, ref, index);
  final originalTab = ref
      .read(tabsProvider)
      .tabs
      .where((tab) => tab.id == learningTab.id)
      .firstOrNull;
  if (!navigatorContext.mounted || originalTab?.isOpen == true) return;
  await OciServeCoursesDialog.show(navigatorContext);
}
