// Het lexiconmodel: één trefwoord, met alles wat de scanner erover moet weten.
//
// Tot fase 12 was een trefwoord een kale string in een lijst, en werd al het
// andere eruit afgeleid. Vooral de matchmodus: die volgde uit de lengte van de
// term, met vier tekens als grens. Dat werkte verrassend ver — korte termen zijn
// meestal acroniemen (`vog`, `hiv`, `ggz`) die als heel woord moeten matchen, en
// lange termen zijn meestal Nederlandse zelfstandige naamwoorden waar een vrij
// achtervoegsel bij hoort.
//
// Maar "meestal" is precies het probleem, en de uitzonderingen zijn niet zeldzaam:
//
//   * `arrest` is zes letters en moet tóch als heel woord matchen, anders vindt
//     hij `arrestatieteam` — wat klopt — maar ook elke samenstelling die er niet
//     toe doet;
//   * `ziekteverzuim` is Nederlands en zou juist als deel van een samenstelling
//     gevonden moeten worden (`ziekteverzuimcijfers`);
//   * een Engelse term hoort géén Nederlandse voorvoegselregel te krijgen: de
//     morfologie van het Engels is niet suffigerend op dezelfde manier.
//
// Zodra de bron van de termen niet meer een handgeschreven lijst is maar een
// gegenereerde ontologie (fase 13: EuroVoc, ORDO), houdt afleiden helemaal op te
// werken — dan moet de generator de modus meegeven, want alleen die weet wat voor
// soort term het is. Vandaar dit model.

/// Hoe een term in de tekst gezocht wordt.
enum PrivacyTermMatch {
  /// Alleen als héél woord, met een grens aan beide kanten.
  ///
  /// Voor acroniemen en voor woorden die als deel van een ander woord niets
  /// betekenen. `vog` vindt zo de VOG en niet de vogels — geen hypothetisch
  /// voorbeeld, dat deed de oude matcher werkelijk.
  word,

  /// Op woordbegin, met een vrij achtervoegsel.
  ///
  /// De juiste standaard voor het Nederlands: de morfologie is vrijwel volledig
  /// suffigerend, dus `verdacht` dekt `verdachte`, `verdachten` en
  /// `verdachtmaking` zonder dat die drie in de lijst hoeven.
  prefix,

  /// Overal binnen een woord, ook middenin een samenstelling.
  ///
  /// Nodig voor het Nederlands, Duits, Zweeds, Deens en Fins, waar
  /// samenstellingen aan elkaar geschreven worden: `ziekteverzuimcijfers` bevat
  /// `ziekteverzuim`, en geen woordgrens ter wereld ziet dat. Alleen voor termen
  /// die lang en specifiek genoeg zijn dat een toevallige treffer niet bestaat —
  /// zie [minCompoundLength].
  compound,
}

/// Of de tekst zélf het gegeven is, of alleen een aanwijzing dat er een in de
/// buurt staat.
///
/// Zie `PrivacyTermRole` in `privacy_finding.dart` voor waarom dit onderscheid
/// bepaalt hoevéél er bij redactie weggaat. Hier is het lexicondata in plaats van
/// een aanname per familie, want binnen één familie komen beide voor: "diagnose"
/// wijst, `F32.1` ís.
enum PrivacyLexiconRole { indicator, value }

/// Waar een entry vandaan komt.
enum PrivacyLexiconSource {
  /// Met de app meegeleverd.
  bundled,

  /// Door de gebruiker of de organisatie toegevoegd (§7 `privacyCustomRules`).
  user,
}

/// Onder deze lengte mag een term nooit als samenstellingsdeel matchen.
///
/// Korte fragmenten zitten in te veel woorden. `arts` in `kaarts`, `hiv` in
/// `hivernale` — de winst van decompounding verdampt volledig als je hem op
/// korte termen loslaat.
const int kMinCompoundLength = 8;

/// Eén term in het lexicon.
class PrivacyLexiconEntry {
  /// De te zoeken string, in kleine letters.
  final String term;

  /// De regel waaronder een treffer gemeld wordt: `special.health`,
  /// `special.criminal`, …
  final String category;

  /// Wijst deze term naar het gegeven, of ís hij het?
  final PrivacyLexiconRole role;

  /// De taalcode (`nl`, `en`, `de`, `fr`, `es`, …).
  ///
  /// Draagt de taaldekkingsmeter van fase 13: zonder dit veld kan het paneel niet
  /// zeggen dát er voor een taal geen lexicon is, en dan liegt een groene balk in
  /// 24 talen.
  final String lang;

  /// Hoe er gezocht wordt.
  final PrivacyTermMatch match;

  /// Specificiteit, 1 (zeer algemeen) tot 5 (praktisch uniek).
  ///
  /// `griep` heeft tien homoniemen en betekenissen; `syndroom van Down` heeft er
  /// geen. Die twee horen niet even zwaar te wegen, en het gewicht beslist welke
  /// term de melding draagt als er meerdere in hetzelfde fragment staan: de
  /// meest specifieke, niet de eerste in de lijst.
  final int weight;

  final PrivacyLexiconSource source;

  const PrivacyLexiconEntry({
    required this.term,
    required this.category,
    required this.lang,
    this.role = PrivacyLexiconRole.indicator,
    this.match = PrivacyTermMatch.prefix,
    this.weight = 3,
    this.source = PrivacyLexiconSource.bundled,
  });

  /// De modus waarin deze term werkelijk gezocht wordt.
  ///
  /// [PrivacyTermMatch.compound] valt terug op [PrivacyTermMatch.prefix] zodra de
  /// term te kort is om veilig middenin een woord te matchen. De entry mag dus
  /// optimistisch `compound` declareren; deze poort houdt de ruis buiten.
  PrivacyTermMatch get effectiveMatch =>
      match == PrivacyTermMatch.compound && term.length < kMinCompoundLength
      ? PrivacyTermMatch.prefix
      : match;
}
