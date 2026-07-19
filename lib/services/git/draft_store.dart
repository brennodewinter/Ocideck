import 'dart:typed_data';

/// De opslaglaag onder [DraftMirror]. Gescheiden om dezelfde reden als het
/// transport: desktop en web hebben er fundamenteel andere middelen voor.
abstract class DraftStore {
  Future<void> writeDeck(String deckDir, Map<String, Uint8List> files);
  Future<Map<String, Uint8List>> readDeck(String deckDir);
  Future<bool> hasDeck(String deckDir);
  Future<void> discardDeck(String deckDir);
  Future<List<String>> deckDirs();

  /// Neem een werkkopie over uit de tijd dat die nog niet per repository was
  /// gescheiden. Levert het aantal overgenomen decks. Idempotent, en een no-op
  /// zonder scope.
  ///
  /// Alleen aan te roepen voor de repo die tóén was ingesteld: er was er maar
  /// één, dus die is de enige rechthebbende. Het alternatief — laten liggen —
  /// maakt nog niet gepusht werk stil onbereikbaar.
  Future<int> adoptLegacyEntries();

  /// Overleeft wat hier geschreven wordt het afsluiten van de app?
  ///
  /// Dit is geen detail maar de kern van P2. Een store die dit onwaar meldt mag
  /// niet als "opgeslagen" worden gepresenteerd.
  bool get isDurable;
}

/// Gegooid wanneer de werkkopie op dit platform niet bestaat.
class DraftStoreUnsupported implements Exception {
  final String message;
  const DraftStoreUnsupported(this.message);

  @override
  String toString() => 'DraftStoreUnsupported: $message';
}
