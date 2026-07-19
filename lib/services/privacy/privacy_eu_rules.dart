// De Europese landpakketten.
//
// Waarom "heel Europa" standaard aan mag staan: ruim twintig van de dertig
// nummers zijn zelfvalidereend. Een checksum kóst geen precisie, hij wint
// precisie — het aanzetten van het Kroatische OIB maakt de scanner niet luider,
// alleen breder. De ruis zat nooit in de checksum-nummers maar in de handvol
// zónder, en díé zijn contextpoort-gebonden, precies zoals het BSN dat is.
//
// Elke regel is data: id, land, patroon, validatie, en of er een contextwoord
// nodig is. Een land toevoegen is één regel in de tabel.

import '../../models/privacy_finding.dart';
import 'privacy_checksums_eu.dart';

/// Eén nationaal identificatienummer.
class EuIdentifierRule {
  final String id;

  /// ISO-landcode. Bepaalt of de regel meedraait bij het gekozen regiopakket.
  final String country;

  final RegExp pattern;

  /// De checksum. Null = er ís er geen, en dan is een contextwoord verplicht.
  final bool Function(String)? validate;

  /// Woorden die in de buurt moeten staan wanneer er geen checksum is, of
  /// wanneer de checksum te zwak is om alleen op af te gaan.
  final List<String> contextWords;

  /// Zonder checksum is het formaat geen bewijs: dan hooguit `likely`.
  final PrivacyConfidence confidence;

  const EuIdentifierRule({
    required this.id,
    required this.country,
    required this.pattern,
    this.validate,
    this.contextWords = const [],
    this.confidence = PrivacyConfidence.certain,
  });
}

/// De landpakketten. EU-27 plus EER, Zwitserland en het VK — decks reizen, en een
/// Nederlandse organisatie ziet Britse en Zwitserse gegevens routinematig.
final List<EuIdentifierRule> euIdentifierRules = [
  EuIdentifierRule(
    id: 'be.rijksregister',
    country: 'BE',
    pattern: RegExp(
      r'(?<!\d)\d{2}[.\s]?\d{2}[.\s]?\d{2}[-\s]?\d{3}[.\s]?\d{2}(?!\d)',
    ),
    validate: isValidBeRijksregister,
  ),
  EuIdentifierRule(
    id: 'de.steuer_id',
    country: 'DE',
    pattern: RegExp(r'(?<!\d)\d{2}[\s]?\d{3}[\s]?\d{3}[\s]?\d{3}(?!\d)'),
    validate: isValidDeSteuerId,
  ),
  EuIdentifierRule(
    id: 'fr.nir',
    country: 'FR',
    pattern: RegExp(
      r'(?<![\dA-Z])[12][\s.]?\d{2}[\s.]?\d{2}[\s.]?(?:\d{2}|2[AB])[\s.]?\d{3}'
      r'[\s.]?\d{3}[\s.]?\d{2}(?![\dA-Z])',
      caseSensitive: false,
    ),
    validate: isValidFrNir,
  ),
  EuIdentifierRule(
    id: 'es.dni',
    country: 'ES',
    pattern: RegExp(r'\b[XYZ]?\d{7,8}[-\s]?[A-Z]\b'),
    validate: isValidEsDniNie,
  ),
  EuIdentifierRule(
    id: 'pt.nif',
    country: 'PT',
    pattern: RegExp(r'(?<!\d)\d{9}(?!\d)'),
    validate: isValidPtNif,
    // Negen cijfers met een mod-11 is te zwak om alleen op af te gaan: het botst
    // met precies dezelfde ordernummers als het BSN.
    contextWords: ['nif', 'contribuinte', 'fiscal'],
  ),
  EuIdentifierRule(
    id: 'pl.pesel',
    country: 'PL',
    pattern: RegExp(r'(?<!\d)\d{11}(?!\d)'),
    validate: isValidPlPesel,
  ),
  EuIdentifierRule(
    id: 'it.codice_fiscale',
    country: 'IT',
    pattern: RegExp(r'\b[A-Z]{6}\d{2}[A-EHLMPR-T]\d{2}[A-Z]\d{3}[A-Z]\b'),
    validate: isValidItCodiceFiscale,
  ),
  EuIdentifierRule(
    id: 'hr.oib',
    country: 'HR',
    pattern: RegExp(r'(?<!\d)\d{11}(?!\d)'),
    validate: isValidHrOib,
  ),
  EuIdentifierRule(
    id: 'bg.egn',
    country: 'BG',
    pattern: RegExp(r'(?<!\d)\d{10}(?!\d)'),
    validate: isValidBgEgn,
  ),
  EuIdentifierRule(
    id: 'ro.cnp',
    country: 'RO',
    pattern: RegExp(r'(?<!\d)[1-8]\d{12}(?!\d)'),
    validate: isValidRoCnp,
  ),
  EuIdentifierRule(
    id: 'se.personnummer',
    country: 'SE',
    pattern: RegExp(r'(?<!\d)(?:19|20)?\d{6}[-+\s]?\d{4}(?!\d)'),
    validate: isValidSePersonnummer,
    // Luhn over tien cijfers is zwak: één op de tien willekeurige reeksen slaagt.
    contextWords: ['personnummer', 'personnr', 'pnr'],
  ),
  EuIdentifierRule(
    id: 'fi.hetu',
    country: 'FI',
    pattern: RegExp(r'\b\d{6}[-+A]\d{3}[0-9A-Y]\b'),
    validate: isValidFiHetu,
  ),
  EuIdentifierRule(
    id: 'ee.isikukood',
    country: 'EE',
    pattern: RegExp(r'(?<!\d)[1-6]\d{10}(?!\d)'),
    validate: isValidBalticPersonalCode,
  ),
  EuIdentifierRule(
    id: 'uk.nhs',
    country: 'GB',
    pattern: RegExp(r'(?<!\d)\d{3}[\s-]?\d{3}[\s-]?\d{4}(?!\d)'),
    validate: isValidUkNhs,
    // Mod-11 over tien cijfers is sterk, maar tien cijfers is ook een
    // telefoonnummer, een klantnummer en een ordernummer.
    contextWords: ['nhs', 'patient', 'patiënt'],
  ),
  EuIdentifierRule(
    id: 'uk.nino',
    country: 'GB',
    pattern: RegExp(r'\b[A-Z]{2}[\s]?\d{2}[\s]?\d{2}[\s]?\d{2}[\s]?[A-D]\b'),
    validate: isValidUkNino,
    // Géén checksum — dus alleen mét context, en nooit meer dan `likely`.
    contextWords: ['nino', 'national insurance', 'ni number'],
    confidence: PrivacyConfidence.likely,
  ),
  // ── Nummers met een eigen checksum ────────────────────────────────────────
  EuIdentifierRule(
    id: 'at.svnr',
    country: 'AT',
    pattern: RegExp(r'(?<!\d)\d{10}(?!\d)'),
    validate: isValidAtSvnr,
  ),
  EuIdentifierRule(
    id: 'ch.ahv',
    country: 'CH',
    // Altijd `756`, meestal met punten. Dat prefix doet hier het meeste
    // FP-werk: dertien willekeurige cijfers die óók met 756 beginnen én de
    // EAN-controle halen zijn zeldzaam.
    pattern: RegExp(r'(?<![\d.])756[. ]?\d{4}[. ]?\d{4}[. ]?\d{2}(?![\d.])'),
    validate: isValidChAhv,
  ),
  EuIdentifierRule(
    id: 'cz.rodne_cislo',
    country: 'CZ',
    // Ook met de schuine streep waarmee het meestal wordt geschreven.
    // Slowakije deelt dit nummer — het stamt uit Tsjecho-Slowakije — en valt
    // dus onder deze regel; een eigen `sk.`-id zou hetzelfde nummer dubbel
    // melden.
    pattern: RegExp(r'(?<!\d)\d{6}/?\d{4}(?!\d)'),
    validate: isValidCzSkRodneCislo,
  ),
  EuIdentifierRule(
    id: 'gr.amka',
    country: 'GR',
    pattern: RegExp(r'(?<!\d)\d{11}(?!\d)'),
    validate: isValidGrAmka,
  ),
  EuIdentifierRule(
    id: 'hu.taj',
    country: 'HU',
    pattern: RegExp(r'(?<!\d)\d{3}[ -]?\d{3}[ -]?\d{3}(?!\d)'),
    validate: isValidHuTaj,
    // Negen cijfers met alléén een mod-10, en geen datum erin: één op de tien
    // willekeurige getallen komt erdoor. Dat is zwakker dan de 11-proef van het
    // BSN, en die eist al een contextwoord.
    //
    // Zonder die eis is dit geen theoretisch risico maar een gemeten ramp: de
    // vals-positievencorpus ging meteen af op `Klantnummer 847362910` en
    // `Ordernummer 202512345`. Erger nog — omdat een identificator als
    // persoonskoppeling telt, tilde elke valse treffer óók alle artikel
    // 9-trefwoorden op diezelfde slide naar `zeker`. Eén zwakke regel, en de
    // halve scanner gaat mee.
    contextWords: ['taj', 'társadalombiztosítási', 'tb-szám', 'taj-szám'],
    confidence: PrivacyConfidence.likely,
  ),
  EuIdentifierRule(
    id: 'ie.pps',
    country: 'IE',
    pattern: RegExp(r'\b\d{7}[A-W]{1,2}\b'),
    validate: isValidIePps,
  ),
  EuIdentifierRule(
    id: 'no.fodselsnummer',
    country: 'NO',
    pattern: RegExp(r'(?<!\d)\d{6}[ ]?\d{5}(?!\d)'),
    validate: isValidNoFodselsnummer,
  ),
  EuIdentifierRule(
    id: 'si.emso',
    country: 'SI',
    pattern: RegExp(r'(?<!\d)\d{13}(?!\d)'),
    validate: isValidSiEmso,
  ),
  // ── En het nummer zonder checksum ─────────────────────────────────────────
  EuIdentifierRule(
    id: 'dk.cpr',
    country: 'DK',
    pattern: RegExp(r'(?<!\d)\d{6}-?\d{4}(?!\d)'),
    // De mod-11-controle is in 2007 losgelaten omdat de nummers opraakten, dus
    // een geldig CPR hoeft hem niet te halen. Erop controleren zou echte
    // nummers afwijzen — de verkeerde fout. Wat overblijft is de datum, en die
    // is te zwak om alleen op af te gaan.
    validate: isValidDkCpr,
    contextWords: ['cpr', 'cpr-nr', 'personnummer', 'cprnummer'],
    confidence: PrivacyConfidence.likely,
  ),
];

/// De landcodes waarvoor er regels zijn.
Set<String> get euRuleCountries => {
  for (final rule in euIdentifierRules) rule.country,
};
