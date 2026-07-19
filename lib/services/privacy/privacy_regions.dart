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

/// Landen buiten Europa waarvan de regels tóch standaard meedraaien.
///
/// De redenering hierboven geldt hier onverkort, en §15.6 maakt hem expliciet:
/// elke Amerikaanse en Canadese regel draagt óf een checksum óf een
/// contextpoort, en geen van beide kost precisie. Wat de doorslag geeft is
/// echter niet techniek maar de AVG. Bescherming mag niet afhangen van de vraag
/// of de auteur wist dat hij een vinkje moest aanzetten — een deck met
/// Amerikaanse persoonsgegevens hoort bij een standaardinstallatie
/// gecontroleerd te worden.
///
/// Dat de Amerikaanse nummers géén checksum hebben pleit hier vóór en niet
/// tegen: juist omdat ze alleen op een contextpoort steunen, vuren ze zelden
/// spontaan. `us.ssn` zonder het woord "SSN" ernaast doet niets.
/// De niet-Europese landpakketten (§15). Sinds fase 8d compleet.
///
/// Deze staan alle acht standaard aan, en de toets daarvoor is per land met de
/// hand gedaan in plaats van collectief: draagt élke regel van dat land óf een
/// checksum óf een contextpoort? Bij `cw` en `aw` is dat alleen het tweede —
/// voor de sedula en het Arubaanse persoonsnummer bestaat geen gedocumenteerde
/// checksum — maar een contextpoort is genoeg, want zonder het woord ernaast
/// zwijgen ze volledig.
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

/// Het standaardpakket: heel Europa (OCIWACHT §7, besluit 4) plus de rest van
/// de wereld (§15.6).
///
/// Dat "plus" is een besluit met een reden die niet technisch is. De techniek
/// zegt alleen dat het kan: checksums en contextpoorten kosten geen precisie.
/// Waaróm het moet, zegt de AVG — bescherming mag niet afhangen van de vraag of
/// de auteur wist dat hij een vinkje moest aanzetten. Wie een deck met
/// Braziliaanse of Zuid-Afrikaanse persoonsgegevens opent, heeft die controle
/// het hardst nodig als hij er het minst aan denkt.
const Set<String> defaultPrivacyRegions = {
  ..._euMemberStates,
  ..._europeanNonEu,
  ...worldPrivacyRegions,
};

/// Alle regio's die als pakket aan te zetten zijn.
///
/// Sinds 8d dekt het standaardpakket ze allemaal, dus dit is nu hetzelfde. De
/// naam blijft omdat de betekenis verschilt: [defaultPrivacyRegions] is wat er
/// áán staat, dit is wat er te kiezen valt. Die twee kunnen weer uiteenlopen
/// zodra er een land bijkomt waarvan de regels nog niet af zijn.
const Set<String> allPrivacyRegions = defaultPrivacyRegions;

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
