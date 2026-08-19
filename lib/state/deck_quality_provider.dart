import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/deck.dart';
import '../models/quality_disposition.dart';
import '../models/slide_quality.dart';
import '../services/slide_quality/split_run_density_summary.dart';
import '../services/slide_quality_analyzer.dart';
import 'deck_provider.dart';
import 'settings_provider.dart';

final slideQualityAnalyzerProvider = Provider<SlideQualityAnalyzer>(
  (ref) => SlideQualityAnalyzer(
    minContrastRatio: ref.watch(
      settingsProvider.select((s) => s.contrastMinRatio),
    ),
  ),
);

/// De ruwe analyse: álle meldingen, óók die op een slide die de auteur al heeft
/// geaccepteerd.
///
/// Bestaat om dezelfde reden als `privacyRawScanProvider`: een badge die wil
/// laten zien dát er ooit iets gevonden is, en een popover die het wil laten
/// lézen, hebben de afgehandelde meldingen nodig. Een lijst waaruit ze al
/// verdwenen zijn kan het verschil tussen "niets gevonden" en "alles
/// afgehandeld" niet meer maken — en dat verschil is nu juist wat de gebruiker
/// wil zien.
final deckQualityRawProvider = Provider<SlideQualityResult>(
  computeDeckQualityRaw,
);

/// De analyse zonder de meldingen die al zijn afgehandeld.
///
/// Dit is wat het paneel toont en waar de export-gate op telt: het open werk.
/// Blijven zeuren over een beslissing die al genomen is leert de gebruiker
/// precies één ding, namelijk dat hij deze meldingen kan negeren — en daarna
/// negeert hij ook de terechte.
final deckQualityProvider = Provider<SlideQualityResult>(computeDeckQuality);

/// Top-level, zodat `AppShell` dezelfde berekening per tab kan overriden.
///
/// Niet inline in de override herhalen: dat is precies hoe deze filter er bijna
/// naast viel te liggen. Een override die de berekening kopieert loopt bij de
/// eerste wijziging uit de pas met het origineel, en de tabversie — de enige die
/// de gebruiker ooit ziet — is dan de verouderde.
SlideQualityResult computeDeckQualityRaw(Ref ref) {
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return const SlideQualityResult([]);
  final result = ref.watch(slideQualityAnalyzerProvider).analyze(deck);
  if (!ref.watch(deckProvider.select(isUntouchedDeck))) return result;
  return SlideQualityResult([
    for (final issue in result.issues)
      if (issue.kind != SlideQualityIssueKind.emptySlide) issue,
  ]);
}

/// Heeft de gebruiker dit deck nog met geen vinger aangeraakt?
///
/// Waar dan ook: net aangemaakt (geen ongedaan-maken-stap in de geschiedenis),
/// nog nooit naar een bestand geschreven, en op web ook niet gedownload.
///
/// Voor zo'n deck zwijgt de lege-dia-melding. 'Leeg deck' geeft precies wat de
/// kiezer belooft — één lege dia — en die dan meteen als probleem aanwijzen is
/// de gebruiker corrigeren voor wat hij zelf net vroeg. Eén toetsaanslag zet
/// een ongedaan-maken-stap, dus zodra hij ook maar iets doet telt de melding
/// weer mee; en dat is precies het moment waarop een lege dia wél iets is om
/// te weten vóór de export. De andere meldingen blijven staan: die gaan over
/// wat er wél is (contrast, dichtheid, een onbeantwoordbare vraag) en zijn dus
/// nooit een verwijt over iets wat de gebruiker nog moet doen.
bool isUntouchedDeck(DeckState state) =>
    !state.canUndo && state.filePath == null && state.downloadName == null;

SlideQualityResult computeDeckQuality(Ref ref) {
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return const SlideQualityResult([]);
  final open = [
    for (final issue in ref.watch(deckQualityRawProvider).issues)
      if (!isQualityAccepted(deck, issue.slideIndex)) issue,
  ];
  // Vat de lengte-gedreven dichtheidsmeldingen die na 'Splits slide' op elke
  // deelpagina terugkeren samen tot één per soort per gesplitste reeks (#1289):
  // splitsen lost de dichtheid-per-aantal op, niet de lengte-per-bullet, dus
  // hetzelfde lange-bullets-probleem hoort één keer geteld, niet per pagina.
  // Presentatie-laag — de ruwe provider en de fix-motor houden elke pagina
  // apart, zodat 'los automatisch op wat kan' de grondwaarheid blijft zien.
  return SlideQualityResult(collapseSplitRunDensity(deck.slides, open));
}

/// Of de auteur de meldingen van slide [slideIndex] heeft geaccepteerd.
///
/// Een deckbrede melding (het thema) hoort bij geen enkele slide en is dus nooit
/// geaccepteerd: die zet je recht in de instellingen, niet op een slide.
bool isQualityAccepted(Deck deck, int slideIndex) {
  if (slideIndex < 0 || slideIndex >= deck.slides.length) return false;
  return deck.slides[slideIndex].quality.isResolved;
}
