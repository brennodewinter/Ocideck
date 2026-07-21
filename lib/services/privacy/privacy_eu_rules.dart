// De Europese landpakketten.
//
// Waarom "heel Europa" standaard aan mag staan: ruim twintig van de dertig
// nummers zijn zelfvaliderend. Een checksum kóst geen precisie, hij wint
// precisie — het aanzetten van het Kroatische OIB maakt de scanner niet luider,
// alleen breder. De ruis zat nooit in de checksum-nummers maar in de handvol
// zónder, en díé zijn contextpoort-gebonden, precies zoals het BSN dat is.
//
// Elke regel is data: id, land, patroon, validatie, en of er een contextwoord
// nodig is. Een land toevoegen is één regel in de tabel.

import '../../models/privacy_finding.dart';
import 'privacy_checksums_eu.dart';
import 'privacy_national_rule.dart';

/// De landpakketten. EU-27 plus EER, Zwitserland en het VK — decks reizen, en een
/// Nederlandse organisatie ziet Britse en Zwitserse gegevens routinematig.
final List<NationalIdentifierRule> euIdentifierRules = [
  NationalIdentifierRule(
    id: 'be.rijksregister',
    country: 'BE',
    pattern: RegExp(
      r'(?<!\d)\d{2}[.\s]?\d{2}[.\s]?\d{2}[-\s]?\d{3}[.\s]?\d{2}(?!\d)',
    ),
    validate: isValidBeRijksregister,
  ),
  NationalIdentifierRule(
    id: 'de.steuer_id',
    country: 'DE',
    pattern: RegExp(r'(?<!\d)\d{2}[\s]?\d{3}[\s]?\d{3}[\s]?\d{3}(?!\d)'),
    validate: isValidDeSteuerId,
  ),
  NationalIdentifierRule(
    id: 'fr.nir',
    country: 'FR',
    pattern: RegExp(
      r'(?<![\dA-Z])[12][\s.]?\d{2}[\s.]?\d{2}[\s.]?(?:\d{2}|2[AB])[\s.]?\d{3}'
      r'[\s.]?\d{3}[\s.]?\d{2}(?![\dA-Z])',
      caseSensitive: false,
    ),
    validate: isValidFrNir,
  ),
  NationalIdentifierRule(
    id: 'es.dni',
    country: 'ES',
    pattern: RegExp(r'\b[XYZ]?\d{7,8}[-\s]?[A-Z]\b'),
    validate: isValidEsDniNie,
  ),
  NationalIdentifierRule(
    id: 'pt.nif',
    country: 'PT',
    pattern: RegExp(r'(?<!\d)\d{9}(?!\d)'),
    validate: isValidPtNif,
    // Negen cijfers met een mod-11 is te zwak om alleen op af te gaan: het botst
    // met precies dezelfde ordernummers als het BSN.
    contextWords: ['nif', 'contribuinte', 'fiscal'],
  ),
  NationalIdentifierRule(
    id: 'pl.pesel',
    country: 'PL',
    pattern: RegExp(r'(?<!\d)\d{11}(?!\d)'),
    validate: isValidPlPesel,
  ),
  NationalIdentifierRule(
    id: 'it.codice_fiscale',
    country: 'IT',
    pattern: RegExp(r'\b[A-Z]{6}\d{2}[A-EHLMPR-T]\d{2}[A-Z]\d{3}[A-Z]\b'),
    validate: isValidItCodiceFiscale,
  ),
  NationalIdentifierRule(
    id: 'hr.oib',
    country: 'HR',
    pattern: RegExp(r'(?<!\d)\d{11}(?!\d)'),
    validate: isValidHrOib,
  ),
  NationalIdentifierRule(
    id: 'bg.egn',
    country: 'BG',
    pattern: RegExp(r'(?<!\d)\d{10}(?!\d)'),
    validate: isValidBgEgn,
  ),
  NationalIdentifierRule(
    id: 'ro.cnp',
    country: 'RO',
    pattern: RegExp(r'(?<!\d)[1-8]\d{12}(?!\d)'),
    validate: isValidRoCnp,
  ),
  NationalIdentifierRule(
    id: 'se.personnummer',
    country: 'SE',
    pattern: RegExp(r'(?<!\d)(?:19|20)?\d{6}[-+\s]?\d{4}(?!\d)'),
    validate: isValidSePersonnummer,
    // Luhn over tien cijfers is zwak: één op de tien willekeurige reeksen slaagt.
    contextWords: ['personnummer', 'personnr', 'pnr'],
  ),
  NationalIdentifierRule(
    id: 'fi.hetu',
    country: 'FI',
    pattern: RegExp(r'\b\d{6}[-+A]\d{3}[0-9A-Y]\b'),
    validate: isValidFiHetu,
  ),
  NationalIdentifierRule(
    id: 'ee.isikukood',
    country: 'EE',
    pattern: RegExp(r'(?<!\d)[1-6]\d{10}(?!\d)'),
    validate: isValidBalticPersonalCode,
  ),
  NationalIdentifierRule(
    id: 'lv.pk',
    country: 'LV',
    pattern: RegExp(r'(?<!\d)\d{6}-?\d{5}(?!\d)'),
    validate: isValidLvPersonasKods,
  ),
  NationalIdentifierRule(
    id: 'uk.nhs',
    country: 'GB',
    pattern: RegExp(r'(?<!\d)\d{3}[\s-]?\d{3}[\s-]?\d{4}(?!\d)'),
    validate: isValidUkNhs,
    // Mod-11 over tien cijfers is sterk, maar tien cijfers is ook een
    // telefoonnummer, een klantnummer en een ordernummer.
    contextWords: ['nhs', 'patient', 'patiënt'],
  ),
  NationalIdentifierRule(
    id: 'uk.nino',
    country: 'GB',
    pattern: RegExp(r'\b[A-Z]{2}[\s]?\d{2}[\s]?\d{2}[\s]?\d{2}[\s]?[A-D]\b'),
    validate: isValidUkNino,
    // Géén checksum — dus alleen mét context, en nooit meer dan `likely`.
    contextWords: ['nino', 'national insurance', 'ni number'],
    confidence: PrivacyConfidence.likely,
  ),
  // ── Nummers met een eigen checksum ────────────────────────────────────────
  NationalIdentifierRule(
    id: 'at.svnr',
    country: 'AT',
    pattern: RegExp(r'(?<!\d)\d{10}(?!\d)'),
    validate: isValidAtSvnr,
  ),
  NationalIdentifierRule(
    id: 'ch.ahv',
    country: 'CH',
    // Altijd `756`, meestal met punten. Dat prefix doet hier het meeste
    // FP-werk: dertien willekeurige cijfers die óók met 756 beginnen én de
    // EAN-controle halen zijn zeldzaam.
    pattern: RegExp(r'(?<![\d.])756[. ]?\d{4}[. ]?\d{4}[. ]?\d{2}(?![\d.])'),
    validate: isValidChAhv,
  ),
  NationalIdentifierRule(
    id: 'cz.rodne_cislo',
    country: 'CZ',
    // Ook met de schuine streep waarmee het meestal wordt geschreven.
    // Slowakije deelt dit nummer — het stamt uit Tsjecho-Slowakije — en valt
    // dus onder deze regel; een eigen `sk.`-id zou hetzelfde nummer dubbel
    // melden.
    pattern: RegExp(r'(?<!\d)\d{6}/?\d{4}(?!\d)'),
    validate: isValidCzSkRodneCislo,
  ),
  NationalIdentifierRule(
    id: 'gr.amka',
    country: 'GR',
    pattern: RegExp(r'(?<!\d)\d{11}(?!\d)'),
    validate: isValidGrAmka,
  ),
  NationalIdentifierRule(
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
  NationalIdentifierRule(
    id: 'ie.pps',
    country: 'IE',
    pattern: RegExp(r'\b\d{7}[A-W]{1,2}\b'),
    validate: isValidIePps,
  ),
  NationalIdentifierRule(
    id: 'no.fodselsnummer',
    country: 'NO',
    pattern: RegExp(r'(?<!\d)\d{6}[ ]?\d{5}(?!\d)'),
    validate: isValidNoFodselsnummer,
  ),
  NationalIdentifierRule(
    id: 'is.kennitala',
    country: 'IS',
    // Meestal met een streepje na de zesde positie, soms zonder.
    pattern: RegExp(r'(?<!\d)\d{6}[-\s]?\d{4}(?!\d)'),
    validate: isValidIsKennitala,
  ),
  NationalIdentifierRule(
    id: 'si.emso',
    country: 'SI',
    pattern: RegExp(r'(?<!\d)\d{13}(?!\d)'),
    validate: isValidSiEmso,
  ),
  // ── En het nummer zonder checksum ─────────────────────────────────────────
  NationalIdentifierRule(
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
  // ── Nederland ─────────────────────────────────────────────────────────────
  //
  // Het BSN zelf zit niet hier maar als eigen detector in `privacy_scanner.dart`,
  // omdat het twee zekerheden kent (met en zonder contextwoord). Deze zes zijn
  // de nummers eromheen: één met een echte checksum, vijf zonder.
  //
  // Dat verschil is het hele verhaal. Alleen `nl.btw_id_legacy` mag zonder
  // contextwoord vuren, want daar draagt de 11-proef het bewijs. De andere vijf
  // zijn kale cijferreeksen — acht, tien of elf cijfers — en die staan met
  // duizenden tegelijk in elk zakelijk deck. Zonder contextpoort zou elk
  // ordernummer een treffer zijn, en dan zet de gebruiker de controle uit.
  NationalIdentifierRule(
    id: 'nl.btw_id_legacy',
    country: 'NL',
    pattern: RegExp(r'\bNL\d{9}B\d{2}\b', caseSensitive: false),
    // De 11-proef doet hier écht werk: hij scheidt het oude nummer (dat het BSN
    // ís) van het nieuwe (dat niets zegt). Geen contextwoord nodig — de vorm
    // `NL…B..` komt nergens anders voor.
    validate: isValidNlBtwIdLegacy,
    confidence: PrivacyConfidence.certain,
  ),
  NationalIdentifierRule(
    id: 'nl.vnummer',
    country: 'NL',
    // Tien cijfers beginnend met een 2. Er is geen gepubliceerde checksum, dus
    // de vorm draagt niets: `2024123456` is net zo goed een ordernummer.
    pattern: RegExp(r'(?<!\d)2\d{9}(?!\d)'),
    contextWords: [
      'v-nummer',
      'vnummer',
      'v nummer',
      'vreemdeling',
      'vreemdelingennummer',
      'ind',
    ],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'nl.anummer',
    country: 'NL',
    pattern: RegExp(r'(?<!\d)\d{10}(?!\d)'),
    // **Bewust geen checksum.** De catalogus schreef "11-proef-variant" voor,
    // maar geen publieke bron van RvIG koppelt een controlegetal aan het
    // A-nummer; wat wél gedocumenteerd is, is de 11-proef over tien cijfers voor
    // *bankrekeningnummers*. Die hier toepassen zou een gok zijn, en de fout
    // valt de verkeerde kant op: een te strenge controle wijst échte A-nummers
    // af, en een gemist persoonsnummer is duurder dan een melding te veel.
    // Zelfde afweging als bij `dk.cpr` hierboven.
    //
    // Wat overblijft is tien kale cijfers, dus de contextpoort draagt alles.
    contextWords: ['a-nummer', 'anummer', 'a nummer', 'administratienummer'],
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'nl.big',
    country: 'NL',
    pattern: RegExp(r'(?<!\d)\d{11}(?!\d)'),
    contextWords: ['big-nummer', 'bignummer', 'big nummer', 'big-register'],
    // Een BIG-nummer identificeert een zorgverlener in zijn beroepsrol. Dat is
    // een persoonsgegeven, maar geen bijzonder persoonsgegeven: het register is
    // openbaar en juist bedoeld om geraadpleegd te worden. Vandaar `likely` en
    // niet hoger, ook mét contextwoord.
    confidence: PrivacyConfidence.likely,
  ),
  NationalIdentifierRule(
    id: 'nl.agb',
    country: 'NL',
    pattern: RegExp(r'(?<!\d)\d{8}(?!\d)'),
    contextWords: ['agb', 'agb-code', 'agbcode', 'vektis'],
    // Acht cijfers is de kortste reeks in dit hele bestand, en dus de ruizigste:
    // elk artikelnummer, elke datum zonder scheidingstekens (`20250131`) heeft
    // deze vorm. Een AGB-code hoort bovendien vaak bij een práktijk en niet bij
    // een persoon. Daarom `possible` — zichtbaar in het paneel, maar het
    // onderbreekt niemand en het escaleert niets.
    confidence: PrivacyConfidence.possible,
  ),
  NationalIdentifierRule(
    id: 'nl.pv_nummer',
    country: 'NL',
    // Er is geen landelijk formaat: elk korps schrijft het anders, en BVH-,
    // mutatie- en PV-nummers lopen door elkaar. Wat ze delen is een reeks van
    // acht tot twintig cijfers, eventueel met streepjes, en een letterprefix dat
    // er soms voor staat (`PL1300-…`). Dit patroon accepteert allebei.
    pattern: RegExp(
      r'\b(?:[A-Z]{2}\d{4}[- ])?\d{4,12}(?:-\d{1,8}){0,2}\b',
      caseSensitive: false,
    ),
    contextWords: [
      'proces-verbaal',
      'procesverbaal',
      'pv-nummer',
      'pvnummer',
      'bvh',
      'mutatienummer',
      'dossiernummer politie',
    ],
    // Een PV-nummer verwijst naar een strafrechtelijk dossier, en dat is zwaar.
    // Maar het patroon is zó ruim dat de contextpoort al het werk doet, en een
    // los nummer met "dossier" ernaast kan van alles zijn. Vandaar `possible`.
    //
    // Let op: dit landt in de familie `identifier`, niet in `criminal` — de lus
    // in `privacy_scanner.dart` zet elke nationale regel op `identifier`. Wie
    // dit ooit onder de strafrechtelijke familie wil hangen, moet daar beginnen
    // en niet hier.
    confidence: PrivacyConfidence.possible,
  ),
];

/// De landcodes waarvoor er regels zijn.
Set<String> get euRuleCountries => {
  for (final rule in euIdentifierRules) rule.country,
};
