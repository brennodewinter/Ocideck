import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/miauw_compliance.dart';
import '../services/miauw_compliance_analyzer.dart';
import 'deck_provider.dart';

/// The (stateless) analyzer instance.
final miauwComplianceAnalyzerProvider = Provider<MiauwComplianceAnalyzer>(
  (ref) => const MiauwComplianceAnalyzer(),
);

/// The MIAUW compliance overview for the active deck (PENTEST_MIAUW §9).
/// Mirrors `deckQualityProvider`: a plain synchronous [Provider] that recomputes
/// whenever the deck (its slides or its waivers) changes. Empty when no deck is
/// open.
final miauwComplianceProvider = Provider<MiauwComplianceResult>((ref) {
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return const MiauwComplianceResult([]);
  return ref.watch(miauwComplianceAnalyzerProvider).analyze(deck);
});
