// Summarise line coverage from an lcov report and, optionally, enforce a floor.
//
//   flutter test --coverage
//   dart run tool/coverage_summary.dart [--min=50] [--require-instrumented]
//                                       [--per-file-floor]
//   (or: make coverage)
//
// Reads coverage/lcov.info, prints overall line coverage, and exits non-zero
// when --min=<percent> is given and the coverage is below it, so it can gate CI.
//
// --require-instrumented closes the hole in that percentage. lcov only records
// files a test actually imported, so a file NO test imports is not 0% — it is
// absent from the denominator entirely. Add a brand-new, wholly untested file
// and the percentage does not move a hair: the one thing a coverage floor is
// supposed to catch is the one thing it structurally cannot see. This flag
// enumerates lib/ from disk instead and fails on any file missing from the
// report that is not in [uncoveredBaseline].
//
// --per-file-floor closes the *second* hole: being in the denominator is not
// being executed. A file can be imported by a test and still run zero lines —
// on 2026-07-21 twenty-two lib/ files were in that state, 1.219 lines between
// them, and every one of them sailed through both checks above, because an
// 80% average absorbs a single file that never runs. A floor that looks at the
// mean cannot see the worst case; this flag looks at the worst case.

import 'dart:io';

/// lib/ files legitimately absent from lcov. RATCHET: may shrink, never grow.
///
/// There are exactly two legitimate reasons to be here:
///
///   * PLATFORM — a conditional-import facade or its web half. The VM test
///     runner cannot load `dart:js_interop` code at all, so these can never be
///     instrumented, no matter how many tests you write.
///   * NO EXECUTABLE LINES — a bare `export` barrel, a lone enum, or a const
///     data table. lcov emits no record for a file with nothing to execute.
///
/// A file that is merely *untested* does not belong here: write the test.
const Set<String> uncoveredBaseline = {
  // NO EXECUTABLE LINES: `slide_taxonomy.dart` is a `part` containing only
  // public enum declarations. Their persisted names are asserted directly in
  // slide_taxonomy_test.dart, but lcov emits no record for declaration-only
  // parts.
  'lib/models/slide_taxonomy.dart',
  // UNTESTABLE NATIVE BINDING (F3, ketenkeuring-flutter-webrtc.md; user-approved
  // new category, 2026-08-02): `meeting_media_core_webrtc.dart` is the one thin
  // binding to `flutter_webrtc` (libwebrtc). It differs from a platform half —
  // it is present on every platform, not split io/web — but shares the reason
  // those sit here: it cannot run in a headless test VM. libwebrtc needs a real
  // device (camera/mic, ICE, a live peer), so this binding is verified LIVE, not
  // by a unit test. The preflight tile imports it, so it does carry a report
  // record — at 0 of 9 lines, because nothing here can run headless. Testing it
  // would only cover the two trivial delegations (the constructor and the
  // `mediaE2ee` getter, which just forwards to the pure, tested `mediaE2eeFor`)
  // while `selfTest`'s libwebrtc call stays uncovered, leaving the file well
  // under the per-file floor. That floor skips this list precisely so the
  // approved exemption is not defeated by it, and `classifyBaselined` keeps the
  // leave-the-list tip from recommending it. Its only real decision — the E2EE
  // fact — is proven directly on `mediaE2eeFor` in meeting_media_core_test.dart,
  // and no decision logic hides here. Keep this list to genuine such bindings,
  // not a hiding place for logic testable via a fake.
  'lib/meetings/meeting_media_core_webrtc.dart',
  // NO EXECUTABLE LINES: `library_scan_limits.dart` holds only two const upper
  // bounds shared by the deck scan and the image picker (#1049) — lcov emits no
  // record for a file with nothing to execute. The values are exercised through
  // ImageLibraryScanner (image_library_scanner_test.dart).
  'lib/utils/library_scan_limits.dart',
  // NO EXECUTABLE LINES: `language_registry.dart` holds only two consts — the
  // interface-language map and the docs base language — kept Flutter-free so
  // build tooling (`dart run tool/translate_docs.dart`) can read them without
  // compiling Flutter. lcov emits no record for a const-only file. The data is
  // exercised through `AppLocalizations.languageNames` across the widget suite,
  // and asserted directly in language_registry_test.dart.
  'lib/l10n/language_registry.dart',
  // NO EXECUTABLE LINES: `collab.dart` is the collaboration module's barrel —
  // pure `export` directives, nothing for a line counter to reach. The files it
  // re-exports (the codec, the log store, the async transport) each carry their
  // own tests; see collab_codec_test, webdav_collab_log_store_test and
  // webdav_async_transport_test.
  'lib/collab/collab.dart',
  // NO EXECUTABLE LINES: `openkat_import_action.dart` is een kale
  // export-facade (één conditional export, patroon media_fetch). PLATFORM:
  // `openkat_import_action_web.dart` is de lege webromp — het menu-item
  // bestaat op web niet. De io-helft, waar het echte werk zit, wordt wél
  // getest (openkat_import_action_test.dart).
  'lib/widgets/shell/openkat_import_action.dart',
  'lib/widgets/shell/openkat_import_action_web.dart',
  // NO EXECUTABLE LINES: `media_fetch.dart` is een kale export-facade — één
  // conditional export en verder niets. PLATFORM: `media_fetch_web.dart` is de
  // web-helft daarvan; daar opent de browser de verbinding en valt er niets te
  // pinnen. De io-helft, waar de SSRF-poort zit, wordt wél getest
  // (media_fetch_test.dart).
  'lib/utils/media_fetch.dart',
  'lib/utils/media_fetch_web.dart',
  // NO EXECUTABLE LINES: `mem_asset_blob.dart` is een kale export-facade — één
  // conditional export en verder niets. PLATFORM: `mem_asset_blob_web.dart` is
  // de web-helft die een `blob:`-URL uit pakket-media-bytes maakt (#854); buiten
  // de browser bestaat die API niet. De stub-helft (die null geeft) wordt wél
  // getest (package_asset_resolver_media_test.dart).
  'lib/utils/mem_asset_blob.dart',
  'lib/utils/mem_asset_blob_web.dart',
  // NO EXECUTABLE LINES: `confirm_certificate.dart` bevat één typedef en verder
  // niets — de vorm waarin de drie netwerkpanelen de certificaatbevestiging
  // aanroepen. Het staat apart omdat het ophalen van een certificaat op
  // `dart:io` leunt en een paneel dat niet mee mag slepen naar de webbundel;
  // lcov schrijft geen record voor een bestand zonder uitvoerbare regels.
  'lib/widgets/dialogs/settings/confirm_certificate.dart',
  // NO EXECUTABLE LINES: `StorageOrigin` is een abstract interface met twee
  // getters en verder niets — het contract dat WebdavOrigin, S3Origin en
  // GitOrigin delen. De implementaties worden wél getest
  // (tab_storage_origin_test.dart), maar lcov schrijft geen record voor een
  // bestand zonder uitvoerbare regels.
  'lib/models/storage_origin.dart',
  // NO EXECUTABLE LINES: `PresentationSource` is idem een abstract interface —
  // één getter en één methode, verder niets — het contract dat de zoekbronnen
  // van 'Slide zoeken' delen. De implementaties worden wél getest
  // (git_presentation_source_test.dart, remote_presentation_source_test.dart),
  // maar lcov schrijft geen record voor een bestand zonder uitvoerbare regels.
  'lib/services/presentation_search/presentation_source.dart',
  // NO EXECUTABLE LINES: the generated MASTG index — two `part` files holding
  // nothing but a const list of 186 MastgTest literals. They are exercised
  // (mastg_catalog_test.dart reads every entry) but lcov emits no record for a
  // file with nothing to execute. Split in two only because 186 entries in one
  // file crosses the 1000-line ratchet.
  'lib/services/mastg_catalog_android.dart',
  'lib/services/mastg_catalog_ios.dart',
  // NO EXECUTABLE LINES: idem voor de gegenereerde MASWE-lijst (zwakheden plus
  // de beta-alias-brug).
  'lib/services/maswe_catalog_data.dart',
  // NO EXECUTABLE LINES: idem voor de WSTG-index, sinds die uit
  // tool/build_wstg_catalog.dart komt in plaats van met de hand overgetikt.
  'lib/services/wstg_catalog_data.dart',
  // NO EXECUTABLE LINES: gegenereerde Procesverbetering-sjabloonvloer — één
  // const JSON-string. Wordt gelezen via ImprovementTemplateCatalog (en
  // improvement_template_catalog_test.dart), maar lcov ziet niets om uit te
  // voeren. Bron: tool/build_improvement_templates.dart.
  'lib/services/improvement/improvement_templates_floor.g.dart',
  // NO EXECUTABLE LINES: de woordenlijst van de markdown-checker — een `part`
  // met alleen const sets (class-tokens, front-matter sleutels, directives).
  // Ruim gedekt via markdown_validator_test.dart, maar lcov ziet niets om uit
  // te voeren. Afgesplitst omdat de validator anders de 1000-regel-ratchet
  // overschrijdt.
  'lib/services/markdown_validator_vocabulary.dart',
  // PLATFORM: entrypoint — runApp() never executes under the test runner.
  'lib/main.dart',
  // PLATFORM: conditional-import facades + their io/web halves. De io-helft van
  // native_window staat hier NIET meer: dat was gewone dart:io-code met
  // negentien echte statements, geen platformnaad. Zie native_window_test.dart,
  // dat het `window_manager`-kanaal namaakt en de opstartvolgorde toetst.
  'lib/platform/native_window.dart',
  'lib/platform/native_window_stub.dart',
  'lib/platform/platform_features_web.dart',
  'lib/platform/presenter_fullscreen_web.dart',
  'lib/services/cve_transport_factory.dart',
  'lib/services/cve_transport_web.dart',
  // NO EXECUTABLE LINES: `mermaid_config.dart` is één bron van waarheid voor de
  // mermaid-instellingen — alleen const-declaraties, lcov schrijft er geen
  // record voor. PLATFORM: `mermaid_web_renderer.dart` is de web-helft die
  // mermaid via JS-interop draait (#851); die compileert alleen op web
  // (dart:js_interop) en komt dus nooit in een VM-testrapport. De io-stub
  // (mermaid_web_renderer_stub.dart) staat hier NIET: die compileert wél op de
  // VM en wordt rechtstreeks gedekt door mermaid_web_render_test. Het echte
  // web-renderen is visueel geverifieerd, want kIsWeb is onder flutter test
  // altijd false.
  'lib/services/mermaid_config.dart',
  'lib/services/mermaid_web_renderer.dart',
  // PLATFORM: the git transport's conditional-export facade (its two halves are
  // exercised via the forge contract). A one-line `export … if …` barrel with
  // no statement to reach — the same seam as cve_transport_factory above.
  'lib/services/git/git_transport_factory.dart',
  // PLATFORM: the native-git CLI's conditional-export facade + its web stub. The
  // io half (NativeGitCli) is exercised directly by git_cli_test.dart; the web
  // stub and the one-line barrel are the platform seam the VM runner can't load.
  'lib/services/git/git_cli_factory.dart',
  'lib/services/git/git_cli_web.dart',
  // PLATFORM: the native git mirror's conditional-export facade + its web stub.
  // The io half is exercised by native_git_mirror_test.dart against a real repo.
  'lib/services/git/native_git_mirror_factory.dart',
  'lib/services/git/native_git_mirror_stub.dart',
  // PLATFORM: the Matrix egress conditional-export facade — a one-line barrel with
  // no executable lines. Both halves (matrix_http_transport_io/web) are exercised
  // directly by matrix_http_transport_test.dart.
  'lib/collab/matrix_http_transport.dart',
  // PLATFORM: de XMPP-transportfacade is eveneens één kale conditional export
  // zonder uitvoerbare regels. De io-helft wordt door de verbindingstests
  // geraakt; de fail-closed webhelft wordt rechtstreeks getoetst in
  // xmpp_frame_transport_web_test.dart.
  'lib/xmpp/xmpp_frame_transport_platform.dart',
  // PLATFORM: the git draft store's conditional-export facade. Both halves
  // (FileDraftStore, PrefsDraftStore) are exercised by the DeckMirror contract
  // in test/git_deck_mirror_contract_test.dart; only this one-line barrel has no
  // statement for a line counter to reach.
  'lib/services/git/draft_store_factory.dart',
  // PLATFORM: the local CVE database's conditional-export facade + its web half
  // (the feature is desktop-only; the io half is exercised by the ingest tests).
  'lib/services/cve/local_cve_database.dart',
  'lib/services/cve/local_cve_database_web.dart',
  'lib/utils/file_download.dart',
  'lib/utils/file_download_web.dart',
  // PLATFORM: de webhelft van de import-runner (#875). De browser heeft geen
  // tweede isolate, dus draait het parsen daar in-process; onder `flutter test`
  // kiest de conditional import altijd de io-helft, zodat deze nooit geladen
  // wordt. De gevel (`import_runner.dart`) én de io-helft draaien wél op de VM
  // en zijn gedekt door import_isolate_test; de gedeelde kern in
  // `import_task.dart` dekt precies wat deze webromp aanroept.
  'lib/services/import/pipeline/import_runner_web.dart',
  // PLATFORM: de webhelft van de rem op het sluiten van een tabblad. Dit is
  // `dart:js_interop`-code (`beforeunload`); de VM-runner kan haar niet laden.
  // De gevel én de io-helft worden wél uitgevoerd — zie
  // test/web_no_recovery_notice_test.dart.
  'lib/platform/unsaved_work_guard_web.dart',
  // PLATFORM: de webhelft van klembord-HTML (#1595). `Pasteboard.html` via
  // dart:js_interop; de VM-runner laadt deze helft niet. De gevel en de
  // io-helft staan onder test in html_clipboard_markdown_test.dart.
  'lib/platform/clipboard_html_web.dart',
  // NO EXECUTABLE LINES: const data table (345 lines, zero statements).
  'lib/services/cvss/cvss4_lookup.dart',
  // NO EXECUTABLE LINES: const data tables — the finding templates, one file
  // per language, plus the map that gathers them. Their *content* is asserted
  // hard in test/finding_template_languages_test.dart, which parses every
  // template in every language and checks the fixed parts field by field;
  // there is simply no statement here for a line counter to reach.
  'lib/services/finding_templates/all.dart',
  'lib/services/finding_templates/bg.dart',
  'lib/services/finding_templates/cs.dart',
  'lib/services/finding_templates/da.dart',
  'lib/services/finding_templates/de.dart',
  'lib/services/finding_templates/el.dart',
  'lib/services/finding_templates/en.dart',
  'lib/services/finding_templates/es.dart',
  'lib/services/finding_templates/et.dart',
  'lib/services/finding_templates/fi.dart',
  'lib/services/finding_templates/fr.dart',
  'lib/services/finding_templates/fy.dart',
  'lib/services/finding_templates/ga.dart',
  'lib/services/finding_templates/gsw.dart',
  'lib/services/finding_templates/hr.dart',
  'lib/services/finding_templates/hu.dart',
  'lib/services/finding_templates/id.dart',
  'lib/services/finding_templates/it.dart',
  'lib/services/finding_templates/la.dart',
  'lib/services/finding_templates/lt.dart',
  'lib/services/finding_templates/lv.dart',
  'lib/services/finding_templates/mt.dart',
  'lib/services/finding_templates/nl.dart',
  'lib/services/finding_templates/pap.dart',
  'lib/services/finding_templates/pl.dart',
  'lib/services/finding_templates/pt.dart',
  'lib/services/finding_templates/ro.dart',
  'lib/services/finding_templates/sk.dart',
  'lib/services/finding_templates/sl.dart',
  'lib/services/finding_templates/sv.dart',
  'lib/services/finding_templates/tlh.dart',
  'lib/services/finding_templates/tr.dart',
  'lib/services/finding_templates/uk.dart',
  // NO EXECUTABLE LINES: const data table — the settings search index. The
  // entries themselves are asserted in test/settings_search_test.dart, which
  // also guards that every section title in here is still rendered.
  'lib/widgets/dialogs/parts/settings_dialog_search_index.dart',
  // NO EXECUTABLE LINES: an abstract interface (the local CVE database as the
  // UI sees it). Its two implementations are covered separately.
  'lib/services/cve/local_cve_database_api.dart',
  // NO EXECUTABLE LINES: a single enum declaration.
  'lib/widgets/markdown_editor/notes_editor_mode.dart',
  // NO EXECUTABLE LINES: the stand-alone dark presenter palette — nothing but
  // `static const Color` tokens. It used to hold one unreachable line (a private
  // constructor that existed only to block instantiation) and therefore sat at
  // 0% forever, which no test could ever fix. It is now `abstract final class`,
  // the way `finding_severity_palette.dart` already did it, which says the same
  // thing without a statement to reach. Its sibling
  // `image_picker_palette.dart` sat here for the same reason until its tokens
  // became mode-dependent getters; those are executable, so it left this list.
  'lib/theme/presenter_palette.dart',
  // NO EXECUTABLE LINES: `Importer` is de abstracte klasse die één
  // presentatieformaat moet invullen (#772) — drie leden zonder body en verder
  // niets. De implementatie wordt wél uitgevoerd: `PptxImporter` loopt door
  // test/import/pptx_importer_test.dart en test/import/
  // presentation_import_service_test.dart.
  'lib/services/import/importers/importer.dart',
  // NO EXECUTABLE LINES: twee kale enum-declaraties van de import.
  // `SourceFormat` zijn de herkende presentatieformaten, `SlideFailurePolicy`
  // is wat er met een dia gebeurt die niet schoon converteert. Beide worden
  // gelezen in test/import/format_detector_test.dart en
  // test/import/deck_builder_test.dart, maar lcov schrijft geen record voor een
  // bestand zonder uitvoerbare regels.
  'lib/services/import/models/source_format.dart',
  'lib/services/import/models/slide_failure_policy.dart',
};

/// The per-file coverage floor: a lib/ file below this fraction of executed
/// lines counts as untested. RATCHET: may rise, never fall.
///
/// Why 20 and not 80: at 20% a file has at least one line in five that some
/// test really runs — enough that a behaviour change somewhere in it stands a
/// chance of turning a test red. Below that the file is decoration in the
/// report.
///
/// Er is geen budget meer. Tot 2026-07-22 stond hier een `filesBelowFloorBudget`
/// dat mocht meetellen hoeveel bestanden onder de vloer zaten: 39 bij de start,
/// daarna 21, en nu nul. Een getal dat nul is, kan iemand ophogen; een poort die
/// bij élk bestand hard faalt, kan dat niet. Wat hieronder zakt is dus geen
/// getal om bij te stellen maar een test om te schrijven.
///
/// Zit een bestand hier echt niet zinnig te dekken, dan hoort het niet in een
/// budget maar in [uncoveredBaseline] hierboven — en dat is een lijst met een
/// reden per regel, geen teller.
const int perFileFloorPercent = 34;

/// Translation data carries no logic; it is gated by the l10n tests instead.
bool _isTranslationData(String path) => path.contains('lib/l10n/translations/');

void main(List<String> args) {
  final report = File('coverage/lcov.info');
  if (!report.existsSync()) {
    stderr.writeln(
      'coverage/lcov.info not found — run "flutter test --coverage" first.',
    );
    exit(1);
  }

  var found = 0;
  var hit = 0;
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      found += int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      hit += int.tryParse(line.substring(3)) ?? 0;
    }
  }

  final pct = found == 0 ? 0.0 : hit / found * 100;
  stdout.writeln(
    'Line coverage: $hit/$found (${pct.toStringAsFixed(1)}%) '
    'across ${_fileCount(report)} instrumented files.',
  );

  double? min;
  var requireInstrumented = false;
  var perFileFloor = false;
  for (final arg in args) {
    if (arg.startsWith('--min=')) min = double.tryParse(arg.substring(6));
    if (arg == '--require-instrumented') requireInstrumented = true;
    if (arg == '--per-file-floor') perFileFloor = true;
  }

  var failed = false;

  if (requireInstrumented && !_checkInstrumented(report)) failed = true;

  if (perFileFloor && !_checkPerFileFloor(report)) failed = true;

  if (min != null && pct < min) {
    stderr.writeln(
      'Coverage ${pct.toStringAsFixed(1)}% is below the required '
      '${min.toStringAsFixed(1)}%.',
    );
    failed = true;
  }

  if (failed) exit(1);
}

/// Fails when a lib/ file is absent from the report and not baselined — i.e. no
/// test imports it at all. Returns true when the tree is clean.
bool _checkInstrumented(File report) {
  final instrumented = <String>{};
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) instrumented.add(line.substring(3).trim());
  }

  final absent = <String>[];
  for (final entry in Directory('lib').listSync(recursive: true)) {
    if (entry is! File || !entry.path.endsWith('.dart')) continue;
    final path = entry.path.replaceAll(r'\', '/');
    if (_isTranslationData(path)) continue;
    if (instrumented.contains(path)) continue;
    if (uncoveredBaseline.contains(path)) continue;
    absent.add(path);
  }
  absent.sort();

  if (absent.isNotEmpty) {
    stderr.writeln(
      '${absent.length} lib/ file(s) are in no test at all, so they never reach '
      'the coverage denominator — the percentage above cannot see them. Write a '
      'test, or (only for a platform half or a file with no executable lines) '
      'add it to uncoveredBaseline in tool/coverage_summary.dart:\n'
      '    ${absent.join('\n    ')}',
    );
    return false;
  }

  // Ratchet the other way: a baselined file that got covered should leave.
  final verdict = classifyBaselined(
    baseline: uncoveredBaseline,
    tallies: {for (final f in _perFile(report)) f.path: f},
  );
  if (verdict.leavers.isNotEmpty) {
    stdout.writeln(
      'Tip: ${verdict.leavers.length} baselined file(s) now run enough of '
      'themselves to leave — drop them from uncoveredBaseline '
      '(tool/coverage_summary.dart) to lock in the win:\n'
      '    ${verdict.leavers.join('\n    ')}',
    );
  }
  if (verdict.tooThin.isNotEmpty) {
    stdout.writeln(
      'Note: ${verdict.tooThin.length} baselined file(s) are in the report but '
      'run less than $perFileFloorPercent% of their own lines. Keep them '
      'baselined until a test covers them — dropping them now trips the '
      'per-file floor:\n    ${verdict.tooThin.join('\n    ')}',
    );
  }
  return true;
}

/// What the report says about the files still sitting in [uncoveredBaseline]:
/// which may leave the list, and which are in the report but too thinly run to
/// survive outside it.
typedef BaselineVerdict = ({List<String> leavers, List<String> tooThin});

/// Sorts the baselined files that carry a report record into the two groups of
/// [BaselineVerdict], each rendered as `path (hit/found)`.
///
/// Being in the report is not enough to leave. The per-file floor skips
/// baselined files, so recommending one that lands under [perFileFloorPercent]
/// hands the next reader a tip that breaks the gate the moment they follow it —
/// which is exactly what the F3 native-media binding did: a preflight tile
/// imports it, so it sits in the report at 0 of 9 lines. Those are named
/// separately, because "instrumented but barely executed" is a different problem
/// and its fix is a test, not a list edit.
///
/// A baselined file absent from [tallies] is not mentioned at all: either no
/// test imports it, or it has no executable line for the floor to judge it by.
/// In both cases its baseline reason still holds.
BaselineVerdict classifyBaselined({
  required Set<String> baseline,
  required Map<String, ({String path, int hit, int found})> tallies,
}) {
  final leavers = <String>[];
  final tooThin = <String>[];
  for (final path in baseline.toList()..sort()) {
    final tally = tallies[path];
    if (tally == null) continue;
    final clearsFloor = tally.hit * 100 >= perFileFloorPercent * tally.found;
    (clearsFloor ? leavers : tooThin).add(
      '$path (${tally.hit}/${tally.found})',
    );
  }
  return (leavers: leavers, tooThin: tooThin);
}

/// One file's line tally, as lcov reports it.
typedef _FileCoverage = ({String path, int hit, int found});

/// Reads every per-file record from the lcov report. Files with no executable
/// line at all are dropped: they carry no percentage to speak of.
List<_FileCoverage> _perFile(File report) {
  final result = <_FileCoverage>[];
  String? path;
  var found = 0;
  var hit = 0;
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      path = line.substring(3).trim();
      found = 0;
      hit = 0;
    } else if (line.startsWith('LF:')) {
      found = int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      hit = int.tryParse(line.substring(3)) ?? 0;
    } else if (line.trim() == 'end_of_record' && path != null && found > 0) {
      result.add((path: path, hit: hit, found: found));
    }
  }
  return result;
}

/// Faalt zodra één lib/-bestand onder [perFileFloorPercent] zakt. Geen budget,
/// geen marge: elk bestand hieronder is er een waar een gedragswijziging geen
/// enkele test rood maakt. Geeft true wanneer de boom schoon is.
bool _checkPerFileFloor(File report) {
  final below =
      _perFile(report)
          .where((f) => !_isTranslationData(f.path))
          // Honour uncoveredBaseline here too, like _checkInstrumented and the
          // average floor. It never mattered before: those entries are platform
          // *other*-halves (a `_web` half on this io VM), never compiled here, so
          // they had no report record to floor-check. The F3 native-media binding
          // is different — it IS compiled on every platform, so an import (via the
          // preflight tile) puts it in the report at 0%. Without this skip the
          // approved exemption would be defeated by this one floor.
          .where((f) => !uncoveredBaseline.contains(f.path))
          .where((f) => f.hit * 100 < perFileFloorPercent * f.found)
          .toList()
        ..sort((a, b) {
          final byShare = (a.hit / a.found).compareTo(b.hit / b.found);
          return byShare != 0 ? byShare : a.path.compareTo(b.path);
        });

  final dead = below.where((f) => f.hit == 0).length;
  stdout.writeln(
    'Per-file floor: ${below.length} file(s) below $perFileFloorPercent% '
    'executed lines ($dead of them at zero); budget is 0.',
  );

  if (below.isNotEmpty) {
    stderr.writeln(
      '${below.length} lib/ file(s) run less than $perFileFloorPercent% of '
      'their lines, and er is geen budget meer. Een test die een bestand wél '
      'importeert maar niet uitvoert, houdt het in de noemer terwijl het '
      'gemiddelde het verbergt — daar is deze vloer voor. Schrijf een test, of '
      'zet het bestand met een reden in uncoveredBaseline wanneer het een '
      'platformhelft is of geen uitvoerbare regels heeft:\n'
      '${below.map(_describe).join('\n')}',
    );
    return false;
  }
  return true;
}

String _describe(_FileCoverage f) {
  final pct = (f.hit / f.found * 100).toStringAsFixed(1).padLeft(5);
  return '    $pct%  ${f.hit}/${f.found}  ${f.path}';
}

int _fileCount(File report) {
  var n = 0;
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) n++;
  }
  return n;
}
