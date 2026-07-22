part of 'deck_provider.dart';

/// `part of` extension for the automation actions (P2-AUTO §10), keeping the
/// main notifier under the line limit; as an extension in the same library it
/// keeps access to `_mutate` and the deck state.
extension DeckNotifierAuto on DeckNotifier {
  /// Renumber every finding (`F-01`, `F-02`, … in deck order) in one undoable
  /// step, rewriting each group's shared id and its heading prefix
  /// (PENTEST_MIAUW §10.1). No-op on a finalised (sealed) deck. Returns how many
  /// findings were numbered.
  int autoRenumberFindings() => _renumber(this);

  /// Store the imported RFC 3161 timestamp token (base64url of the `.tsr`) on the
  /// sealed deck (PENTEST_MIAUW §8-A2). Allowed on a finalised deck because the
  /// token lives outside the hashed content. Ignored when the deck is unsealed.
  ///
  /// Wist meteen de nonce: die hoort bij het vérzoek, dus zodra het antwoord er
  /// is staat er niets meer uit. Laten staan zou hem bij een volgend verzoek
  /// laten meekijken met een echo die er niet bij hoort.
  void setSealTimestampToken(String base64Token) => _mutateSeal(
    this,
    (d) => d.copyWith(sealTimestampToken: base64Token, sealTimestampNonce: ''),
  );

  /// De nonce van het zojuist geëxporteerde verzoek; zie
  /// [Deck.sealTimestampNonce] voor waarom hij bewaard wordt.
  void setSealTimestampNonce(String nonceHex) =>
      _mutateSeal(this, (d) => d.copyWith(sealTimestampNonce: nonceHex));
}

/// Zegelvelden bijwerken op een deck dat er al één heeft. Zonder zegelhash valt
/// er niets te stempelen, en dan is dit een no-op.
///
/// Top-level en geen methode: hij raakt alleen [n], en `DeckNotifier` zit tegen
/// zijn plafond — gedrag dat geen veld van de klasse nodig heeft, hoort er ook
/// niet in te tellen.
void _mutateSeal(DeckNotifier n, Deck Function(Deck) change) {
  final deck = n.currentState.deck;
  if (deck == null || deck.sealHash.isEmpty) return;
  n._mutate(change(deck), allowFinalized: true);
}

/// Zie [DeckNotifierAuto.autoRenumberFindings]. Zelfde reden als [_mutateSeal]
/// om buiten de klasse te staan: hij raakt geen enkel veld van [n].
int _renumber(DeckNotifier n) {
  final deck = n.currentState.deck;
  if (deck == null) return 0;
  final renumbered = renumberFindings(deck);
  final count = deckFindingList(renumbered).length;
  if (count > 0) n._mutate(renumbered, bumpRevision: true);
  return count;
}
