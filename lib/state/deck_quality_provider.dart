import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/deck.dart';
import '../models/slide_quality.dart';
import '../services/slide_quality_analyzer.dart';
import 'deck_provider.dart';

final slideQualityAnalyzerProvider = Provider<SlideQualityAnalyzer>(
  (_) => const SlideQualityAnalyzer(),
);

final deckQualityProvider =
    StateNotifierProvider<DeckQualityNotifier, SlideQualityResult>((ref) {
      return DeckQualityNotifier(ref);
    });

class DeckQualityNotifier extends StateNotifier<SlideQualityResult> {
  DeckQualityNotifier(this._ref) : super(const SlideQualityResult([])) {
    _schedule(_ref.read(deckProvider).deck, immediate: true);
    _ref.listen<DeckState>(deckProvider, (_, next) => _schedule(next.deck));
  }

  final Ref _ref;
  Timer? _debounce;

  void _schedule(Deck? deck, {bool immediate = false}) {
    _debounce?.cancel();
    if (deck == null) {
      state = const SlideQualityResult([]);
      return;
    }
    if (immediate) {
      state = _ref.read(slideQualityAnalyzerProvider).analyze(deck);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final current = _ref.read(deckProvider).deck;
      if (current == null) {
        state = const SlideQualityResult([]);
        return;
      }
      state = _ref.read(slideQualityAnalyzerProvider).analyze(current);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
