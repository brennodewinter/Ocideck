// ── THIRD-PARTY CONTENT — NOT EUPL-1.2 ──────────────────────────────────────
//
// The test index in this library (see the `_android` and `_ios` parts)
// reproduces 186 verbatim test ids, titles and MASVS categories of the **OWASP
// Mobile Application Security Testing Guide v2.0.0**, © the OWASP Foundation and
// its contributors, licensed under CC-BY-SA-4.0.
//
//   Licence: https://creativecommons.org/licenses/by-sa/4.0/
//   Source:  https://owasp.org/www-project-mobile-app-security/
//
// **Share-alike travels with this dataset.** Anyone redistributing it — as part
// of OciDeck or lifted out of it — does so under CC-BY-SA-4.0 with this
// attribution. It does not reach the surrounding EUPL-1.2 code: OciDeck bundles
// this material as a *Collection* in the licence's own sense.
//
// See docs/LICENSE_COMPLIANCE.md, § "OWASP WSTG, MASTG and MASWE", for what is
// bundled and what deliberately is not.
// ────────────────────────────────────────────────────────────────────────────

import '../models/mastg_test.dart';

part 'mastg_catalog_android.dart';
part 'mastg_catalog_ios.dart';

/// De OWASP Mobile Application Security Testing Guide (MASTG) — de offline
/// testlijst voor mobiele scope-objecten, tegenhanger van [WstgCatalog] voor
/// het web. Vult een `checklist`-slide in één klik met de standaard.
///
/// Dit sluit een belofte die sinds 11-07-2026 openstond: het besluit was
/// "WSTG + MASTG bundelen", maar alleen WSTG landde. `MASTG` bestond
/// daardoor alleen als etiket op het `mobile` scope-objecttype — een
/// standaard waarvan de checklist niet te vullen was.
///
/// **Gebundeld is de index van v2.0.0, niet de v1-tests.** MASTG is op
/// 30-06-2026 herbouwd tot een verzameling componenten met stabiele id's en
/// expliciete pass/fail-condities. De 92 tests van vóór die herbouw dragen
/// stuk voor stuk `status: deprecated`; die zitten hier niet in. De 14
/// placeholders evenmin: die hebben een titel en een voornemen maar geen
/// uitgeschreven test, en in een klantrapport zou zo'n regel een controle
/// suggereren die niemand kan uitvoeren.
///
/// **Materiaal van derden onder CC-BY-SA-4.0.** De id's, titels en categorieën
/// zijn de MASTG-index, © de OWASP Foundation en haar bijdragers, hier
/// overgenomen met naamsvermelding en gelijke deling; de inhoud van de gids
/// (hoe te testen) is bewust niet gebundeld. De voorwaarden reizen mee met
/// deze dataset — `docs/LICENSE_COMPLIANCE.md` is daarvoor het gezag.
class MastgCatalog {
  MastgCatalog._();

  static final MastgCatalog instance = MastgCatalog._();

  /// De uitgebrachte standaardversie die deze catalogus weerspiegelt.
  String get version => mastgVersion;

  /// Het etiket dat als standaardkop op de checklist komt.
  String get standardLabel => mastgStandardLabel;

  /// Alle tests, op id gesorteerd.
  List<MastgTest> get tests =>
      [..._androidTests, ..._iosTests]..sort((a, b) => a.id.compareTo(b.id));

  /// Alleen de tests voor [platform] (`android` of `ios`).
  ///
  /// Bestaat omdat een mobiele pentest zelden beide platforms tegelijk raakt:
  /// een checklist van 186 regels waarvan de helft niet van toepassing is,
  /// wordt niet afgewerkt maar weggeklikt.
  List<MastgTest> forPlatform(String platform) =>
      platform == 'ios' ? _iosTests : _androidTests;

  /// De test met [id], of null.
  MastgTest? byId(String id) {
    for (final t in tests) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// De uitgebrachte MASTG-versie die hier gebundeld is.
const mastgVersion = '2.0.0';

/// Het versiedragende etiket voor de checklistkop.
const mastgStandardLabel = 'OWASP MASTG v$mastgVersion';
