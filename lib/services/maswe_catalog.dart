// ── THIRD-PARTY CONTENT — NOT EUPL-1.2 ──────────────────────────────────────
//
// The weakness list in this library (see the `maswe_catalog_data` part)
// reproduces 78 verbatim weakness ids, titles, MASVS categories, requirement
// summaries and CWE mappings of the **OWASP Mobile Application Security
// Weakness Enumeration v1.0.0.
// © the OWASP Foundation and its contributors, licensed under CC-BY-SA-4.0.
//
//   Licence: https://creativecommons.org/licenses/by-sa/4.0/
//   Source:  https://mas.owasp.org/MASWE/
//
// **Share-alike travels with this dataset.** Anyone redistributing it — as part
// of OciDeck or lifted out of it — does so under CC-BY-SA-4.0 with this
// attribution. It does not reach the surrounding EUPL-1.2 code: OciDeck bundles
// this material as a *Collection* in the licence's own sense.
//
// See docs/LICENSE_COMPLIANCE.md, § "OWASP WSTG, MASTG and MASWE".
// ────────────────────────────────────────────────────────────────────────────

import '../models/maswe_weakness.dart';

part 'maswe_catalog_data.dart';

/// De OWASP Mobile Application Security Weakness Enumeration (MASWE) — de
/// mobiele tegenhanger van MITRE's CWE, en de laag waar MASTG-tests naar
/// verwijzen.
///
/// **Vastgelegd op de officiële uitgave.** Sinds 17 augustus 2026 publiceert
/// MASWE releases. De gebundelde catalogus volgt daarom net als WSTG en MASTG
/// een citeerbare tag; de bewegende `main`-branch wordt afzonderlijk als
/// ontwikkelstand bewaakt en mag deze stabiele ondergrens niet stil vervangen.
///
/// **Oude beta-nummering blijft aanhaalbaar.** OWASP heeft de lijst medio 2026
/// herbouwd: van 117 (grotendeels concept) naar 78 uitgeschreven zwakheden,
/// MASWE-0001..0078. De oude concept-id's tot 0119 bestaan niet meer als
/// zwakheid, maar leven voort als [_betaAliases]: elk oud id wijst de canonieke
/// zwakheid aan die het heeft opgeslokt. [byId] volgt die brug, zodat de
/// gebundelde MASTG v2.0.0 — die nog naar de beta-nummering verwijst — blijft
/// kloppen zonder dat we die MASTG-data vervalsen.
///
/// **Materiaal van derden onder CC-BY-SA-4.0**, © de OWASP Foundation en haar
/// bijdragers; `docs/LICENSE_COMPLIANCE.md` is daarvoor het gezag.
class MasweCatalog {
  MasweCatalog._();

  static final MasweCatalog instance = MasweCatalog._();

  /// De officiële MASWE-versie die deze catalogus weerspiegelt.
  String get version => masweVersion;

  /// Het etiket dat de aanhaling draagt.
  String get standardLabel => masweStandardLabel;

  /// Alle zwakheden, op id gesorteerd (de generator levert ze al gesorteerd).
  List<MasweWeakness> get weaknesses => _weaknesses;

  /// De zwakheid met [id], of null.
  ///
  /// Een canoniek id wint altijd: bestaat [id] als huidige zwakheid, dan geeft
  /// die terug. Pas als dat niet zo is, wordt [id] als oud beta-id opgevat en
  /// via [_betaAliases] naar zijn canonieke opvolger gebracht. Die volgorde is
  /// wezenlijk — de beta- en de canonieke nummering delen dezelfde ruimte
  /// (`MASWE-0001` is zowel een huidige zwakheid als een beta-id dat elders is
  /// opgegaan), en de huidige zwakheid hoort dan voor te gaan.
  MasweWeakness? byId(String id) {
    for (final w in _weaknesses) {
      if (w.id == id) return w;
    }
    final canonical = _betaAliases[id];
    if (canonical == null) return null;
    for (final w in _weaknesses) {
      if (w.id == canonical) return w;
    }
    return null;
  }

  /// De zwakheden die op CWE-nummer [cweId] uitkomen.
  ///
  /// De brug tussen de mobiele en de algemene taal: een bevinding die al een
  /// CWE draagt, kan zo de mobiele zwakheid erbij vinden — en omgekeerd.
  List<MasweWeakness> forCwe(int cweId) =>
      weaknesses.where((w) => w.cweIds.contains(cweId)).toList();
}

/// De officiële MASWE-uitgave die hier gebundeld is.
const masweVersion = '1.0.0';

/// Het versiedragende etiket voor rapporten en verwijzingen.
const masweStandardLabel = 'OWASP MASWE v$masweVersion';
