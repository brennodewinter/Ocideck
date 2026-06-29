import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final deckQualityProvider = Provider<SlideQualityResult>((ref) {
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return const SlideQualityResult([]);
  return ref.watch(slideQualityAnalyzerProvider).analyze(deck);
});
