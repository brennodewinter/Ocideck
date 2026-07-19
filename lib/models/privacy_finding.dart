// Het bevindingenmodel van de privacycontrole.
//
// Eén ding is hier bewust anders dan je zou verwachten: een bevinding bewaart de
// gevonden waarde NIET. Een privacycontrole die de gevonden BSN's in een lijstje
// in het geheugen zet, in een log schrijft of in een melding toont, heeft het
// probleem verplaatst in plaats van opgelost. Wat er wél in zit is een gemaskeerd
// fragment, genoeg om de gebruiker te laten zien wélke treffer bedoeld wordt.

/// Waar een bevinding toe behoort. Bepaalt de familieschakelaar in de
/// instellingen en het icoon in het paneel.
enum PrivacyFamily {
  /// Direct identificerend nummer: BSN, paspoortnummer, nationale ID.
  identifier,

  /// Financieel: IBAN, creditcard, crypto-adres.
  financial,

  /// Contact en locatie: e-mail, telefoon, adres, geboortedatum.
  contact,

  /// Digitale identificatoren: IP, MAC, IMEI, device-ID.
  digital,

  /// Credentials: API-sleutels, tokens, private keys, wachtwoorden.
  secret,

  /// Bijzondere persoonsgegevens (AVG art. 9/10).
  specialCategory,

  /// Massa-persoonsgegevens: een tabelkolom, een geplakte ledenlijst.
  bulk,

  /// Lek via metadata, paden, URL's — de verstopplekken in markdown.
  structural,
}

/// Hoe zeker we zijn dat dit werkelijk een persoonsgegeven is.
///
/// Dit is geen kosmetische schaal maar de kern van de vals-positieven-strategie:
/// alleen [certain] mag de gebruiker onderbreken. De rest informeert.
enum PrivacyConfidence {
  /// Checksum- of structureel gevalideerd, en niet op de nepwaardelijst. Een
  /// IBAN die mod-97 haalt met de juiste landlengte is geen ordernummer.
  certain,

  /// Sterk formaat zonder checksum, of een checksum met een zwak formaat.
  likely,

  /// Context- of woordgedreven. Hier zitten de vals-positieven, dus hier hoort
  /// een melding informatief te blijven.
  possible,
}

/// Of de gevonden tekst zélf het persoonsgegeven is, of alleen een aanwijzing
/// dat er een in de buurt staat.
///
/// Dit onderscheid bepaalt wat er bij redactie weggaat, en het is de reden dat
/// deze enum bestaat. "Diagnose" is geen gezondheidsgegeven — het is een woord
/// dat zegt dat er over gezondheid gesproken wordt. Dat weglakken levert dit op:
///
///     Jan had een ████████ bij de huisarts
///
/// Er is niets verborgen, "Jan" staat er nog, en de ontvanger denkt ten onrechte
/// dat daar iets gevoeligs stond. `F32.1`, `diabetes` of een parketnummer zijn
/// wél het gegeven zelf; die horen wél weg.
///
/// De Autoriteit Persoonsgegevens hanteert precies dit onderscheid: *"Gegevens
/// die hooguit een indicatie geven dat het om een gevoelig kenmerk zou kunnen
/// gaan, zijn niet voldoende"* om van een rechtstreeks verband te spreken
/// (onderzoek kinderopvangtoeslag, §3.3.1).
enum PrivacyTermRole {
  /// Een signaalwoord. Meldt wel, redigeert niet — tenzij de escalator het
  /// bereik heeft verbreed tot de hele mededeling, want dán gaat het niet meer
  /// om het woord maar om de uitspraak eromheen.
  indicator,

  /// De tekst is zelf het gegeven. Redigeren haalt werkelijk iets weg.
  value,
}

/// Eén treffer, op één plek in één slide.
class PrivacyFinding {
  /// De regel die vuurde, bijvoorbeeld `nl.bsn` of `fin.iban`. Stabiel: de
  /// gebruiker kan hierop een regel uitzetten, en het reist mee in de
  /// ignore-lijst van een deck.
  final String ruleId;

  final PrivacyFamily family;
  final PrivacyConfidence confidence;

  /// Index van de slide, of [kDeckWidePrivacyIndex] voor een deckbrede treffer
  /// (frontmatter, bestandsnaam).
  final int slideIndex;

  /// Het slideveld waarin de treffer zit (`title`, `bullets`, `notes`, …). Voert
  /// de navigatie: klik op de melding en het juiste editorveld krijgt focus.
  final String field;

  /// Bij een veld dat uit meerdere stukken bestaat (bullets, tabelcellen):
  /// welk stuk. 0 voor een enkelvoudig veld.
  final int fragmentIndex;

  /// Positie van de treffer binnen dat tekstfragment.
  final int start;
  final int end;

  /// Een gemaskeerd fragment van de treffer, bedoeld om te tónen — nooit de
  /// volledige waarde. Zie [maskValue].
  final String maskedSample;

  /// Of deze tekst het gegeven ís of er alleen naar wijst. Standaard [value]:
  /// een BSN, een IBAN, een e-mailadres is zichzelf, en alleen de trefwoordregels
  /// hoeven zich als aanwijzing te melden.
  final PrivacyTermRole role;

  const PrivacyFinding({
    required this.ruleId,
    required this.family,
    required this.confidence,
    required this.slideIndex,
    required this.field,
    required this.start,
    required this.end,
    required this.maskedSample,
    this.fragmentIndex = 0,
    this.role = PrivacyTermRole.value,
  });

  /// Of deze bevinding weggelakt hoort te worden als de slide op `redact` staat.
  ///
  /// Een aanwijzing gaat alleen mee als de escalator haar bereik heeft verbreed
  /// tot de hele mededeling — dan is het gegeven niet het woord maar de
  /// uitspraak, en dán haalt redactie werkelijk iets weg. Een losse `diagnose`
  /// zonder persoon eromheen blijft staan: er valt niets te verbergen, en een
  /// zwart blok op die plek liegt tegen de ontvanger.
  bool get isRedactable =>
      role == PrivacyTermRole.value || confidence == PrivacyConfidence.certain;

  bool get isDeckWide => slideIndex == kDeckWidePrivacyIndex;

  /// Dezelfde bevinding, geëscaleerd door de co-occurrence-escalator.
  ///
  /// Twee dingen veranderen tegelijk, en dat is geen toeval — het is dezelfde
  /// vaststelling, twee keer uitgedrukt:
  ///
  ///   * de zekerheid gaat omhoog: er staat iemand op de slide om het bijzondere
  ///     gegeven aan te koppelen, dus het is herleidbaar tot een persoon;
  ///   * het bereik gaat omhoog: bij een bijzonder gegeven is niet het wóórd het
  ///     gegeven maar de mededeling. "Marieke de Vries meldde zich ziek met een
  ///     diabetes-diagnose" met alleen `diagnose` weggelakt is nog steeds
  ///     leesbaar — en dat is precies wat er niét mocht.
  ///
  /// [maskedSample] blijft staan: dat is het trefwoord dat vuurde, en dát is wat
  /// de auteur wil zien om te begrijpen wáárom er iets weggaat.
  PrivacyFinding escalated({required int start, required int end}) =>
      PrivacyFinding(
        ruleId: ruleId,
        family: family,
        confidence: PrivacyConfidence.certain,
        slideIndex: slideIndex,
        field: field,
        fragmentIndex: fragmentIndex,
        start: start,
        end: end,
        maskedSample: maskedSample,
        role: role,
      );
}

/// Sentinel voor een bevinding die niet bij één slide hoort (frontmatter,
/// bestandsnaam).
const int kDeckWidePrivacyIndex = -1;

/// Regels die standaard uit staan.
///
/// Niet omdat ze onbelangrijk zijn — dit zijn juist de zwaarste categorieën uit
/// artikel 9 — maar omdat hun vals-positieven-ratio op gewone zakelijke slides
/// onhoudbaar is. Een slide over diversiteitsbeleid gaat *over* etniciteit zonder
/// etnische gegevens te bevatten; een verkiezingsanalyse noemt partijnamen zonder
/// iemands politieke voorkeur vast te leggen.
///
/// Ze staan er wél, en zijn met één vinkje aan te zetten voor wie in die hoek
/// werkt. Dat is beter dan ze weglaten: de keuze hoort bij de gebruiker, niet bij
/// ons.
const Set<String> defaultDisabledPrivacyRules = {
  'special.politics',
  'special.ethnicity',
  'special.sexlife',
};

/// Maskeert een gevonden waarde voor weergave.
///
/// Toont hooguit het eerste en laatste teken. Een BSN wordt `1…2`, een
/// e-mailadres `j…l`. Genoeg om te herkennen wélke treffer bedoeld wordt als er
/// meerdere op een slide staan, te weinig om de waarde te reconstrueren — en dus
/// veilig om in een melding, een tooltip of een exportsamenvatting te zetten.
String maskValue(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 2) return '…';
  return '${trimmed[0]}…${trimmed[trimmed.length - 1]}';
}

/// Alle bevindingen van één scan.
class PrivacyScanResult {
  final List<PrivacyFinding> findings;

  const PrivacyScanResult(this.findings);

  static const empty = PrivacyScanResult([]);

  bool get isEmpty => findings.isEmpty;
  bool get isNotEmpty => findings.isNotEmpty;

  /// Alleen de zekere treffers. Dit is de verzameling die de gebruiker mag
  /// onderbreken — bij een export-gate, bij een rode badge.
  Iterable<PrivacyFinding> get certain =>
      findings.where((f) => f.confidence == PrivacyConfidence.certain);

  Iterable<PrivacyFinding> forSlide(int index) =>
      findings.where((f) => f.slideIndex == index);

  /// Welke regels op deze scan hebben gevuurd, ongeacht hoe vaak.
  Set<String> get firedRules => {for (final f in findings) f.ruleId};
}
