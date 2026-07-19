// Regiopakketten: welke landen de scanner meeneemt.
//
// Een regel-id dat met een landcode begint (`nl.bsn`, `pl.pesel`, `uk.nino`) is
// landgebonden; al het andere (`fin.iban`, `contact.email`, `secret.*`,
// `digital.*`, `doc.mrz`) draait altijd. Dat onderscheid zit in het id zelf en
// niet in een tweede lijst, want een handmatig bijgehouden koppeling tussen
// regels en landen is precies het soort ding dat stilletjes uit de pas loopt.
//
// ── Waarom heel Europa standaard aan staat ──────────────────────────────────
//
// De intuïtie zegt: begin smal, want elk extra land is extra ruis. Voor deze
// verzameling klopt dat niet, en de reden is de FP-strategie zelf. Van de ruim
// dertig Europese persoonsnummers zijn er ruim twintig zelfvaliderend — mod-97,
// mod-11, ISO 7064, Luhn — en een checksum kóst geen precisie, hij wínt precisie.
// Een Pools PESEL aanzetten voegt vrijwel geen vals-positieven toe, want een
// willekeurig getal haalt die controle niet.
//
// De uitzonderingen zijn de handvol zonder bruikbare checksum: `dk.cpr` (sinds
// 2007 losgelaten), `uk.nino`, `mt.id`, `cy.id`, `lu.matricule`. Die dragen
// sowieso een contextpoort (§5.2) en zijn dus ook aan te laten staan.
//
// "Heel Europa" leest hier als EU-27 + EER + Zwitserland + het VK. Decks reizen,
// en een Nederlandse organisatie ziet Britse en Zwitserse gegevens routinematig.

/// De EU-27.
const Set<String> _euMemberStates = {
  'at',
  'be',
  'bg',
  'cy',
  'cz',
  'de',
  'dk',
  'ee',
  'es',
  'fi',
  'fr',
  'gr',
  'hr',
  'hu',
  'ie',
  'it',
  'lt',
  'lu',
  'lv',
  'mt',
  'nl',
  'pl',
  'pt',
  'ro',
  'se',
  'si',
  'sk',
};

/// EER-landen buiten de EU, plus Zwitserland en het Verenigd Koninkrijk.
const Set<String> _europeanNonEu = {'no', 'is', 'li', 'ch', 'uk'};

/// Het standaardpakket: heel Europa (OCIWACHT §7, besluit 4).
const Set<String> defaultPrivacyRegions = {
  ..._euMemberStates,
  ..._europeanNonEu,
};

/// De rest van de wereld waarvoor er regels bestaan of komen (§3-A, fase 8).
const Set<String> worldPrivacyRegions = {
  'us',
  'ca',
  'au',
  'in',
  'br',
  'za',
  'cw',
  'aw',
};

/// Alle regio's die als pakket aan te zetten zijn.
const Set<String> allPrivacyRegions = {
  ...defaultPrivacyRegions,
  ...worldPrivacyRegions,
};

/// De landcode waaraan [ruleId] hangt, of `null` als de regel altijd draait.
///
/// Een regel is landgebonden wanneer zijn id begint met precies twee letters
/// gevolgd door een punt, én die twee letters een bekende regio zijn. Die tweede
/// eis doet echt werk: `fin.iban` begint óók met letters en een punt, maar `fin`
/// is drie tekens en bovendien geen land — de IBAN-regel geldt voor 89 landen
/// tegelijk en hoort dus nooit uit te vallen omdat iemand een pakket uitzet.
String? privacyRuleRegion(String ruleId) {
  final dot = ruleId.indexOf('.');
  if (dot != 2) return null;
  final code = ruleId.substring(0, 2);
  return allPrivacyRegions.contains(code) ? code : null;
}

/// Draait deze regel binnen [activeRegions]?
///
/// Regels zonder landcode draaien altijd — dat is de universele laag uit §1.4,
/// en die staat los van welk pakket iemand aan heeft.
bool privacyRuleInRegions(String ruleId, Set<String> activeRegions) {
  final region = privacyRuleRegion(ruleId);
  return region == null || activeRegions.contains(region);
}
