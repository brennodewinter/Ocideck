// De landpakketten buiten Europa (OCIWACHT §15).
//
// Zelfde vorm als `privacy_eu_rules.dart`, andere onderbouwing. Daar draagt de
// checksum het bewijs; hier is er meestal geen, en draagt de **contextpoort**
// het. Dat verschil staat uitgelegd in `privacy_checksums_world.dart`.
//
// ── Waarom de AVG en niet de Amerikaanse opsomming ──────────────────────────
//
// Het Amerikaanse recht is sectoraal — HIPAA voor zorg, GLBA voor financiën,
// FERPA voor onderwijs — en werkt met een opgesómde lijst PII. De AVG kent een
// open norm: alle informatie over een identificeerbare natuurlijke persoon. Wie
// de Amerikaanse lijst overneemt, bouwt de verkeerde tool: die lijst is
// geschreven om te bepalen wanneer een meldplicht ontstaat, niet om te bepalen
// wanneer iemand herkenbaar is.
//
// Praktisch gevolg voor deze tabel: het ITIN staat erin. Onder Amerikaans recht
// is dat een fiscaal administratienummer; onder de AVG wijst het een
// niet-ingezetene aan, en daarmee raakt het aan verblijfsstatus.

import '../../models/privacy_finding.dart';
import 'privacy_checksums_world.dart';
import 'privacy_national_rule.dart';

/// De niet-Europese landpakketten.
///
/// Op `fin.us_routing` na, want dat is financiële data en hangt aan de
/// universele laag: een Amerikaans rekeningnummer hoort niet stil te blijven
/// omdat iemand het VS-pakket uit had staan.
final List<NationalIdentifierRule> worldIdentifierRules = [
  // ── Verenigde Staten ──────────────────────────────────────────────────────
  NationalIdentifierRule(
    id: 'us.ssn',
    country: 'US',
    // Scheidingstekens optioneel: `123-45-6789`, `123 45 6789` en negen kale
    // cijfers komen alledrie voor. De kale variant leunt volledig op de
    // contextpoort hieronder.
    pattern: RegExp(r'(?<!\d)\d{3}[- ]?\d{2}[- ]?\d{4}(?!\d)'),
    validate: isValidUsSsn,
    // Verplicht, en dat is geen voorzichtigheid maar noodzaak. De bereikcontrole
    // schrapt maar een paar procent van de willekeurige negencijferige getallen,
    // dus zonder poort zou elk ordernummer een SSN worden. Erger: een
    // identificator telt als persoonskoppeling, en tilt daarmee élk artikel
    // 9-trefwoord op dezelfde slide naar `certain`. Dat is precies de cascade
    // die bij `hu.taj` gemeten is.
    contextWords: ['ssn', 'social security', 'soc sec', 'ss#', 'ssn#'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'us.ssn_last4',
    country: 'US',
    // De gemaskeerde vorm: `XXX-XX-1234`, `***-**-1234`, `•••-••-1234`.
    //
    // Amerikaans idioom zonder Europese tegenhanger, en juist daarom makkelijk
    // te missen. Onder de AVG is dit geen "geanonimiseerd" gegeven maar een
    // pseudonieme identificator: vier cijfers plus een naam of geboortedatum op
    // dezelfde slide wijzen weer één persoon aan.
    pattern: RegExp(r'(?<![\w*•])[Xx*•]{3}[- ]?[Xx*•]{2}[- ]?\d{4}(?![\w*•])'),
    contextWords: ['ssn', 'social security', 'last 4', 'last four'],
    confidence: PrivacyConfidence.possible,
  ),
  NationalIdentifierRule(
    id: 'us.itin',
    country: 'US',
    pattern: RegExp(r'(?<!\d)9\d{2}[- ]?\d{2}[- ]?\d{4}(?!\d)'),
    validate: isValidUsItin,
    contextWords: ['itin', 'taxpayer id', 'individual taxpayer', 'tin'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'us.ein',
    country: 'US',
    // Het EIN wordt met een koppelteken ná twee cijfers geschreven, en dat is
    // het enige wat hem van een SSN onderscheidt — beide zijn negen cijfers.
    // Daarom hier wél het streepje verplicht: zonder dat onderscheid zouden de
    // twee regels elkaars treffers overnemen.
    pattern: RegExp(r'(?<!\d)\d{2}-\d{7}(?!\d)'),
    validate: isValidUsEin,
    contextWords: ['ein', 'employer id', 'employer identification', 'fein'],
    confidence: PrivacyConfidence.possible,
  ),
];
