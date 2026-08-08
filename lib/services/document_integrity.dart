import '../models/deck.dart';
import '../models/document_signature.dart';
import '../models/redaction_manifest.dart';
import '../models/seal_record.dart';
import '../utils/content_hash.dart';
import '../utils/secure_compare.dart';
import 'markdown_service.dart';

/// Result of verifying a deck's document seal (§8 A1).
enum IntegrityStatus {
  /// The deck is not finalised/sealed — there is nothing to verify.
  notSealed,

  /// The recomputed content hash matches the stored seal: intact.
  intact,

  /// The recomputed content hash differs from the stored seal: the content was
  /// changed after finalising (tamper-evidence).
  changed,

  /// Verzegeld, maar er is niets om het zegel tegen na te rekenen.
  ///
  /// Twee manieren om hier te komen, en ze lopen op hetzelfde uit: het deck is
  /// zojuist afgerond maar nog niet opgeslagen (de hash gaat over bestandsbytes,
  /// dus die kan pas bestaan zodra het bestand bestaat), of het deck is nooit
  /// uit een bestand gekomen. In beide gevallen is "intact" een bewering die
  /// niemand kan staven, en die is erger dan geen bewering.
  notVerifiable,

  /// Een geredigeerde afleiding van een verzegeld deck.
  ///
  /// Dit bestaat om een vals alarm te voorkomen, en dat is geen bijzaak. Een
  /// geredigeerd artefact heeft per definitie andere inhoud dan de bron, dus de
  /// hertelde hash wijkt af — en zonder deze status zou een auditor die het
  /// pakket natrekt tot "GEMANIPULEERD" concluderen. Een vals tamper-alarm op een
  /// echt rapport is erger dan geen integriteitscontrole hebben: het maakt het
  /// mechanisme onbetrouwbaar precies wanneer het ertoe doet.
  ///
  /// De controle loopt hier niet tegen de inhoudshash maar tegen het
  /// redactiemanifest (`redaction_manifest.dart`): elke redactie moet uit de
  /// bron terug te rekenen zijn, en er mogen er niet meer of minder zijn.
  redactedDerivative,
}

/// The general "Document integrity" capability (§8 A1): compute and verify a
/// content seal over a deck, and produce a sealed copy.
///
/// The guarantee is deliberately **tamper-evidence**, not impossibility: a
/// `.md` handed to someone else can always be edited, but a mismatch between the
/// recomputed hash and the stored [Deck.sealHash] makes such an edit visible.
///
/// **Het zegel gaat over de bytes van de `.md`.** Niet over een canonicalisatie,
/// niet over de uitvoer van een serialisator, niet over een selectie van velden:
/// over het bestand. Dat is de hele winst van het zegel ernaast zetten in plaats
/// van erin. Een ontvanger heeft OciDeck niet nodig en hoeft geen specificatie
/// na te spelen — `sha512sum rapport.md` en vergelijken met `hash` uit
/// `rapport.seal.json`, klaar. Er is dan ook géén normalisatiestap: geen
/// regeleinde-omzetting, geen trimmen, geen sortering. Elke stap die hier stond
/// zou een stap zijn die de ontvanger moet naspelen, en dus een stap waarop de
/// controle stuk kan gaan.
///
/// De keerzijde is dat het zegel streng is: élke wijziging aan de `.md` breekt
/// het, ook een die niets aan de inhoud verandert. Dat is de bedoeling — een
/// verzegeld document is bevroren — en het is waarom OciDeck een verzegeld deck
/// alleen-lezen maakt in plaats van erop te vertrouwen dat niemand het opslaat.
///
/// Zie [SealForm.canonical] voor de oude vorm, die alleen nog voorkomt op een
/// deck van vóór 0.1.0.
class DocumentIntegrity {
  /// The one hash algorithm A1 uses. Recorded in the seal sidecar so a future
  /// algorithm stays distinguishable.
  static const String algorithm = 'sha-512';

  final MarkdownService _md;

  DocumentIntegrity(this._md);

  /// De zegelhash over [bytes]: de SHA-512 in kleine-letter-hex, precies zoals
  /// `sha512sum` hem afdrukt.
  static String hashBytes(List<int> bytes) => sha512Hex(bytes);

  /// De zegelhash over [markdown] zoals het bestand hem krijgt: UTF-8, zonder
  /// enige bewerking. OciDeck schrijft elke `.md` met `utf8.encode` van precies
  /// deze tekst, dus dit is de hash van het bestand op schijf.
  static String hashMarkdown(String markdown) => sha512HexOfText(markdown);

  /// De hash zoals een deck van vóór 0.1.0 hem droeg: over de uitvoer van
  /// [MarkdownService.canonicalContentForSeal]. Alleen nog gebruikt om zo'n oud
  /// zegel te blijven controleren; nieuwe zegels ontstaan nooit zo.
  String computeCanonicalHash(Deck deck) =>
      hashMarkdown(_md.canonicalContentForSeal(deck));

  /// [deck] nadat [markdown] als zijn `.md` is weggeschreven — de enige plek
  /// waar een zegelhash ontstaat.
  ///
  /// Twee regels, en ze zijn allebei belangrijk.
  ///
  /// [Deck.fileHash] wordt altijd bijgewerkt: dat is de *waargenomen* toestand
  /// van het bestand. Zonder deze regel zou een deck na opslaan nog rondlopen
  /// met de hash van vóór de opslag.
  ///
  /// [Deck.sealHash] wordt alleen gezet als hij nog leeg is, en dat is de
  /// tamper-evidence zelf: bij het verzegelen bestond het bestand nog niet, dus
  /// de eerste opslag legt de hash vast. Elke opslag daarna raakt hem niet meer
  /// aan. Zou hij opnieuw worden uitgerekend, dan keurde elke wijziging zichzelf
  /// goed en betekende het zegel niets meer.
  static Deck recordWrittenBytes(Deck deck, String markdown) {
    final hash = hashMarkdown(markdown);
    final fresh = deck.finalized && deck.sealHash.isEmpty;
    return deck.copyWith(
      fileHash: hash,
      sealHash: fresh ? hash : null,
      sealForm: fresh ? SealForm.fileBytes : null,
    );
  }

  /// Verify [deck] against its stored seal.
  IntegrityStatus verify(Deck deck) {
    if (!deck.finalized) return IntegrityStatus.notSealed;
    if (deck.sealHash.isEmpty) return IntegrityStatus.notVerifiable;
    switch (deck.sealForm) {
      case SealForm.fileBytes:
        if (deck.fileHash.isEmpty) return IntegrityStatus.notVerifiable;
        return constantTimeEqualsString(deck.fileHash, deck.sealHash)
            ? IntegrityStatus.intact
            : IntegrityStatus.changed;
      case SealForm.canonical:
        return constantTimeEqualsString(
              computeCanonicalHash(deck),
              deck.sealHash,
            )
            ? IntegrityStatus.intact
            : IntegrityStatus.changed;
    }
  }

  /// Verifieer een **geredigeerde afleiding** tegen de bron waaruit hij komt.
  ///
  /// Dit is het pad voor een auditor die twee dingen heeft: het geredigeerde
  /// rapport (met zijn manifest) en de gezegelde bron. De inhoudshash klópt hier
  /// per definitie niet — dat is geen manipulatie maar redactie — dus de controle
  /// loopt tegen het manifest.
  ///
  /// [IntegrityStatus.changed] betekent hier: het manifest hoort niet bij deze
  /// bron. Er is een redactie toegevoegd, weggelaten, of hij verbergt iets anders
  /// dan hij beweert.
  IntegrityStatus verifyRedactedDerivative(
    RedactionManifest manifest,
    Deck source, {
    required bool Function(RedactionManifest, Deck) verifier,
  }) {
    // Een bron die zelf niet klopt, kan geen afleiding staven.
    final sourceStatus = verify(source);
    if (sourceStatus == IntegrityStatus.changed) return IntegrityStatus.changed;
    // Niet verzegeld óf niets om tegen na te rekenen: er is geen bron om deze
    // afleiding aan op te hangen. Dat is geen manipulatiemelding.
    if (sourceStatus != IntegrityStatus.intact) {
      return IntegrityStatus.notSealed;
    }
    if (manifest.derivedFrom != source.sealHash) return IntegrityStatus.changed;
    return verifier(manifest, source)
        ? IntegrityStatus.redactedDerivative
        : IntegrityStatus.changed;
  }

  /// Return a finalised copy of [deck]: the read-only lock, the algorithm, the
  /// form and the moment of sealing. [at] defaults to now (UTC). Finalising is
  /// intentionally one-way in the UI — there is no matching "unseal" here.
  ///
  /// **De hash zet dit niet.** Die gaat over de bytes van de `.md`, en die
  /// bestaan pas wanneer het deck wordt opgeslagen — de opslagroute vult hem in
  /// ([Deck.sealHash] blijft tot dat moment leeg, en het zegel meldt zich als
  /// [IntegrityStatus.notVerifiable]). Vooruitrekenen op wat de serialisator
  /// straks zou schrijven, was precies de fout die dit zegel niet meer maakt:
  /// het opslaan verplaatst afbeeldingen en grafiekdata, dus de bytes die
  /// werkelijk op schijf komen zijn niet de bytes die je hier zou hashen.
  Deck seal(Deck deck, {DocumentSignature? signature, DateTime? at}) {
    final when = (at ?? DateTime.now()).toUtc();
    return deck.copyWith(
      finalized: true,
      sealHash: '',
      sealAlgo: algorithm,
      sealForm: SealForm.fileBytes,
      sealAt: when.toIso8601String(),
      signature: (signature != null && signature.isNotEmpty) ? signature : null,
      clearSignature: signature != null && signature.isEmpty,
    );
  }
}

/// Convenience for widgets that only hold a [Deck] (e.g. the status bar badge):
/// verify [deck] with a fresh [MarkdownService]. Cheap; only meaningful for a
/// finalised deck, so callers typically guard on [Deck.finalized] first.
IntegrityStatus deckIntegrityStatus(Deck deck) =>
    DocumentIntegrity(MarkdownService()).verify(deck);

/// The 1-based slide numbers that still carry unreviewed AI-assist markers
/// (AI_ASSIST §16.3, [Slide.aiAssistedFields]). While this is non-empty the deck
/// must **not** be sealed: the EIS 1.6 attestation has to cover human-verified
/// text, so every AI-drafted field must be reviewed and cleared first. AI
/// drafting (P3-AIA) sets the markers and clears them on review; the finding and
/// image editors set them when a field is AI-drafted, so a deck can carry
/// unreviewed markers until each is cleared.
List<int> slidesWithUnreviewedAiMarkers(Deck deck) => [
  for (var i = 0; i < deck.slides.length; i++)
    if (deck.slides[i].aiAssistedFields.isNotEmpty) i + 1,
];

/// Whether any slide carries an unreviewed AI-assist marker — i.e. sealing is
/// blocked (see [slidesWithUnreviewedAiMarkers]).
bool deckHasUnreviewedAiMarkers(Deck deck) =>
    deck.slides.any((s) => s.aiAssistedFields.isNotEmpty);
