import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that every place telling someone where to report a security problem
/// names the same address.
///
/// This is not hypothetical tidiness: `.github/ISSUE_TEMPLATE/config.yml` sent
/// reporters to `security@vigilis.nl` while `SECURITY.md` and
/// `CODE_OF_CONDUCT.md` both said `security@librekat.nl`. Someone following the
/// tracker's own "report privately" link mailed an address the project does not
/// document — and the mistake sat in the one path a reporter actually walks.
///
/// `SECURITY.md` is the single source of truth here, because that is the
/// document the tracker, the README and the templates all point at. Every other
/// occurrence must agree with it.
void main() {
  /// Text files that may plausibly tell a reader where to report. Deliberately
  /// enumerated rather than globbed over the whole tree: a stray address in a
  /// vendored dependency or a build artefact is not ours to police, and a
  /// tree-wide sweep would turn this guard into a source of false alarms.
  const scanned = <String>[
    'SECURITY.md',
    'README.md',
    'CODE_OF_CONDUCT.md',
    'CONTRIBUTING.md',
    '.github/ISSUE_TEMPLATE/config.yml',
    '.github/ISSUE_TEMPLATE/bug_report.md',
    '.github/ISSUE_TEMPLATE/feature_request.md',
    '.github/PULL_REQUEST_TEMPLATE.md',
  ];

  /// Matches an address in the `security@…` family, however it is wrapped —
  /// bare, in `mailto:`, or inside Markdown bold. Only the address itself is
  /// captured.
  final addressPattern = RegExp(r'security@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

  late final String canonical;

  setUpAll(() {
    final security = File('SECURITY.md');
    expect(
      security.existsSync(),
      isTrue,
      reason: 'SECURITY.md is the source of truth for this guard and must exist',
    );
    final matches = addressPattern.allMatches(security.readAsStringSync());
    expect(
      matches,
      isNotEmpty,
      reason: 'SECURITY.md names no security@ address to compare against',
    );
    canonical = matches.first.group(0)!;
  });

  test('every security contact address matches the one in SECURITY.md', () {
    final offenders = <String>[];

    for (final path in scanned) {
      final file = File(path);
      // A missing file is not this guard's business — docs_registration_test
      // covers what must exist. Skipping keeps the failure message about
      // addresses only.
      if (!file.existsSync()) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in addressPattern.allMatches(lines[i])) {
          final found = match.group(0)!;
          if (found != canonical) {
            offenders.add('$path:${i + 1} names $found');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'SECURITY.md says to report to $canonical, but these disagree:\n'
          '  ${offenders.join('\n  ')}\n'
          'A reporter follows whichever one they happen to read first.',
    );
  });

  test('the canonical address is on the foundation domain', () {
    // A weak but useful second assertion: it catches the case where someone
    // "fixes" the mismatch by changing SECURITY.md to the wrong address, which
    // would make the test above green for the wrong reason.
    expect(
      canonical,
      endsWith('@librekat.nl'),
      reason:
          'The publisher is Stichting LibreKAT; security reports belong on its '
          'own domain, not on a domain the project does not control.',
    );
  });
}
