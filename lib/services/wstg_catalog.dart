import '../models/wstg_test.dart';

part 'wstg_catalog_data.dart';

/// The OWASP Web Security Testing Guide (WSTG) test catalog — the offline,
/// always-on standard test list for the Informatieveiligheid module's
/// `checklist` slide ("Uitvoering testen conform standaard", PENTEST_MIAUW
/// §3.2). Like [CweCatalog], this is a **curated, bundled, in-repo dataset** —
/// no asset wiring, no network — so a tester can populate a checklist with the
/// full standard in one click.
///
/// The test list itself is **generated** by `tool/build_wstg_catalog.dart` from
/// the release's own `checklist.json`; it used to be transcribed by hand, which
/// made a version bump expensive enough to postpone. Two category names read
/// as the guide's own section titles ("Testing for Error Handling", "Testing
/// for Weak Cryptography") rather than the tidied forms this file carried
/// before: the dataset is third-party content, so it is reproduced, not edited.
///
/// The pinned [version] is the **stable released** WSTG version (v4.2, 2020),
/// so a report cites a fixed, citeable standard rather than a moving branch.
/// The ids and titles are the canonical WSTG identifiers; every entry maps back
/// to owasp.org's guide.
///
/// **Third-party content under CC-BY-SA-4.0.** The ids, titles and categories are
/// the OWASP Web Security Testing Guide v4.2 checklist index, © the OWASP
/// Foundation and its contributors, reproduced here with attribution and
/// share-alike; the guide's substance (how to test) is deliberately not bundled.
/// The terms travel with this dataset — `docs/LICENSE_COMPLIANCE.md` is the
/// authority (PENTEST_MIAUW §15 is a design-time note). Bundling another
/// standard's content means adding it to that table in the same commit.
class WstgCatalog {
  WstgCatalog._();

  static final WstgCatalog instance = WstgCatalog._();

  /// The released standard version this catalog reflects (e.g. `4.2`).
  String get version => wstgVersion;

  /// The label written as the checklist's standard heading, e.g.
  /// `OWASP WSTG v4.2` — carries the [version] so it shows in the slide.
  String get standardLabel => wstgStandardLabel;

  /// All tests, in canonical WSTG order (category, then number).
  List<WstgTest> get tests => _tests;
}

/// The stable released WSTG version bundled here.
const wstgVersion = '4.2';

/// The versioned standard label used as the checklist heading default.
const wstgStandardLabel = 'OWASP WSTG v$wstgVersion';
