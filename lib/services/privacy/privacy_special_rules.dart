// Bijzondere persoonsgegevens (AVG art. 9 en 10).
//
// Hier zit de grootste vals-positieven-val van de hele scanner, en het is niet
// eens een subtiele: een slide *óver* de AVG noemt "gezondheidsgegevens" zonder
// er een te bevatten. Een privacyles, een DPIA-presentatie, een
// verwerkingsregister — allemaal vol met precies de woorden die we zoeken. Een
// trefwoordscanner die daarop waarschuwt, is binnen een dag uitgezet.
//
// ── De co-occurrence-escalator ───────────────────────────────────────────────
//
// De oplossing is dat een trefwoord op zichzelf níéts meldt dat de gebruiker
// onderbreekt. "Diagnose", "vakbond", "verdachte" leveren hooguit een
// informatieve hint op.
//
// Pas wanneer op dezelfde slide óók een DIRECT IDENTIFICEREND gegeven staat — een
// BSN, een e-mailadres, een nationaal nummer — gaat de melding omhoog: dan is het
// bijzondere gegeven herleidbaar tot een persoon, en dát is precies wat artikel 9
// beschermt.
//
//   slide over privacywetgeving:      "gezondheidsgegevens"          → stil
//   dossierslide:  "Jan, BSN 728398242, diagnose F32.1"              → melding
//
// Zonder die koppeling is trefwoorddetectie ruis. Mét die koppeling vangt ze
// precies het geval waar het om gaat.
//
// ── Wat we bewust NIET meeleveren ────────────────────────────────────────────
//
// Politieke opvattingen, etnische afkomst en seksuele geaardheid staan in het
// ontwerp (§3-G) als "standaard uit". Ze zitten hier nog niet in, en dat is een
// keuze: een slide over diversiteitsbeleid gaat *over* etniciteit zonder etnische
// gegevens te bevatten, en zonder een per-regel-uitschakelaar in de instellingen
// (fase 7) is die FP-ratio niet te verdedigen. Beter geen regel dan een regel die
// de hele controle ongeloofwaardig maakt.

import '../../models/privacy_finding.dart';

/// Eén trefwoordfamilie uit artikel 9 of 10.
class SpecialCategoryRule {
  final String id;

  /// De trefwoorden, meertalig. Data, geen UI — deze woorden worden nooit
  /// getoond, alleen gematcht, dus ze gaan niet door de l10n heen.
  final List<String> keywords;

  const SpecialCategoryRule(this.id, this.keywords);
}

/// De trefwoordfamilies.
///
/// NL/EN/DE/FR/ES. De lijst is bewust uit te breiden zonder code te raken: een
/// taal toevoegen is woorden toevoegen.
const List<SpecialCategoryRule> specialCategoryRules = [
  SpecialCategoryRule('special.health', [
    'diagnose',
    'diagnosis',
    'diagnostic',
    'diagnóstico',
    'medicatie',
    'medication',
    'medikation',
    'médicament',
    'medicación',
    'ziekteverzuim',
    'sick leave',
    'krankmeldung',
    'arrêt maladie',
    'zwangerschap',
    'pregnancy',
    'schwangerschaft',
    'grossesse',
    'embarazo',
    'psychiatrisch',
    'psychiatric',
    'psychiatrische',
    'verslaving',
    'addiction',
    'sucht',
    'adicción',
    'ziektebeeld',
    'medisch dossier',
    'medical record',
    'patientendossier',
    'arbeidsongeschikt',
    'burn-out',
    'burnout',
    'depressie',
    'depression',
    'depresión',
    'kanker',
    'cancer',
    'krebs',
    'cáncer',
    'hiv',
    'diabetes',
    'ggz',
  ]),
  SpecialCategoryRule('special.criminal', [
    'verdachte',
    'suspect',
    'verdächtige',
    'sospechoso',
    'veroordeling',
    'conviction',
    'verurteilung',
    'condamnation',
    'condena',
    'strafblad',
    'criminal record',
    'vorstrafe',
    'casier judiciaire',
    'proces-verbaal',
    'aanhouding',
    'arrest',
    'festnahme',
    'detención',
    'tenlastelegging',
    'strafrechtelijk',
    'misdrijf',
    'delict',
    'gedetineerde',
    'reclassering',
    'vog',
  ]),
  SpecialCategoryRule('special.religion', [
    'geloofsovertuiging',
    'levensovertuiging',
    'religieuze overtuiging',
    'religious belief',
    'religionszugehörigkeit',
    'confession religieuse',
    'kerkgenootschap',
    'moskeebezoek',
    'geloofsgemeenschap',
  ]),
  SpecialCategoryRule('special.union', [
    'vakbond',
    'vakbondslid',
    'trade union',
    'gewerkschaft',
    'syndicat',
    'sindicato',
    'union membership',
    'lid van de fnv',
    'lid van het cnv',
  ]),
  // ── Standaard uit (zie defaultDisabledPrivacyRules) ───────────────────────
  //
  // Deze drie zijn niet minder belangrijk — het zijn juist de zwaarste
  // categorieën — maar hun trefwoorden komen in gewone zakelijke taal veel te
  // vaak voor. Ze staan er wél, en zijn met één vinkje aan te zetten.
  SpecialCategoryRule('special.politics', [
    'politieke voorkeur',
    'politieke overtuiging',
    'stemde op',
    'lid van de partij',
    'political opinion',
    'politische meinung',
    'opinion politique',
    'opinión política',
  ]),
  SpecialCategoryRule('special.ethnicity', [
    'etnische afkomst',
    'etnische achtergrond',
    'raciale afkomst',
    'ethnic origin',
    'racial origin',
    'ethnische herkunft',
    'origine ethnique',
    'origen étnico',
  ]),
  SpecialCategoryRule('special.sexlife', [
    'seksuele geaardheid',
    'seksuele voorkeur',
    'sexual orientation',
    'sexuelle orientierung',
    'orientation sexuelle',
    'orientación sexual',
  ]),

  SpecialCategoryRule('special.biometric', [
    'vingerafdruk',
    'fingerprint',
    'fingerabdruck',
    'empreinte digitale',
    'huella dactilar',
    'irisscan',
    'iris scan',
    'gezichtsherkenning',
    'facial recognition',
    'gesichtserkennung',
    'stemprofiel',
    'voiceprint',
    'biometrisch',
    'biometric',
    'biometrische',
  ]),
];

/// Genetische gegevens herkennen we aan hun notatie, niet aan een trefwoord.
///
/// dbSNP-identificatoren (`rs334`) en HGVS-varianten (`c.1521_1523delCTT`,
/// `p.Val600Glu`) zijn onmiskenbaar genetisch en komen in gewone tekst niet voor.
/// Dat maakt ze een van de weinige art. 9-regels met een laag FP-risico.
final List<({String id, RegExp pattern})> geneticPatterns = [
  // dbSNP: rs334 (sikkelcel), rs1801133. Drie cijfers is het minimum — `rs12`
  // zou te veel gewone tekst raken.
  (id: 'special.genetic', pattern: RegExp(r'\brs\d{3,}\b')),
  // HGVS op DNA-niveau: c.35G>A, c.1521_1523delCTT.
  (
    id: 'special.genetic',
    pattern: RegExp(
      r'\b[cgmn]\.\d+[+\-_\d]*(?:[ACGT]>[ACGT]|del[ACGT]*|dup[ACGT]*|ins[ACGT]*)\b',
    ),
  ),
  // HGVS op eiwitniveau: p.Val600Glu. Bewust met de drieletterige aminozuurcode,
  // want `p.42` is gewoon een paginanummer.
  (
    id: 'special.genetic',
    pattern: RegExp(r'\bp\.[A-Z][a-z]{2}\d+(?:[A-Z][a-z]{2}|\*|fs|=)\b'),
  ),
];

/// Het Nederlandse parketnummer: `01/234567-19`.
///
/// Strafrechtelijke gegevens (art. 10), en een formaat dat in gewone tekst niet
/// voorkomt. Geen checksum, dus nooit meer dan `waarschijnlijk` — maar het
/// patroon is distinctief genoeg om zonder contextwoord te vuren.
final RegExp parketnummerPattern = RegExp(r'\b\d{2}/\d{6}-\d{2}\b');

/// De mededeling waarin een treffer staat: van regelbegin tot regeleinde.
///
/// Dit is de reikwijdte waarmee een bijzonder persoonsgegeven wordt weggehaald,
/// en de reden is dat een bijzonder gegeven geen wóórd is maar een uitspraak.
/// Lak je alleen het trefwoord weg, dan blijft er dit staan:
///
///     Marieke de Vries meldde zich ziek met een ████████
///
/// De naam staat er nog, de ziekmelding staat er nog, en `diabetes-` staat er
/// zelfs letterlijk nog. Er is niets weggehaald — er is een woord bedekt. Dat is
/// precies de fout die dit hele ontwerp wil voorkomen: niet beschikbaar is niet
/// beschikbaar.
///
/// Waarom de regel en niet de zin? Omdat zinsgrenzen niet te vertrouwen zijn.
/// "Zie dhr. Jansen. De diagnose is diabetes." splitst een puntdetector op de
/// afkorting, en dan valt de naam búíten de redactie — en dat is de gevaarlijke
/// kant om ernaast te zitten. Een regel is wat de auteur als één mededeling heeft
/// opgeschreven: één bullet, één tabelcel, één alinea. Te ruim redigeren is
/// hinderlijk; te krap redigeren is een lek.
({int start, int end}) statementSpan(String text, int start, int end) {
  var from = text.lastIndexOf('\n', start > 0 ? start - 1 : 0);
  from = from < 0 ? 0 : from + 1;

  var to = text.indexOf('\n', end);
  if (to < 0) to = text.length;

  // Omliggende witruimte hoort niet bij de mededeling: die meenemen zou het blok
  // laten kleven aan het woord ervoor.
  while (from < start && _isSpace(text.codeUnitAt(from))) {
    from++;
  }
  while (to > end && _isSpace(text.codeUnitAt(to - 1))) {
    to--;
  }
  return (start: from, end: to);
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;

/// Welke bevindingen tellen als "direct identificerend" voor de escalator.
///
/// Een BSN, een nationaal nummer, een e-mailadres: gegevens die één persoon
/// aanwijzen. Een IBAN of een API-sleutel niet — die zeggen niets over wíé.
bool identifiesAPerson(PrivacyFinding finding) {
  if (finding.confidence != PrivacyConfidence.certain) return false;
  return finding.family == PrivacyFamily.identifier ||
      finding.ruleId == 'contact.email';
}
