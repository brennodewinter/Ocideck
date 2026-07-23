part of 'deck_provider.dart';

/// `part of` extension for the MIAUW compliance waivers (P2-COMP §9), keeping
/// the main notifier under the line limit; as an extension in the same library
/// it keeps access to `_mutate` and the deck state.
extension DeckNotifierMiauw on DeckNotifier {
  /// Exclude EIS [eisId] from the compliance overview with a mandatory [reason].
  /// An empty reason is ignored — a waiver must always be justified.
  void setMiauwWaiver(String eisId, String reason) =>
      _setMiauwEntry(this, _MiauwMap.waivers, eisId, reason);

  /// Lift the exclusion on EIS [eisId], returning it to its automatic/manual
  /// status.
  void removeMiauwWaiver(String eisId) =>
      _setMiauwEntry(this, _MiauwMap.waivers, eisId, null);

  /// Manually confirm EIS [eisId] with a mandatory [note] (the human
  /// attestation). An empty note is ignored — a confirmation must be justified,
  /// just like a waiver. The requirement then reads as voldaan (handmatig).
  void setMiauwConfirmation(String eisId, String note) =>
      _setMiauwEntry(this, _MiauwMap.confirmations, eisId, note);

  /// Withdraw the manual confirmation on EIS [eisId], returning it to open.
  void removeMiauwConfirmation(String eisId) =>
      _setMiauwEntry(this, _MiauwMap.confirmations, eisId, null);
}

/// Welke van de twee MIAUW-mappen op het deck geraakt wordt.
enum _MiauwMap { waivers, confirmations }

/// Zet [eisId] op [value] in de gekozen MIAUW-map, of haalt hem eruit wanneer
/// [value] null is.
///
/// Top-level en geen methode: het raakt geen enkel veld van [DeckNotifier], en
/// die klasse zit tegen zijn plafond (#630). De vier publieke methodes hierboven
/// deden alle vier hetzelfde — map kopiëren, één sleutel wijzigen, vastleggen —
/// en dat vier keer uitschrijven was de reden dat dit bestand zo groot was.
///
/// **Een lege waarde telt als afwezig.** Een uitsluiting of een handmatige
/// bevestiging zonder motivering hoort niet vastgelegd te worden: het verschil
/// tussen "hier is over nagedacht" en "hier is op geklikt" is precies wat een
/// auditor uit dit veld wil lezen.
void _setMiauwEntry(
  DeckNotifier n,
  _MiauwMap which,
  String eisId,
  String? value,
) {
  final deck = n.currentState.deck;
  if (deck == null) return;
  final trimmed = value?.trim();
  if (value != null && (trimmed == null || trimmed.isEmpty)) return;

  final isWaiver = which == _MiauwMap.waivers;
  final source = isWaiver ? deck.miauwWaivers : deck.miauwConfirmations;
  if (trimmed == null && !source.containsKey(eisId)) return;

  // Het moment van dít besluit: de merge in een git-repository laat per
  // EIS-id het laatste besluit winnen, en intrekken laat een grafsteen achter
  // zodat het de samenvoeging overleeft (GIT_STORAGE §9.7).
  n._mutate(
    deck.copyWith(
      miauw: deck.miauw.withEntry(
        isWaiver: isWaiver,
        eisId: eisId,
        text: trimmed,
        at: DateTime.now().toUtc().toIso8601String(),
      ),
    ),
  );
}
