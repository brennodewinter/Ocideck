import 'deck.dart';
import 'document_signature.dart';
import 'provenance_signature.dart';

/// Waar de zegelhash over gaat. Het is het enige dat een ontvanger moet weten om
/// hem na te rekenen, dus het staat in het bestand en niet in een release-noot.
enum SealForm {
  /// De hash gaat over de **bytes van de `.md`**, precies zoals ze op schijf
  /// staan: geen normalisatie, geen serialisator, geen OciDeck.
  /// `sha512sum rapport.md` levert deze waarde op.
  fileBytes('file-bytes-v1'),

  /// De oude vorm: een hash over de uitvoer van OciDecks eigen serialisator
  /// (`MarkdownService.canonicalContentForSeal`). Alleen nog te vinden op een
  /// deck dat vóór 0.1.0 is verzegeld.
  ///
  /// Hij blijft bestaan omdat herberekenen niet mag: een RFC 3161-token
  /// tijdstempelt precies déze hash, dus hem vervangen door een bytehash zou
  /// een echte notarisatie ongeldig maken. Zo'n zegel blijft dus verifieerbaar
  /// op de oude manier, en alleen op de oude manier — narekenen buiten OciDeck
  /// om kan er niet bij.
  canonical('canonical-v1');

  const SealForm(this.key);

  /// De waarde zoals ze in de sidecar staat.
  final String key;

  /// De vorm die [raw] noemt. Iets onbekends telt als [fileBytes]: dat is de
  /// vorm die deze build schrijft, en een sidecar met een vorm van later wordt
  /// al tegengehouden door de versiecontrole van de sidecar.
  static SealForm fromKey(String raw) {
    for (final form in SealForm.values) {
      if (form.key == raw.trim()) return form;
    }
    return SealForm.fileBytes;
  }
}

/// Alles wat over de vaststelling van een document gaat in plaats van erin: de
/// vergrendeling, het zegel, de tijdstempel en de handtekening van wie tekende.
///
/// Woont op schijf in `<naam>.seal.json` (zie `seal_codec.dart`).
class SealRecord {
  final bool finalized;
  final String hash;
  final String algo;
  final String at;
  final SealForm form;
  final String timestampToken;

  /// De nonce (hex) van het uitstaande verzoek; zie [Deck.sealTimestampNonce].
  final String timestampNonce;
  final DocumentSignature? signature;
  final ProvenanceSignature? provenance;

  const SealRecord({
    this.finalized = false,
    this.hash = '',
    this.algo = '',
    this.at = '',
    this.form = SealForm.fileBytes,
    this.timestampToken = '',
    this.timestampNonce = '',
    this.signature,
    this.provenance,
  });

  /// Niets vast te leggen — dan hoort er ook geen sidecar te liggen.
  bool get isEmpty =>
      !finalized &&
      hash.isEmpty &&
      at.isEmpty &&
      timestampToken.isEmpty &&
      timestampNonce.isEmpty &&
      (signature?.isEmpty ?? true) &&
      (provenance?.isEmpty ?? true);

  /// De vaststelling zoals [deck] hem draagt.
  factory SealRecord.of(Deck deck) => SealRecord(
    finalized: deck.finalized,
    hash: deck.sealHash,
    algo: deck.sealAlgo,
    at: deck.sealAt,
    form: deck.sealForm,
    timestampToken: deck.sealTimestampToken,
    timestampNonce: deck.sealTimestampNonce,
    signature: deck.signature,
    provenance: deck.provenance,
  );

  /// [deck] met deze vaststelling erop. De sidecar is de waarheid: wat de
  /// parser nog uit de oude front matter haalde, wordt hier vervangen.
  Deck applyTo(Deck deck) => deck.copyWith(
    finalized: finalized,
    sealHash: hash,
    sealAlgo: algo,
    sealAt: at,
    sealForm: form,
    sealTimestampToken: timestampToken,
    sealTimestampNonce: timestampNonce,
    signature: signature,
    clearSignature: signature?.isEmpty ?? true,
    provenance: provenance,
    clearProvenance: provenance?.isEmpty ?? true,
  );
}
