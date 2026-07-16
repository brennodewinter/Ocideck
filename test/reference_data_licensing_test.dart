import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secmodule/sec_reference_inventory.dart';

/// Every bundled reference dataset must be recorded in `LICENSE_COMPLIANCE.md`
/// with its terms — that document is what an auditor and the CRA are shown, and
/// it ships inside the app (Settings → Documentatie), which is also how OciDeck
/// discharges the attribution that CC-BY-SA-4.0 and MITRE's terms ask for.
///
/// This guard exists because the alternative failed. The compliance doc stated
/// that no OWASP WSTG checklist content was bundled — and named the very
/// condition that would undo it ("should verbatim checklist content be bundled
/// later…") — while `wstg_catalog.dart` had shipped the 97 verbatim titles from
/// the start. Nothing broke, because nothing checked. The same lapse left the
/// 969-entry MITRE CWE asset out of the table.
///
/// So the rule is mechanical now: a dataset the app offers is a dataset whose
/// licence is written down. `SecReferenceInventory` is the app's own registry of
/// what it can serve, so a sixth catalogue cannot appear in the UI without
/// failing here first.
void main() {
  final doc = File('docs/LICENSE_COMPLIANCE.md').readAsStringSync();

  /// Catalogue name (as the inventory calls it) → a phrase that must appear in
  /// the licence table for it. Adding a dataset means adding it in **both**
  /// places; that is the whole point of the map.
  const recorded = {
    'Zwakheden (CWE)': 'MITRE Terms of Use',
    'Testgevallen (WSTG)': 'CC-BY-SA-4.0',
    'MIAUW-eisen': 'EUPL-1.2 (same as OciDeck)',
    'CVSS-scoretabel': 'FIRST.Org',
    'Bevindingsjablonen': 'EUPL-1.2 — our content',
  };

  test('every catalogue the app serves has its licence recorded', () {
    final offered = SecReferenceInventory.snapshot()
        .map((c) => c.name)
        .toList();

    expect(
      offered.toSet(),
      equals(recorded.keys.toSet()),
      reason:
          'The reference catalogues changed. A dataset OciDeck bundles ships to '
          'every user in every build, so its terms belong in '
          'docs/LICENSE_COMPLIANCE.md — add the row, then add it here.',
    );

    for (final entry in recorded.entries) {
      expect(
        doc.contains(entry.value),
        isTrue,
        reason:
            'LICENSE_COMPLIANCE.md no longer states the terms for '
            '"${entry.key}" (expected to find "${entry.value}").',
      );
    }
  });

  test('the WSTG attribution names the licensor and the licence', () {
    // CC-BY-SA-4.0 asks for the creator, the licence and a link. Anything less
    // is a mention, not an attribution.
    for (final required in [
      'OWASP Foundation',
      'creativecommons.org/licenses/by-sa/4.0',
      'owasp.org/www-project-web-security-testing-guide',
      'share-alike',
    ]) {
      expect(
        doc.contains(required),
        isTrue,
        reason: 'The WSTG attribution is missing "$required".',
      );
    }
  });

  test('the superseded "no WSTG content is bundled" claim is gone', () {
    // The exact sentence that was false for as long as the module shipped. It
    // may be quoted as history, but never again as a statement of fact.
    expect(
      doc.contains(
        'No WSTG / MASTG / ISTG / FSTM text or checklist content is',
      ),
      isFalse,
      reason:
          'That claim is false: wstg_catalog.dart bundles the 97-test checklist '
          'index. If content is ever genuinely removed, rewrite the claim rather '
          'than restoring this sentence.',
    );
  });
}
