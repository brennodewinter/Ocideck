import '../models/reference_standard.dart';
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
    // Op datum, niet op tag: de methodologie tagt releases met namen.
    probe: UpstreamProbe.githubReleaseDate,
    probeTarget: 'brennodewinter/Informatiebeveiligingsonderzoek',
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
/// voert geen releasenummers, dus we noteren de datum van de overgenomen versie.
const miauwBundledVersion = '2026-07-16';

/// De CVSS-specificatie die `lib/services/cvss/` implementeert.
const cvssBundledVersion = '4.0';

/// Opzoeken op [ReferenceStandard.id], of null.
ReferenceStandard? referenceStandardById(String id) {
  for (final s in referenceStandards) {
    if (s.id == id) return s;
  }
  return null;
}
