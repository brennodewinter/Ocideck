part of 'privacy_scanner.dart';

// Terzijdegelegde privacybevindingen: van een melding in het paneel naar een
// commitment in de sidecar (#651, FILE_FORMAT §6.7).
//
// Apart bestand om dezelfde reden als `privacy_scanner_fragments.dart`:
// `privacy_scanner.dart` zit tegen de regelratchet aan.
//
// Alles hier staat top-level en niet op `PrivacyScanner` — geen van deze
// functies raakt een veld van die klasse aan; ze hebben hem alleen nodig om bij
// de private fragmentlijst te komen.
//
// De reden dat dít de plek is en niet de widgetlaag: hier ligt de gevonden
// waarde. Die wordt opgezocht, meteen tot een commitment verwerkt, en gaat niet
// verder. De brug naar het kwaliteitspaneel geeft de volledige waarde bewust
// nooit door — een privacycontrole die de gevonden BSN's in haar eigen
// meldingen zet, heeft het probleem verplaatst in plaats van opgelost.

/// De bevinding uit [findings] die bij [issue] hoort, of null.
///
/// Het kwaliteitspaneel werkt met [SlideQualityIssue]; een terzijdelegging
/// hangt aan de [PrivacyFinding] eronder, want alleen die draagt de
/// onbewerkte regel-id. De melding draagt een variant mét persoonsrol
/// (`nl.crime.reporter`), en dat is een andere sleutel.
///
/// Gekoppeld op de coördinaten, want die staan in allebei: dia, veld,
/// fragment en de positie binnen dat fragment.
PrivacyFinding? findingForIssue(
  List<PrivacyFinding> findings,
  int slideIndex,
  String field,
  int fragmentIndex,
  int start,
  int end,
) {
  for (final f in findings) {
    if (f.slideIndex == slideIndex &&
        f.field == field &&
        f.fragmentIndex == fragmentIndex &&
        f.start == start &&
        f.end == end) {
      return f;
    }
  }
  return null;
}

/// [current] met [finding] terzijdegelegd, of null wanneer de tekst niet meer
/// te vinden is.
///
/// De waarde wordt hier opgezocht en meteen tot een commitment verwerkt; ze
/// verlaat deze laag niet. Zie [matchedTextOf].
///
/// Null betekent: de dia is bewerkt sinds de scan en er valt niets te
/// beoordelen. De aanroeper hoort dan niets te doen, in plaats van een
/// willekeurig stuk tekst vast te leggen.
DeckDismissals? withFindingSetAside(
  PrivacyScanner scanner,
  Deck deck,
  PrivacyFinding finding,
  DateTime at,
) {
  final text = matchedTextOf(scanner, deck, finding);
  if (text == null) return null;
  final base = deck.dismissals ?? DeckDismissals(salt: newDismissalSalt());
  return DeckDismissals(
    salt: base.salt,
    dismissals: [
      ...base.dismissals,
      PrivacyDismissal(
        ruleId: finding.ruleId,
        commitment: commitmentFor(base.salt, text),
        at: at.toUtc(),
        seenAtSlide: finding.isDeckWide ? null : finding.slideIndex,
        seenAtField: finding.field,
        seenAtFragment: finding.fragmentIndex,
      ),
    ],
    revocations: base.revocations,
  );
}

/// [current] met [dismissal] herroepen: de terzijdelegging blijft staan en er
/// komt een grafsteen bij met een later tijdstip.
///
/// Niet verwijderen. Een weggegooide terzijdelegging keert bij de
/// eerstvolgende samenvoeging terug van de andere kant, en dan is de bevinding
/// weer verborgen zonder dat iemand daarvoor koos.
DeckDismissals withDismissalRevoked(
  DeckDismissals current,
  PrivacyDismissal dismissal,
  DateTime at,
) => DeckDismissals(
  salt: current.salt,
  dismissals: current.dismissals,
  revocations: [
    ...current.revocations,
    PrivacyDismissal(
      ruleId: dismissal.ruleId,
      commitment: dismissal.commitment,
      at: at.toUtc(),
    ),
  ],
);

/// De tekst waar [finding] op sloeg, of null wanneer die niet meer bestaat.
///
/// Nodig om een bevinding terzijde te kunnen leggen (#651): de terzijdelegging
/// bewaart `SHA-256(zout ‖ tekst)`, en die tekst staat nergens in de bevinding
/// zelf. Met opzet niet — `PrivacyFinding.maskedSample` is gemaskeerd, en de
/// brug naar het kwaliteitspaneel geeft de volledige waarde bewust nooit door.
/// Een privacycontrole die de gevonden BSN's in haar eigen meldingen zet,
/// heeft het probleem verplaatst in plaats van opgelost.
///
/// Daarom staat deze functie hier, in de scannerbibliotheek: de waarde wordt
/// opgezocht, meteen tot een commitment verwerkt, en verlaat deze laag niet.
///
/// Null wanneer het fragment weg is of korter is geworden dan de opgeslagen
/// positie — de dia is dan bewerkt sinds de scan, en de aanroeper hoort dat
/// als "niets te doen" te behandelen in plaats van een willekeurig stuk tekst
/// te nemen.
String? matchedTextOf(
  PrivacyScanner scanner,
  Deck deck,
  PrivacyFinding finding,
) {
  final fragments = finding.isDeckWide
      ? scanner._deckFragments(deck)
      : (finding.slideIndex >= 0 && finding.slideIndex < deck.slides.length
            ? scanner._slideFragments(deck.slides[finding.slideIndex])
            : const <_Fragment>[]);
  for (final fragment in fragments) {
    if (fragment.field != finding.field) continue;
    if (fragment.index != finding.fragmentIndex) continue;
    if (finding.start < 0 ||
        finding.end > fragment.text.length ||
        finding.start >= finding.end) {
      return null;
    }
    return fragment.text.substring(finding.start, finding.end);
  }
  return null;
}

/// Hoe ver een contextwoord vóór een treffer mag staan om nog te tellen.
///
/// Ruim genoeg voor "Het burgerservicenummer van betrokkene is 123456782", krap
/// genoeg dat een woord elders in de zin niet meetelt.
const int kContextWindow = 40;

/// Het gewicht waarmee een term uit de gebundelde bronnen meedoet.
///
/// Maximaal, want zo'n term ís het gegeven waar een signaalwoord alleen naar
/// wijst: `taaislijmziekte` tegenover `diagnose`, `katholicisme` tegenover
/// `geloofsovertuiging`. Zie `privacy_bulk_lexicon.dart` voor de metingen die
/// dat rechtvaardigen.
const int _kBulkTermWeight = 5;

/// Contextwoorden die van een 11-proef-treffer een echte BSN-melding maken.
/// Zonder een van deze blijft de treffer informatief — zie [_scanBsn].
const List<String> bsnContextWords = [
  'bsn',
  'burgerservicenummer',
  'burgerservice',
  'sofinummer',
  'sofi-nummer',
  'sofinr',
];

final _reEmail = RegExp(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}");

/// De handmatige redactiemarkering in de bron: `[[tekst]]`.
///
/// Detectie is per definitie best-effort — wat de scanner niet ziet, redigeert
/// hij niet. Deze markering geeft de auteur het laatste woord, onafhankelijk van
/// welke detectieregel wel of niet vuurt. Geen geneste blokhaken, zodat een
/// gewone markdown-link (`[tekst](url)`) er niet in loopt.
///
/// Staat hier en niet in `privacy_projection.dart`, omdat die de scanner al
/// importeert en de omgekeerde richting een cyclus zou zijn.
final RegExp kManualRedaction = RegExp(r'\[\[([^\[\]]*)\]\]');

/// Een IBAN staat vaak met spaties in een tekst. We accepteren die en
/// normaliseren pas in de validatie.
final _reIban = RegExp(r'\b[A-Z]{2}\d{2}(?:[ -]?[A-Z0-9]){10,30}\b');

/// Negen losstaande cijfers. Bewust ruim: de 11-proef en de contextpoort doen
/// het filterwerk, niet de regex.
final _reNineDigits = RegExp(r'(?<!\d)\d{9}(?!\d)');
