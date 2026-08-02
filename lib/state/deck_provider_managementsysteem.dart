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
