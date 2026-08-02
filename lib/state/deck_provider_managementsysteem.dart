part of 'deck_provider.dart';

/// Top-level deck action for the managementsysteem module: generating a
/// progress-overview slide from the `controlStatus` slides
/// (ISO_MANAGEMENTSYSTEEM §6). A top-level function in the same library rather
/// than an `extension on DeckNotifier`, so it keeps library-private access to
/// `_mutate` and the deck state without counting toward the notifier's
/// class-size ratchet.
///
/// Regenerate the management-system progress overview: a `table` slide with one
/// row per `controlStatus` section (applicable / implemented / % implemented)
/// plus a totals row. Derived from the deck, so it is always consistent with
/// the detail slides.
///
/// Idempotent: an existing overview (a `table` slide whose title equals
/// [overviewTitle]) is refreshed in place; otherwise a new one is appended.
/// Returns 0 when the deck has no `controlStatus` slides to summarise. The
/// visible strings are passed in so this stays Flutter-free and localises at
/// the call site.
int generateManagementSystemOverview(
  DeckNotifier notifier, {
  required String overviewTitle,
  required String sectionHeader,
  required String applicableHeader,
  required String implementedHeader,
  required String progressHeader,
  required String totalLabel,
}) {
  final deck = notifier.currentState.deck;
  if (deck == null) return 0;
  final progress = deckManagementSystemProgress(deck);
  if (progress.isEmpty) return 0;

  final rows = <List<String>>[
    [sectionHeader, applicableHeader, implementedHeader, progressHeader],
    for (final s in progress.sections)
      [
        s.heading,
        '${s.applicable}',
        '${s.implemented}',
        '${s.progressPercent}%',
      ],
    [
      totalLabel,
      '${progress.applicable}',
      '${progress.implemented}',
      '${progress.progressPercent}%',
    ],
  ];

  final overview = Slide.create(
    SlideType.table,
  ).copyWith(title: overviewTitle, tableRows: rows);

  final slides = List<Slide>.from(deck.slides);
  final existing = slides.indexWhere(
    (s) => s.type == SlideType.table && s.title == overviewTitle,
  );
  if (existing >= 0) {
    // Refresh in place, keeping the slide's position and id.
    slides[existing] = slides[existing].copyWith(
      title: overviewTitle,
      tableRows: rows,
    );
  } else {
    slides.add(overview);
  }
  notifier._mutate(deck.copyWith(slides: slides), bumpRevision: true);
  return 1;
}

/// Regenerate the **burn-up chart**: a horizontal stacked-bar `chart` slide,
/// implemented (green) vs remaining (grey) per `controlStatus` section, derived
/// from the deck (ISO_MANAGEMENTSYSTEEM §6). A companion to the overview table —
/// the "Genereer voortgangsoverzicht"-actie draws both.
///
/// Idempotent: a `chart` slide whose spec title equals [chartTitle] is refreshed
/// in place (the title round-trips inside the chart block, unlike `Slide.title`);
/// otherwise a new one is appended. Returns 0 when there is nothing to plot.
int generateManagementSystemChart(
  DeckNotifier notifier, {
  required String chartTitle,
  required String implementedLabel,
  required String remainingLabel,
}) {
  final deck = notifier.currentState.deck;
  if (deck == null) return 0;
  final progress = deckManagementSystemProgress(deck);
  if (progress.isEmpty) return 0;
  final block = buildManagementSystemProgressChart(
    progress,
    chartTitle: chartTitle,
    implementedLabel: implementedLabel,
    remainingLabel: remainingLabel,
  ).toBlock();

  final slides = List<Slide>.from(deck.slides);
  final existing = slides.indexWhere(
    (s) =>
        s.type == SlideType.chart &&
        ChartSpec.parse(s.customMarkdown).title == chartTitle,
  );
  if (existing >= 0) {
    slides[existing] = slides[existing].copyWith(customMarkdown: block);
  } else {
    slides.add(
      Slide.create(SlideType.chart).copyWith(customMarkdown: block),
    );
  }
  notifier._mutate(deck.copyWith(slides: slides), bumpRevision: true);
  return 1;
}

/// Invisible marker on the first management-review slide, so re-running the
/// action never appends a second copy over the author's answers. A private-use
/// HTML comment: Marp ignores it and it round-trips through `freeMarkdown`.
const kManagementReviewMarker = '<!-- ocideck_ms_review -->';

/// Append the ISO 9.3 **management-review** template: two `freeMarkdown` slides
/// (inputs 9.3.2 and outputs 9.3.3), pre-filled with the current progress
/// figures (ISO_MANAGEMENTSYSTEEM §4). Unlike the derived overview this is a
/// *template to fill in*, so it appends once and refuses to duplicate — the
/// marker guard protects the author's answers on a re-run.
///
/// [inputBody] may carry `{p}`, `{impl}` and `{app}` placeholders, filled from
/// the deck's derived progress. Returns 2 (slides added), or 0 when a review is
/// already present. Visible strings are passed in so this stays Flutter-free.
int generateManagementReview(
  DeckNotifier notifier, {
  required String inputTitle,
  required String inputBody,
  required String outputTitle,
  required String outputBody,
}) {
  final deck = notifier.currentState.deck;
  if (deck == null) return 0;
  final already = deck.slides.any(
    (s) =>
        s.type == SlideType.freeMarkdown &&
        s.customMarkdown.contains(kManagementReviewMarker),
  );
  if (already) return 0;

  final progress = deckManagementSystemProgress(deck);
  String fill(String s) => s
      .replaceAll('{p}', '${progress.progressPercent}')
      .replaceAll('{impl}', '${progress.implemented}')
      .replaceAll('{app}', '${progress.applicable}');

  final inputMd = '$kManagementReviewMarker\n# $inputTitle\n\n${fill(inputBody)}\n';
  final outputMd = '# $outputTitle\n\n${fill(outputBody)}\n';
  final slides = List<Slide>.from(deck.slides)
    ..add(Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: inputMd))
    ..add(
      Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: outputMd),
    );
  notifier._mutate(deck.copyWith(slides: slides), bumpRevision: true);
  return 2;
}
