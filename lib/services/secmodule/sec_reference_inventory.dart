import '../cvss/cvss4.dart';
import '../cwe_catalog.dart';
import '../finding_template_library.dart';
import '../miauw_eis_catalog.dart';
import '../mastg_catalog.dart';
import '../maswe_catalog.dart';
import '../wstg_catalog.dart';

/// Eén referentiecatalogus zoals hij lokaal beschikbaar is: hoeveel erin zit,
/// welke versie, en van wie hij komt.
class ReferenceCatalog {
  /// Nederlandse bronnaam; het scherm haalt hem door `l10n.d(...)`.
  final String name;

  /// Aantal records dat de app er nú uit kan bedienen.
  final int count;

  /// De bovenstroomse standaard/versie, of leeg als die er niet is.
  final String standard;

  /// Waar het vandaan komt. Data, niet vertaald.
  final String source;

  const ReferenceCatalog({
    required this.name,
    required this.count,
    required this.standard,
    required this.source,
  });
}

/// Wát er lokaal aan referentiegegevens ligt, in aantallen.
///
/// De vraag "welke informatie is er eigenlijk opgehaald?" was niet te
/// beantwoorden: het scherm zei alleen "Gegevens lokaal beschikbaar". Dit telt
/// de catalogi die de app daadwerkelijk bedient — niet wat een pakket bewéért
/// te bevatten. Zo staat er nooit een geruststellend vinkje bij een lijst die
/// in werkelijkheid leeg is.
class SecReferenceInventory {
  const SecReferenceInventory._();

  /// Telt alle catalogi. Laadt eerst de volledige CWE-lijst uit de asset, want
  /// zonder die stap zou hij de curated bodem tellen en een veel te laag getal
  /// tonen.
  static Future<List<ReferenceCatalog>> load() async {
    await CweCatalog.instance.ensureLoaded();
    return snapshot();
  }

  /// Dezelfde telling, maar zonder te laden — voor een synchrone opbouw van het
  /// scherm nadat [load] al gedraaid heeft.
  static List<ReferenceCatalog> snapshot() => [
    ReferenceCatalog(
      name: 'Zwakheden (CWE)',
      count: CweCatalog.instance.entries.length,
      standard: 'MITRE CWE',
      source: 'cwe.mitre.org',
    ),
    ReferenceCatalog(
      name: 'Testgevallen (WSTG)',
      count: WstgCatalog.instance.tests.length,
      standard: WstgCatalog.instance.standardLabel,
      source: 'owasp.org',
    ),
    ReferenceCatalog(
      name: 'Testgevallen (MASTG)',
      count: MastgCatalog.instance.tests.length,
      standard: MastgCatalog.instance.standardLabel,
      source: 'mas.owasp.org',
    ),
    ReferenceCatalog(
      name: 'Mobiele zwakheden (MASWE)',
      count: MasweCatalog.instance.weaknesses.length,
      standard: MasweCatalog.instance.standardLabel,
      source: 'mas.owasp.org',
    ),
    ReferenceCatalog(
      name: 'MIAUW-eisen',
      count: MiauwEisCatalog.instance.entries.length,
      standard: 'MIAUW',
      source: 'librekat.nl',
    ),
    ReferenceCatalog(
      name: 'CVSS-scoretabel',
      count: cvss4LookupSize,
      standard: 'CVSS 4.0 (FIRST)',
      source: 'first.org',
    ),
    ReferenceCatalog(
      name: 'Bevindingsjablonen',
      count: FindingTemplateLibrary.instance.count,
      standard: '',
      source: 'OciDeck',
    ),
  ];
}
