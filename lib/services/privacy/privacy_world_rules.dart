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

  // ── De zorgnummers ─────────────────────────────────────────────────────────
  //
  // In de VS routineuze administratie, onder de AVG artikel 9-gebied: deze drie
  // verschijnen in de context van zorg, en dat maakt van de identificator een
  // gegeven over gezondheid. §15.2 noemt dit de blinde vlek van elke lijst die
  // van Amerikaanse wetgeving is overgeschreven.
  //
  // Alle drie met een contextpoort, en geen van drieën op `certain`. De
  // controles zijn zwakker dan ze ogen: Luhn bij het NPI en een mod-10 bij het
  // DEA-nummer laten allebei ongeveer één op de tien willekeurige getallen
  // door, en het MBI heeft helemaal geen checksum. Dat is dezelfde correctie
  // die §15.4 op `ca.sin` maakt — de ontwerptabel in §15.3 zet deze drie nog op
  // "zeker", en dat is bij nader inzien te sterk.
  NationalIdentifierRule(
    id: 'us.npi',
    country: 'US',
    pattern: RegExp(r'(?<!\d)[12]\d{9}(?!\d)'),
    validate: isValidUsNpi,
    contextWords: ['npi', 'national provider', 'provider id', 'rendering'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'us.medicare_mbi',
    country: 'US',
    // De koppeltekens staan in het CMS-voorbeeld (`1EG4-TE5-MK73`) maar zijn
    // geen onderdeel van het nummer; ze mogen er wel of niet staan.
    pattern: RegExp(
      r'(?<![0-9A-Za-z])[1-9][ACDEFGHJKMNPQRTUVWXY]'
      r'[0-9ACDEFGHJKMNPQRTUVWXY]\d-?'
      r'[ACDEFGHJKMNPQRTUVWXY][0-9ACDEFGHJKMNPQRTUVWXY]\d-?'
      r'[ACDEFGHJKMNPQRTUVWXY]{2}\d{2}(?![0-9A-Za-z])',
    ),
    validate: isValidUsMbi,
    contextWords: ['mbi', 'medicare', 'beneficiary'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'us.dea',
    country: 'US',
    pattern: RegExp(r'(?<![0-9A-Za-z])[A-Za-z]{2}\d{7}(?![0-9A-Za-z])'),
    validate: isValidUsDea,
    contextWords: ['dea', 'dea#', 'prescriber', 'npi/dea'],
    confidence: PrivacyConfidence.likely,
  ),
  // ── Canada ────────────────────────────────────────────────────────────────
  //
  // De zorgnummers zijn hier provinciaal, niet landelijk. RAMQ (Québec) en OHIP
  // (Ontario) dekken samen ruim zestig procent van de bevolking; de overige elf
  // provincies hebben elk een eigen formaat, meestal negen of tien kale cijfers
  // zonder controlecijfer. Die zijn bewust níét gebouwd — het zouden regels zijn
  // die volledig op een contextwoord leunen, en dat is precies de ruis waar §15.5
  // het rijbewijs om afwijst.
  NationalIdentifierRule(
    id: 'ca.sin',
    country: 'CA',
    pattern: RegExp(r'(?<!\d)\d{3}[- ]?\d{3}[- ]?\d{3}(?!\d)'),
    validate: isValidCaSin,
    // §15.4 corrigeert het ontwerp hier: een Luhn over negen cijfers laat één op
    // de tien willekeurige getallen door, dezelfde orde als de 11-proef bij het
    // BSN. Wat een checksum sterk maakt is de lengte, niet de checksum.
    contextWords: ['sin', 'social insurance', 'nas', "numéro d'assurance"],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'ca.ramq',
    country: 'CA',
    // Vier letters plus acht cijfers: `ABCD 1234 5678`.
    pattern: RegExp(
      r'(?<![A-Za-z0-9])[A-Za-z]{4}[- ]?\d{4}[- ]?\d{4}(?![A-Za-z0-9])',
    ),
    validate: isValidCaRamq,
    // Codeert geboortedatum én geslacht, net als de Franse NIR — dit nummer is
    // daarmee bijna zelf al een bijzonder gegeven.
    contextWords: ['ramq', 'assurance maladie', 'carte soleil', 'nam'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'ca.ohip',
    country: 'CA',
    pattern: RegExp(
      r'(?<!\d)\d{4}[- ]?\d{3}[- ]?\d{3}(?:[- ]?[A-Za-z]{2})?(?!\d)',
    ),
    validate: isValidCaOhip,
    contextWords: ['ohip', 'health card', 'health number', 'carte santé'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'ca.bn',
    country: 'CA',
    pattern: RegExp(r'(?<!\d)\d{9}(?:[- ]?[A-Za-z]{2}\d{4})?(?!\d)'),
    validate: isValidCaBn,
    contextWords: ['business number', 'bn', 'numéro d\'entreprise'],
    confidence: PrivacyConfidence.possible,
  ),
  // ── Australië ─────────────────────────────────────────────────────────────
  NationalIdentifierRule(
    id: 'au.tfn',
    country: 'AU',
    pattern: RegExp(r'(?<!\d)\d{3}[- ]?\d{3}[- ]?\d{3}(?!\d)'),
    validate: isValidAuTfn,
    // §15.4: negen cijfers met een mod-11 is te zwak om alleen op af te gaan.
    contextWords: ['tfn', 'tax file'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'au.medicare',
    country: 'AU',
    pattern: RegExp(r'(?<!\d)[2-6]\d{3}[- ]?\d{5}[- ]?\d(?!\d)'),
    validate: isValidAuMedicare,
    contextWords: ['medicare', 'health', 'gezondheid'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'au.abn',
    country: 'AU',
    pattern: RegExp(r'(?<!\d)\d{2}[- ]?\d{3}[- ]?\d{3}[- ]?\d{3}(?!\d)'),
    validate: isValidAuAbn,
    contextWords: ['abn', 'business number'],
    confidence: PrivacyConfidence.possible,
  ),

  // ── India ─────────────────────────────────────────────────────────────────
  NationalIdentifierRule(
    id: 'in.aadhaar',
    country: 'IN',
    pattern: RegExp(r'(?<!\d)[2-9]\d{3}[- ]?\d{4}[- ]?\d{4}(?!\d)'),
    validate: isValidInAadhaar,
    // Twaalf cijfers plus Verhoeff draagt op eigen kracht: Verhoeff vangt álle
    // enkelvoudige fouten en álle verwisselingen van buren, waar Luhn er een
    // deel doorlaat. Geen contextpoort nodig.
  ),
  NationalIdentifierRule(
    id: 'in.pan',
    country: 'IN',
    pattern: RegExp(r'(?<![A-Za-z0-9])[A-Za-z]{5}\d{4}[A-Za-z](?![A-Za-z0-9])'),
    validate: isValidInPan,
    contextWords: ['pan', 'permanent account'],
    confidence: PrivacyConfidence.likely,
  ),

  // ── Zuid-Afrika ───────────────────────────────────────────────────────────
  NationalIdentifierRule(
    id: 'za.id',
    country: 'ZA',
    pattern: RegExp(r'(?<!\d)\d{6}[- ]?\d{4}[- ]?\d{3}(?!\d)'),
    validate: isValidZaId,
    // Luhn plus een geldige geboortedatum over dertien cijfers: sterk genoeg
    // voor `certain`, anders dan de losse Luhn-nummers uit §15.4.
  ),

  // ── Curaçao en Aruba ──────────────────────────────────────────────────────
  NationalIdentifierRule(
    id: 'cw.sedula',
    country: 'CW',
    pattern: RegExp(r'(?<!\d)\d{10}(?!\d)'),
    validate: isValidCwSedula,
    contextWords: ['sedula', 'sédula', 'identiteitskaart', 'id-kaart'],
    confidence: PrivacyConfidence.possible,
  ),
  NationalIdentifierRule(
    id: 'aw.persoonsnummer',
    country: 'AW',
    pattern: RegExp(r'(?<!\d)\d{8,10}(?!\d)'),
    validate: isValidAwPersoonsnummer,
    contextWords: ['persoonsnummer', 'persoonsnr', 'cedula'],
    confidence: PrivacyConfidence.possible,
  ),

  // ── Brazilië ──────────────────────────────────────────────────────────────
  NationalIdentifierRule(
    id: 'br.cpf',
    country: 'BR',
    pattern: RegExp(r'(?<!\d)\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?!\d)'),
    validate: isValidBrCpf,
    // Twee onafhankelijke mod-11-controles over elf cijfers: dat is een andere
    // orde dan één controle, en draagt `certain`.
  ),
  NationalIdentifierRule(
    id: 'br.cnpj',
    country: 'BR',
    pattern: RegExp(r'(?<!\d)\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}(?!\d)'),
    validate: isValidBrCnpj,
    confidence: PrivacyConfidence.possible,
  ),
];
