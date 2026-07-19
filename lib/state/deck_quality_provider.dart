import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/deck.dart';
import '../models/quality_disposition.dart';
import '../models/slide_quality.dart';
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
  return ref.watch(slideQualityAnalyzerProvider).analyze(deck);
}

SlideQualityResult computeDeckQuality(Ref ref) {
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return const SlideQualityResult([]);
  return SlideQualityResult([
    for (final issue in ref.watch(deckQualityRawProvider).issues)
      if (!isQualityAccepted(deck, issue.slideIndex)) issue,
  ]);
}

/// Of de auteur de meldingen van slide [slideIndex] heeft geaccepteerd.
///
/// Een deckbrede melding (het thema) hoort bij geen enkele slide en is dus nooit
/// geaccepteerd: die zet je recht in de instellingen, niet op een slide.
bool isQualityAccepted(Deck deck, int slideIndex) {
  if (slideIndex < 0 || slideIndex >= deck.slides.length) return false;
  return deck.slides[slideIndex].quality.isResolved;
}
