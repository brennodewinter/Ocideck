// Het gebundelde lexicon voor artikel 9 en 10.
//
// Dit bestand is de opvolger van de kale trefwoordlijsten die hier tot fase 12
// stonden. Inhoudelijk zijn het dezelfde woorden; wat erbij is gekomen is dat
// elke term nu zégt hoe hij gezocht wil worden, in welke taal hij staat, en hoe
// specifiek hij is. Zie `privacy_lexicon.dart` voor waarom dat afleiden uit de
// termlengte niet houdbaar was.
//
// ── Wat hier bewust nog níét in zit ─────────────────────────────────────────
//
// De taaldekking is scheef en dat is met opzet zichtbaar in plaats van verstopt.
// Nederlands is rijk, Engels redelijk, Duits/Frans/Spaans dun, en de overige 25
// talen waarin de interface draait hebben géén lexicon. Fase 13 vult dat aan uit
// EuroVoc en ORDO, en bouwt de meter die het aan de gebruiker vertelt — want een
// groene balk die "niets gevonden" zegt terwijl er voor die taal niets te vinden
// vált, is erger dan geen controle.
//
// Homosaurus (seksuele geaardheid), de IISG-religietaxonomieën en de Thesaurus
// Zorg en Welzijn zouden dit bestand in één klap tien keer zo rijk maken. Ze
// staan er niet in omdat hun licentie niet rond is — zie §13.8. Kosteloos is
// niet hetzelfde als herdistribueerbaar, en dat onderscheid is precies waar
// SNOMED CT NL op afknapt.

import '../../models/privacy_lexicon.dart';

/// Korter schrijven wat anders zes regels per term kost.
PrivacyLexiconEntry _e(
  String term,
  String category,
  String lang, {
  PrivacyTermMatch match = PrivacyTermMatch.prefix,
  int weight = 3,
  PrivacyLexiconRole role = PrivacyLexiconRole.indicator,
}) => PrivacyLexiconEntry(
  term: term,
  category: category,
  lang: lang,
  match: match,
  weight: weight,
  role: role,
);

/// Gezondheid (AVG art. 9).
///
/// De gewichten doen hier het meeste werk. `diagnose` is een woord dat in elke
/// projectvergadering valt ("de diagnose van het probleem"), en staat dus laag;
/// `ziektebeeld` of een concrete aandoening staat hoog, want die woorden hebben
/// geen tweede betekenis.
final List<PrivacyLexiconEntry> _healthTerms = [
  _e('diagnose', 'special.health', 'nl', weight: 2),
  _e('diagnosis', 'special.health', 'en', weight: 2),
  _e('diagnostic', 'special.health', 'fr', weight: 2),
  _e('diagnóstico', 'special.health', 'es', weight: 2),
  _e('medicatie', 'special.health', 'nl', weight: 4),
  _e('medication', 'special.health', 'en', weight: 4),
  _e('medikation', 'special.health', 'de', weight: 4),
  _e('médicament', 'special.health', 'fr', weight: 4),
  _e('medicación', 'special.health', 'es', weight: 4),
  _e(
    'ziekteverzuim',
    'special.health',
    'nl',
    match: PrivacyTermMatch.compound,
    weight: 5,
  ),
  _e(
    'sick leave',
    'special.health',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'krankmeldung',
    'special.health',
    'de',
    match: PrivacyTermMatch.compound,
    weight: 5,
  ),
  _e(
    'arrêt maladie',
    'special.health',
    'fr',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'zwangerschap',
    'special.health',
    'nl',
    match: PrivacyTermMatch.compound,
    weight: 4,
  ),
  _e('pregnancy', 'special.health', 'en', weight: 4),
  _e(
    'schwangerschaft',
    'special.health',
    'de',
    match: PrivacyTermMatch.compound,
    weight: 4,
  ),
  _e('grossesse', 'special.health', 'fr', weight: 4),
  _e('embarazo', 'special.health', 'es', weight: 4),
  _e('psychiatrisch', 'special.health', 'nl', weight: 5),
  _e('psychiatric', 'special.health', 'en', weight: 5),
  _e('verslaving', 'special.health', 'nl', weight: 5),
  _e('addiction', 'special.health', 'en', weight: 5),
  _e('sucht', 'special.health', 'de', match: PrivacyTermMatch.word, weight: 3),
  _e('adicción', 'special.health', 'es', weight: 5),
  _e(
    'ziektebeeld',
    'special.health',
    'nl',
    match: PrivacyTermMatch.compound,
    weight: 5,
  ),
  _e(
    'medisch dossier',
    'special.health',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'medical record',
    'special.health',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'patientendossier',
    'special.health',
    'de',
    match: PrivacyTermMatch.compound,
    weight: 5,
  ),
  _e('arbeidsongeschikt', 'special.health', 'nl', weight: 5),
  // Concrete aandoeningen: de tekst ís hier het gegeven, niet een aanwijzing
  // ernaar. Vandaar de rol `value` — bij redactie moeten deze woorden zélf weg,
  // ook zonder dat de escalator het bereik verbreedt.
  _e(
    'burn-out',
    'special.health',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'burnout',
    'special.health',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'depressie',
    'special.health',
    'nl',
    weight: 4,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'depression',
    'special.health',
    'en',
    weight: 4,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'depresión',
    'special.health',
    'es',
    weight: 4,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'kanker',
    'special.health',
    'nl',
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'cancer',
    'special.health',
    'en',
    weight: 4,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'krebs',
    'special.health',
    'de',
    match: PrivacyTermMatch.word,
    weight: 4,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'cáncer',
    'special.health',
    'es',
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'hiv',
    'special.health',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'diabetes',
    'special.health',
    'nl',
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e('ggz', 'special.health', 'nl', match: PrivacyTermMatch.word, weight: 5),
];

/// Strafrechtelijke gegevens (AVG art. 10).
final List<PrivacyLexiconEntry> _criminalTerms = [
  // De stam, niet de verbogen vorm: met voorvoegselmatching dekt `verdacht` ook
  // `verdachte`, `verdachten` en `verdachtmaking`. Stond hier eerst als
  // `verdachte`, en daardoor miste "wordt verdacht van diefstal" — de meest
  // voorkomende formulering — volledig.
  _e('verdacht', 'special.criminal', 'nl', weight: 4),
  _e('suspect', 'special.criminal', 'en', weight: 3),
  _e('verdächtige', 'special.criminal', 'de', weight: 4),
  _e('sospechoso', 'special.criminal', 'es', weight: 4),
  // De stam en niet `veroordeling`, om precies de reden die §13.1 al voor
  // `verdacht` optekende: de zelfstandignaamwoordsvorm mist de werkwoordsvorm,
  // en "werd veroordeeld" is de gewonere formulering van de twee. Dezelfde fout,
  // een regel lager — gevonden doordat de rolherkenningstest er niet op aansloeg.
  _e('veroordeel', 'special.criminal', 'nl', weight: 5),
  _e('veroordeling', 'special.criminal', 'nl', weight: 5),
  _e('conviction', 'special.criminal', 'en', weight: 3),
  _e('verurteilung', 'special.criminal', 'de', weight: 5),
  _e('condamnation', 'special.criminal', 'fr', weight: 5),
  _e('condena', 'special.criminal', 'es', weight: 4),
  _e(
    'strafblad',
    'special.criminal',
    'nl',
    match: PrivacyTermMatch.compound,
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'criminal record',
    'special.criminal',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'vorstrafe',
    'special.criminal',
    'de',
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'casier judiciaire',
    'special.criminal',
    'fr',
    match: PrivacyTermMatch.word,
    weight: 5,
    role: PrivacyLexiconRole.value,
  ),
  _e(
    'proces-verbaal',
    'special.criminal',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e('aanhouding', 'special.criminal', 'nl', weight: 4),
  // `arrest` is zes letters en zou met de oude lengteregel als voorvoegsel
  // matchen. Maar het is óók een uitspraak van de Hoge Raad, en juist in een
  // juridisch deck staat dat woord overal. Heel woord dus, en laag gewicht.
  _e(
    'arrest',
    'special.criminal',
    'en',
    match: PrivacyTermMatch.word,
    weight: 1,
  ),
  _e('festnahme', 'special.criminal', 'de', weight: 4),
  _e('detención', 'special.criminal', 'es', weight: 4),
  _e('tenlastelegging', 'special.criminal', 'nl', weight: 5),
  _e('strafrechtelijk', 'special.criminal', 'nl', weight: 4),
  _e('misdrijf', 'special.criminal', 'nl', weight: 4),
  _e('delict', 'special.criminal', 'nl', weight: 4),
  _e('gedetineerde', 'special.criminal', 'nl', weight: 5),
  _e('reclassering', 'special.criminal', 'nl', weight: 5),
  _e('vog', 'special.criminal', 'nl', match: PrivacyTermMatch.word, weight: 4),
];

/// Religie, vakbond, en de drie categorieën die standaard uit staan.
final List<PrivacyLexiconEntry> _beliefTerms = [
  _e('geloofsovertuiging', 'special.religion', 'nl', weight: 5),
  _e('levensovertuiging', 'special.religion', 'nl', weight: 5),
  _e(
    'religieuze overtuiging',
    'special.religion',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'religious belief',
    'special.religion',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e('religionszugehörigkeit', 'special.religion', 'de', weight: 5),
  _e(
    'confession religieuse',
    'special.religion',
    'fr',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e('kerkgenootschap', 'special.religion', 'nl', weight: 5),
  _e('moskeebezoek', 'special.religion', 'nl', weight: 5),
  _e('geloofsgemeenschap', 'special.religion', 'nl', weight: 4),

  _e(
    'vakbond',
    'special.union',
    'nl',
    match: PrivacyTermMatch.compound,
    weight: 4,
  ),
  _e('vakbondslid', 'special.union', 'nl', weight: 5),
  _e(
    'trade union',
    'special.union',
    'en',
    match: PrivacyTermMatch.word,
    weight: 4,
  ),
  _e(
    'gewerkschaft',
    'special.union',
    'de',
    match: PrivacyTermMatch.compound,
    weight: 4,
  ),
  _e('syndicat', 'special.union', 'fr', weight: 4),
  _e('sindicato', 'special.union', 'es', weight: 4),
  _e(
    'union membership',
    'special.union',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'lid van de fnv',
    'special.union',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'lid van het cnv',
    'special.union',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),

  _e(
    'politieke voorkeur',
    'special.politics',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'politieke overtuiging',
    'special.politics',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'stemde op',
    'special.politics',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 4,
  ),
  _e(
    'lid van de partij',
    'special.politics',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'political opinion',
    'special.politics',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'politische meinung',
    'special.politics',
    'de',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'opinion politique',
    'special.politics',
    'fr',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'opinión política',
    'special.politics',
    'es',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),

  _e(
    'etnische afkomst',
    'special.ethnicity',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'etnische achtergrond',
    'special.ethnicity',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'raciale afkomst',
    'special.ethnicity',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'ethnic origin',
    'special.ethnicity',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'racial origin',
    'special.ethnicity',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'ethnische herkunft',
    'special.ethnicity',
    'de',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'origine ethnique',
    'special.ethnicity',
    'fr',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'origen étnico',
    'special.ethnicity',
    'es',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),

  _e(
    'seksuele geaardheid',
    'special.sexlife',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'seksuele voorkeur',
    'special.sexlife',
    'nl',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'sexual orientation',
    'special.sexlife',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'sexuelle orientierung',
    'special.sexlife',
    'de',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'orientation sexuelle',
    'special.sexlife',
    'fr',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'orientación sexual',
    'special.sexlife',
    'es',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
];

/// Biometrie.
final List<PrivacyLexiconEntry> _biometricTerms = [
  _e(
    'vingerafdruk',
    'special.biometric',
    'nl',
    match: PrivacyTermMatch.compound,
    weight: 5,
  ),
  _e('fingerprint', 'special.biometric', 'en', weight: 5),
  _e(
    'fingerabdruck',
    'special.biometric',
    'de',
    match: PrivacyTermMatch.compound,
    weight: 5,
  ),
  _e(
    'empreinte digitale',
    'special.biometric',
    'fr',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e(
    'huella dactilar',
    'special.biometric',
    'es',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e('irisscan', 'special.biometric', 'nl', weight: 5),
  _e(
    'iris scan',
    'special.biometric',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e('gezichtsherkenning', 'special.biometric', 'nl', weight: 5),
  _e(
    'facial recognition',
    'special.biometric',
    'en',
    match: PrivacyTermMatch.word,
    weight: 5,
  ),
  _e('gesichtserkennung', 'special.biometric', 'de', weight: 5),
  _e('stemprofiel', 'special.biometric', 'nl', weight: 5),
  _e('voiceprint', 'special.biometric', 'en', weight: 5),
  _e('biometrisch', 'special.biometric', 'nl', weight: 4),
  _e('biometric', 'special.biometric', 'en', weight: 4),
];

/// Alle gebundelde entries, in één lijst.
final List<PrivacyLexiconEntry> bundledPrivacyLexicon = [
  ..._healthTerms,
  ..._criminalTerms,
  ..._beliefTerms,
  ..._biometricTerms,
];

/// De talen waarvoor er überhaupt trefwoorden zijn.
///
/// Fase 13 hangt de dekkingsmeter hieraan op. Nu al bruikbaar als eerlijke
/// mededeling: staat de decktaal hier niet bij, dan heeft de
/// trefwoorddetectie voor dit deck niets te zoeken.
Set<String> get privacyLexiconLanguages => {
  for (final entry in bundledPrivacyLexicon) entry.lang,
};
