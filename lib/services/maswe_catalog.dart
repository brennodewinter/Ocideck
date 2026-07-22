// ── THIRD-PARTY CONTENT — NOT EUPL-1.2 ──────────────────────────────────────
//
// The weakness list in this library (see the `_written` and `_draft` parts)
// reproduces 117 verbatim weakness ids, titles, MASVS categories and CWE
// mappings of the **OWASP Mobile Application Security Weakness Enumeration**
// (snapshot 2026-06-12 — the project publishes no releases or tags).
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

part 'maswe_catalog_written.dart';
part 'maswe_catalog_draft.dart';

/// De OWASP Mobile Application Security Weakness Enumeration (MASWE) — de
/// mobiele tegenhanger van MITRE's CWE, en de laag waar MASTG-tests naar
/// verwijzen.
///
/// **Vastgelegd op datum, niet op versie.** MASWE voert geen releases en geen
/// tags: er is één doorlopende branch. Het enige eerlijke antwoord op "welke
/// versie is gebruikt" is dus de dag waarop deze momentopname is genomen, en de
/// verouderingspoort vergelijkt met de datum van de laatste commit. Dat is een
/// zwakkere aanhaling dan `WSTG v4.2` of `MASTG v2.0.0`, en dat hoort zo te
/// staan in plaats van weggepoetst te worden met een verzonnen versienummer.
///
/// **Drie kwart is nog niet uitgeschreven, en dat is geen reden om ze weg te
/// laten.** OWASP heeft de zwakheden benoemd — met id, titel, CWE-koppeling en
/// een conceptomschrijving — maar de toelichtingspagina's grotendeels nog niet
/// geschreven. Naar zo'n zwakheid verwijzen in een bevinding is gewoon juist;
/// je haalt een enumeratie aan, geen handleiding. Ze dragen wel
/// [MasweWeakness.isPlaceholder], zodat een scherm kan tonen dat de uitleg dun
/// is. Dit is bewust een ándere afweging dan bij MASTG, waar placeholders juist
/// worden overgeslagen: daar zou het een test beloven die niemand kan doen.
///
/// **Materiaal van derden onder CC-BY-SA-4.0**, © de OWASP Foundation en haar
/// bijdragers; `docs/LICENSE_COMPLIANCE.md` is daarvoor het gezag.
class MasweCatalog {
  MasweCatalog._();

  static final MasweCatalog instance = MasweCatalog._();

  /// De datum van de momentopname (`JJJJ-MM-DD`).
  String get snapshotDate => masweSnapshotDate;

  /// Het etiket dat de aanhaling draagt.
  String get standardLabel => masweStandardLabel;

  /// Alle zwakheden, op id gesorteerd.
  List<MasweWeakness> get weaknesses =>
      [..._writtenWeaknesses, ..._draftWeaknesses]
        ..sort((a, b) => a.id.compareTo(b.id));

  /// Alleen de zwakheden waarvan de uitleg is geschreven.
  List<MasweWeakness> get written => _writtenWeaknesses;

  /// De zwakheid met [id], of null.
  MasweWeakness? byId(String id) {
    for (final w in weaknesses) {
      if (w.id == id) return w;
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

/// De dag waarop deze momentopname van MASWE is genomen.
const masweSnapshotDate = '2026-06-12';

/// Het etiket met de datum, want een versienummer heeft MASWE niet.
const masweStandardLabel = 'OWASP MASWE ($masweSnapshotDate)';
