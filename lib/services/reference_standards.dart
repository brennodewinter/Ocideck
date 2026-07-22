import '../models/reference_standard.dart';
import 'mastg_catalog.dart';
import 'maswe_catalog.dart';
import 'wstg_catalog.dart';

/// Elke referentiestandaard die OciDeck meedraagt, als data.
///
/// De versies stonden tot nu toe alleen in proza — een `const` in de catalogus,
/// een regel in `docs/LICENSE_COMPLIANCE.md`, een zin in een ontwerpdoc. Proza
/// veroudert stil: WSTG kreeg een v5.0 in ontwikkeling en MASTG werd op
/// 30-06-2026 volledig herbouwd zonder dat er iets in deze repo dat kon merken.
/// Hiervandaan leest de verouderingspoort, het instellingenoverzicht en straks
/// de rapportbijlage, zodat er één waarheid is en die te toetsen valt.
///
/// **Bij het bijwerken van een catalogus hoort de versie hier mee.** De
/// bijbehorende test bewaakt dat het versienummer hier gelijk is aan dat in de
/// catalogus zelf, zodat de twee niet uiteen kunnen lopen.
const referenceStandards = <ReferenceStandard>[
  ReferenceStandard(
    id: 'wstg',
    name: 'OWASP WSTG',
    bundledVersion: wstgVersion,
    url: 'https://owasp.org/www-project-web-security-testing-guide/',
    bundled:
        'De checklist-index: per test het stabiele id, de canonieke titel en de '
        'categorie. De inhoud van de gids zelf is niet gebundeld.',
    licence: 'CC-BY-SA-4.0',
    probe: UpstreamProbe.githubReleases,
    probeTarget: 'OWASP/wstg',
  ),
  ReferenceStandard(
    id: 'mastg',
    name: 'OWASP MASTG',
    bundledVersion: mastgVersion,
    url: 'https://mas.owasp.org/MASTG/',
    bundled:
        'De test-index van v2.0.0: per test het stabiele id, de canonieke '
        'titel, de MASVS-categorie en de MASWE-zwakheid. De ingetrokken '
        'v1-tests en de placeholders zitten er niet in; de inhoud van de gids '
        'evenmin.',
    licence: 'CC-BY-SA-4.0',
    probe: UpstreamProbe.githubReleases,
    probeTarget: 'OWASP/mastg',
  ),
  ReferenceStandard(
    id: 'maswe',
    name: 'OWASP MASWE',
    bundledVersion: masweSnapshotDate,
    url: 'https://mas.owasp.org/MASWE/',
    bundled:
        'De zwakhedenlijst (117): id, titel, MASVS-categorie, platform en de '
        'CWE-koppeling. Drie kwart is bij de bron nog niet uitgeschreven; die '
        'staan er wél in, gemarkeerd. Ingetrokken zwakheden niet.',
    licence: 'CC-BY-SA-4.0',
    // Geen releases, geen tags — alleen een doorlopende branch.
    probe: UpstreamProbe.githubCommitDate,
    probeTarget: 'OWASP/maswe',
  ),
  ReferenceStandard(
    id: 'cwe',
    name: 'MITRE CWE',
    bundledVersion: cweBundledVersion,
    url: 'https://cwe.mitre.org/',
    bundled:
        'De volledige lijst (id, naam, beschrijving) plus een eigen '
        'geselecteerde kern met onze remediatie-notities.',
    licence: 'MITRE Terms of Use',
    // MITRE's eigen REST-API geeft versie, inhoudsdatum én het aantal
    // zwakheden — dat laatste controleert meteen of onze bundel compleet is.
    probe: UpstreamProbe.cweApi,
    probeTarget: 'https://cwe-api.mitre.org/api/v1/cwe/version',
  ),
  ReferenceStandard(
    id: 'miauw',
    name: 'MIAUW',
    bundledVersion: miauwBundledVersion,
    url: 'https://github.com/brennodewinter/Informatiebeveiligingsonderzoek',
    bundled: 'Het volledige EIS-schema (88 toetsbare eisen).',
    licence: 'EUPL-1.2',
    // Op de commitdatum van het werkboek zelf, niet op de release en niet op de
    // repo als geheel. De methodologie tagt releases met namen ("Otis"), dus een
    // tagvergelijking gaat niet op; de repo krijgt daarnaast commits die het
    // schema niet raken. Wat wij bundelen is dit ene bestand, dus dat is wat de
    // poort in de gaten houdt.
    probe: UpstreamProbe.githubCommitDate,
    probeTarget: 'brennodewinter/Informatiebeveiligingsonderzoek',
    probePath: 'NL-Schema_Miauw_1_00.xlsx',
  ),
  ReferenceStandard(
    id: 'orphanet',
    name: 'Orphanet',
    bundledVersion: orphanetBundledVersion,
    url: 'https://www.orphadata.com/data/xml/',
    bundled:
        'Aandoeningsnamen in negen talen als gezondheidslexicon voor de '
        'privacycontrole (assets/privacy/health_lexicon.json).',
    licence: 'CC-BY-4.0',
    probe: UpstreamProbe.orphanetDate,
    probeTarget: 'https://www.orphadata.com/data/xml/nl_product1.xml',
    // Adviserend: dit is een detectielexicon, geen catalogus die de gebruiker
    // leest. Zie ReferenceStandard.advisory en OCIWACHT §13.3.
    advisory: true,
  ),
  ReferenceStandard(
    id: 'cvss',
    name: 'FIRST CVSS',
    bundledVersion: cvssBundledVersion,
    url: 'https://www.first.org/cvss/v4-0/',
    bundled:
        'Een eigen Dart-implementatie van de publieke specificatie, inclusief '
        'de MacroVector-tabel en de gepubliceerde bandindeling.',
    licence: 'Specificatie van FIRST.Org — attributie',
    // FIRST publiceert geen "laatste versie", maar wel per versie een schema op
    // een vaste URL. We proberen dus of de opvolger al bestaat.
    probe: UpstreamProbe.successorDocument,
    probeTarget: 'https://www.first.org/cvss/cvss-v{version}.json',
  ),
];

/// De CWE-lijst die `assets/cwe/cwe_full.json` weerspiegelt.
const cweBundledVersion = '4.20';

/// Het MIAUW-schema dat `miauw_eis_catalog.dart` weerspiegelt. De methodologie
/// voert geen releasenummers, dus we noteren een datum — en dat is de datum die
/// **de bron** draagt: de laatste wijziging van het werkboek
/// `NL-Schema_Miauw_1_00.xlsx` upstream.
///
/// Hier stond tot 22-07-2026 `2026-07-16`, de dag waarop wij het schema
/// overnamen. Dat leest als hetzelfde soort feit maar is het niet, en het brak
/// de poort: een overnamedatum ligt altijd ná de bronwijziging, dus de
/// vergelijking "is upstream nieuwer?" kon voor MIAUW nooit waar worden. De
/// verouderingscontrole meldde jarenlang "actueel" zonder ooit iets te kunnen
/// zeggen. Bundel je een nieuwe snapshot, zet hier dan de commitdatum van het
/// werkboek — niet de dag waarop je het deed.
const miauwBundledVersion = '2024-12-06';

/// De Orphanet-uitgave die `assets/privacy/health_lexicon.json` weerspiegelt.
/// Orphanet voert geen versienummers maar datumt elke uitgave.
const orphanetBundledVersion = '2026-06-23';

/// De CVSS-specificatie die `lib/services/cvss/` implementeert.
const cvssBundledVersion = '4.0';

/// Opzoeken op [ReferenceStandard.id], of null.
ReferenceStandard? referenceStandardById(String id) {
  for (final s in referenceStandards) {
    if (s.id == id) return s;
  }
  return null;
}

/// De regel zoals hij in een deck wordt vastgelegd: `naam@versie`.
String usedStandardEntry(ReferenceStandard s) =>
    s.bundledVersion.isEmpty ? s.name : '${s.name}@${s.bundledVersion}';

/// Alles wat deze build meedraagt, klaar om in een deck te zetten (EIS 4.3.2).
List<String> currentStandardEntries() =>
    referenceStandards.map(usedStandardEntry).toList();

/// Splitst `naam@versie` terug. Een regel zonder `@` levert een lege versie —
/// oude decks en met de hand getypte regels blijven zo gewoon leesbaar.
({String name, String version}) parseUsedStandard(String entry) {
  final at = entry.lastIndexOf('@');
  if (at <= 0) return (name: entry.trim(), version: '');
  return (
    name: entry.substring(0, at).trim(),
    version: entry.substring(at + 1).trim(),
  );
}

/// De standaarden waarvan het deck een ándere versie noemt dan deze build
/// bundelt — met per standaard de vastgelegde en de huidige versie.
///
/// Dit is de verouderingsmelding zonder netwerk. Het deck draagt de versie
/// waartegen echt is getoetst; deze build draagt de nieuwste die wij kennen.
/// Lopen die uiteen, dan is de standaard sinds dat onderzoek bijgewerkt, en dat
/// hoort een lezer van het rapport te weten vóór het wordt verzegeld.
///
/// Standaarden die het deck noemt maar wij niet kennen blijven buiten beeld:
/// daar valt niets over te zeggen, en een gok zou hier als feit gaan lezen.
List<({String name, String recorded, String current})> outdatedStandards(
  List<String> standardsUsed,
) {
  final out = <({String name, String recorded, String current})>[];
  for (final entry in standardsUsed) {
    final used = parseUsedStandard(entry);
    if (used.version.isEmpty) continue;
    for (final known in referenceStandards) {
      if (known.name != used.name) continue;
      if (known.bundledVersion.isNotEmpty &&
          known.bundledVersion != used.version) {
        out.add((
          name: used.name,
          recorded: used.version,
          current: known.bundledVersion,
        ));
      }
      break;
    }
  }
  return out;
}
