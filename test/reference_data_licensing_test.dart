import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reference content retained for legacy slides must keep its attribution even
/// after the module and its inventory UI have been retired.
void main() {
  final doc = File('docs/LICENSE_COMPLIANCE.md').readAsStringSync();

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

  group('the files say it themselves', () {
    /// A file whose only licence statement lives in a document elsewhere reads
    /// as ours. Someone copying `wstg_catalog.dart` into another EUPL project —
    /// or an AI summarising the repo — sees a Dart file among other Dart files
    /// and infers the repository licence. CC-BY-SA-4.0 and MITRE's terms both
    /// want the attribution attached to the material, not filed next to it.
    const heads = <String, List<String>>{
      'lib/services/wstg_catalog.dart': [
        'NOT EUPL-1.2',
        'CC-BY-SA-4.0',
        'OWASP Foundation',
        'creativecommons.org/licenses/by-sa/4.0/',
        'Share-alike',
      ],
      'lib/services/mastg_catalog.dart': [
        'NOT EUPL-1.2',
        'CC-BY-SA-4.0',
        'OWASP Foundation',
        'creativecommons.org/licenses/by-sa/4.0/',
        'Share-alike',
      ],
      'lib/services/maswe_catalog.dart': [
        'NOT EUPL-1.2',
        'CC-BY-SA-4.0',
        'OWASP Foundation',
        'creativecommons.org/licenses/by-sa/4.0/',
        'Share-alike',
      ],
    };

    for (final entry in heads.entries) {
      test('${entry.key} carries its own licence header', () {
        // Only the header: a mention further down the file is not a notice a
        // reader meets first.
        final head = File(entry.key).readAsLinesSync().take(30).join('\n');
        for (final needle in entry.value) {
          expect(
            head.contains(needle),
            isTrue,
            reason: '${entry.key} no longer states "$needle" in its header.',
          );
        }
      });
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
