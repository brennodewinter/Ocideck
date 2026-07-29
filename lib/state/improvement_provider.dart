import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/slide_quality.dart';
import '../services/improvement/improvement_quality_bridge.dart';
import 'deck_provider.dart';
import 'procesverbetering_provider.dart';

/// Golden-thread kwaliteitsmeldingen wanneer het deck of de module
/// procesverbetering actief is.
List<SlideQualityIssue> computeImprovementQualityIssues(Ref ref) {
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return const [];

  final moduleOn = ref.watch(procesverbeteringEnabledProvider);
  if (!moduleOn && !deck.hasImprovementSlides) return const [];

  return improvementIssuesFrom(deck);
}

final improvementQualityIssuesProvider = Provider<List<SlideQualityIssue>>(
  computeImprovementQualityIssues,
);
