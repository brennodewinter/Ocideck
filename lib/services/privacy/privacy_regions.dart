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
// 2007 losgelaten) en `uk.nino`. Die dragen sowieso een contextpoort (§5.2) en
// zijn dus ook aan te laten staan.
//
// "Heel Europa" leest hier als EU-27 + EER + Zwitserland + het VK. Decks reizen,
// en een Nederlandse organisatie ziet Britse en Zwitserse gegevens routinematig.
//
// ── Maar alleen de landen waarvoor iets te vinden valt ──────────────────────
//
// Zes van die landen hadden geen enkele regel en stonden tóch als chip in de
// instellingen, standaard aan. Wie CY of MT zag staan, mocht aannemen dat er
// naar Cypriotische of Maltese nummers werd gekeken; er gebeurde niets. Dat is
// niet "minder vinden" maar iets ergers: het is de belofte van een controle die
// niet bestaat, en het maakt van "niemand keek" een "niets gevonden".
//
// Ze staan er daarom uit tot hun regel bestaat. `privacy_region_coverage_test`
// bewaakt beide kanten van die afspraak.

/// De EU-27, EER, Zwitserland en het VK: elke landcode die de regiopoort als
/// prefix van een regel-id herkent.
///
/// Dit is **niet** de lijst die de gebruiker te zien krijgt — zie
/// [allPrivacyRegions]. Deze staat er apart omdat [privacyRuleRegion] volledig
/// moet blijven: zou `cy` hier ontbreken, dan leest een toekomstige `cy.id` als
/// een regel zónder land, en draait die altijd — buiten elk pakket om, en dus
/// ook bij de gebruiker die Cyprus bewust heeft uitgezet.
const Set<String> _knownEuropeanCodes = {
  'at', 'be', 'bg', 'ch', 'cy', 'cz', 'de', 'dk', 'ee', 'es', 'fi', 'fr', //
  'gr', 'hr', 'hu', 'ie', 'is', 'it', 'li', 'lt', 'lu', 'lv', 'mt', 'nl', //
  'no', 'pl', 'pt', 'ro', 'se', 'si', 'sk', 'uk', //
};

/// Europese landen waarvoor werkelijk een regel bestaat.
///
/// Wie hier ontbreekt is niet vergeten maar heeft nog geen regel, en een chip
/// die aan staat en niets doet is erger dan geen chip — hij laat "niemand keek"
/// lezen als "niets gevonden", precies wat `docs/PRIVACY.md` §"Wat de controle
/// níét doet" verbiedt. LT en SK stáán er wél in: hun nummers worden gedekt door
/// een regel van de buren, zie [sharedRegionRules].
///
/// Nog open: CY, LU, MT en LI.
///
/// Bouw je zo'n regel, zet het land er dan bij — `privacy_region_coverage_test`
/// wordt rood tot je dat doet.
const Set<String> _europeanRegions = {
  'at', 'be', 'bg', 'ch', 'cz', 'de', 'dk', 'ee', 'es', 'fi', 'fr', 'gr', //
  'hr', 'hu', 'ie', 'is', 'it', 'lt', 'lv', 'nl', 'no', 'pl', 'pt', 'ro', //
  'se', 'si', 'sk', 'uk', //
};

/// Regels die voor meer dan één land gelden.
///
/// Sommige nummers zijn niet van één staat. Het rodné číslo stamt uit
/// Tsjecho-Slowakije en wordt in beide opvolgerstaten nog uitgegeven, met
/// dezelfde vorm en dezelfde mod-11. Het Estse isikukood en het Litouwse asmens
/// kodas zijn elf cijfers met exact dezelfde twee controlerondes — één
/// validator (`isValidBalticPersonalCode`) dekt ze allebei.
///
/// Waarom geen eigen `sk.`- en `lt.`-id: dat zou hetzelfde nummer twee keer
/// melden bij wie beide pakketten aan heeft, en een scanner die dubbel roept
/// wordt uitgezet. De regel houdt dus het id van het land waar de checksum
/// vandaan komt, en dit is de lijst waar de póórt leest wie hem nog meer deelt.
const Map<String, Set<String>> sharedRegionRules = {
  'cz.rodne_cislo': {'cz', 'sk'},
  'ee.isikukood': {'ee', 'lt'},
};

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
  ..._europeanRegions,
  ...worldPrivacyRegions,
};

/// Alle regio's die als pakket aan te zetten zijn.
///
/// Gelijk aan [defaultPrivacyRegions]: wat er te kiezen valt staat ook aan. De
/// naam blijft omdat de betekenis verschilt, en die twee kunnen weer uiteenlopen
/// zodra er een land bijkomt dat je wél kunt kiezen maar niet standaard wilt.
const Set<String> allPrivacyRegions = defaultPrivacyRegions;

/// De landcode waaraan [ruleId] hangt, of `null` als de regel altijd draait.
///
/// Een regel is landgebonden wanneer zijn id begint met precies twee letters
/// gevolgd door een punt, én die twee letters een bekende regio zijn. Die tweede
/// eis doet echt werk: `fin.iban` begint óók met letters en een punt, maar `fin`
/// is drie tekens en bovendien geen land — de IBAN-regel geldt voor 89 landen
/// tegelijk en hoort dus nooit uit te vallen omdat iemand een pakket uitzet.
///
/// De toets gaat tegen [_knownEuropeanCodes] en niet tegen [allPrivacyRegions]:
/// een land waarvoor nog geen regel bestaat moet wél als landcode herkend
/// blijven, anders draait de eerste regel die iemand ervoor bouwt buiten elk
/// pakket om.
String? privacyRuleRegion(String ruleId) {
  final dot = ruleId.indexOf('.');
  if (dot != 2) return null;
  final code = ruleId.substring(0, 2);
  return _knownEuropeanCodes.contains(code) ||
          worldPrivacyRegions.contains(code)
      ? code
      : null;
}

/// Draait deze regel binnen [activeRegions]?
///
/// Regels zonder landcode draaien altijd — dat is de universele laag uit §1.4,
/// en die staat los van welk pakket iemand aan heeft. Een gedeelde regel draait
/// zodra één van de landen die hem delen aan staat: zie [sharedRegionRules].
bool privacyRuleInRegions(String ruleId, Set<String> activeRegions) {
  final shared = sharedRegionRules[ruleId];
  if (shared != null) return shared.any(activeRegions.contains);
  final region = privacyRuleRegion(ruleId);
  return region == null || activeRegions.contains(region);
}
