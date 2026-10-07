part of 'deck_provider.dart';

void _loadDeck(
  DeckNotifier notifier,
  Deck deck, {
  String? filePath,
  String? remoteOrigin,
  required bool isDirty,
  required bool preserveThemeProfile,
}) {
  final resolvedDeck = preserveThemeProfile
      ? deck
      : deck.copyWith(
          themeProfile: notifier._file.activeProfileFor(
            projectPath: deck.projectPath,
          ),
        );
  notifier._clearHistory();
  notifier._replacementState = DeckState(
    deck: resolvedDeck,
    filePath: filePath,
    remoteOrigin: remoteOrigin,
    isDirty: isDirty,
  );
  // De mtime is pas bij een volgende opslag nodig en hoeft het openen daarom
  // niet op te houden.
  if (filePath != null) {
    unawaited(notifier._localMerge.recordMtime());
  }
  // Alleen een schone lading vanaf een pad is een aantoonbare basis voor de
  // driewegs-merge (#2323); een vuil hersteld tabblad wijkt mogelijk al af.
  notifier._localMerge.base = !isDirty && filePath != null
      ? resolvedDeck
      : null;
}
