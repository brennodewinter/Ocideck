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
  final visible = <int>[
    for (var i = 0; i < deck.slides.length; i++)
      if (slideReachesAudience(
        deck.slides[i],
        presentationTlp: deck.tlp,
        includeDetail: true,
      ))
        i,
  ];
  final slides = _slidesForPresentationOrExport(deck);
  if (slides.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(emptyAudienceReason(l10n, deck, forExport: false)),
      ),
    );
    return;
  }
  int initial;
  if (fromStart) {
    initial = 0;
  } else {
    final selectedIndex = ref.read(editorProvider).selectedIndex;
    initial = visible.indexWhere((i) => i >= selectedIndex);
    if (initial < 0) initial = visible.length - 1;
    if (initial < 0) initial = 0;
  }
  final settings = ref.read(settingsProvider);
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
  var liveEdited = false;
  // Een blijvende [MaterialBanner] of [SnackBar] hoort niet mee de zaal in. De
  // gedeelde ScaffoldMessenger verhuist die anders naar het Scaffold van de
  // zojuist geduwde presenter-route. Bij een snackbar kan dat bovendien twee
  // Hero's met dezelfde tag in één overgang opleveren. Verwijder beide meteen,
  // zonder uitanimatie, vóór de presenter-route wordt gemaakt.
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentMaterialBanner();
  messenger.removeCurrentSnackBar();
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
    playOnly: deck.playOnly,
    targetDuration: () {
      final secs = deck.presentationTargetSeconds;
      return secs > 0 ? Duration(seconds: secs) : null;
    }(),
    annotations: deck.annotations,
    onAnnotationsChanged: deckNotifier.setAnnotations,
    initialUserNotes: deck.userNotes,
    onUserNotesChanged: deckNotifier.setUserNotes,
    onSlideChanged: (updated) {
      final index = deckNotifier.currentState.deck?.slides.indexWhere(
        (slide) => slide.id == updated.id,
      );
      if (index != null && index >= 0) {
        deckNotifier.updateSlide(index, updated);
        liveEdited = true;
      }
    },
    // Live-fix tijdens presenteren (#914): de presenter knipt een te volle dia
    // lokaal al op; hier wordt de knip op de bron doorgeschreven, op dezelfde
    // dia (via het id, net als onSlideChanged). Eén ongedaan-stap.
    onSlideSplit: (slideId) {
      final index = deckNotifier.currentState.deck?.slides.indexWhere(
        (slide) => slide.id == slideId,
      );
      if (index != null && index >= 0) {
        deckNotifier.splitSlide(index);
        liveEdited = true;
      }
    },
  );
  // Pas ná afloop verversen: tijdens het presenteren staat de editor toch
  // achter de presentatie, en per toetsaanslag verversen zou elke aanslag een
  // eigen ongedaan-stap maken (de coalescing in [updateSlide] hangt aan het
  // uitblijven van een revisiesprong).
  presenting.then((endSlideId) {
    if (liveEdited) deckNotifier.refreshEditorFields();
    // De editor volgt de presenter naar de dia waar die stopte (#1111). De
    // presenter geeft het bron-dia-id terug (niet de render-index — findings
    // klappen uit tot meerdere render-pagina's met hetzelfde id); zoek dat id
    // terug in het actuele deck. Een tijdens het presenteren verwijderde dia is
    // niet meer te vinden (< 0) → laat de selectie dan staan.
    if (endSlideId == null) return;
    final current = deckNotifier.currentState.deck;
    if (current == null) return;
    final sourceIndex = current.slides.indexWhere((s) => s.id == endSlideId);
    if (sourceIndex >= 0) editorNotifier.select(sourceIndex);
  });
}
