// Freshness monitor for the third-party CI Actions we pin to an EXACT version.
//
//   dart run tool/check_pinned_actions.dart            (or: make check-actions)
//   dart run tool/check_pinned_actions.dart --offline  (validate manifest only)
//
// Unlike the vendored JS bundles (which `make deps-check` scans for CVEs), a
// pinned Action drifting behind its upstream is not a vulnerability in itself —
// it just means a bump is available and unnoticed. This is the Action analogue
// of that check: it reads .github/pinned-actions.json and asks each Action's
// release API for the latest tag, so a version bump stands out instead of
// silently ageing. Floating major-tag Actions (…@v4) auto-update and are not
// listed, so they are out of scope here by design.
//
// Exit codes:  0 = every pinned Action is on its latest release (or --offline)
//              1 = at least one pinned Action is behind — bump it + the manifest
//              2 = could not run the check (missing/invalid manifest, or the
//                  release API was unreachable)
//
// Advisory: it is NOT wired into `make check`/`check-full` (it needs network and
// a bump is a prompt, not a regression). Run it periodically, like
// `make deps-outdated`.

import 'dart:convert';
import 'dart:io';

const _manifestPath = '.github/pinned-actions.json';

Future<void> main(List<String> args) async {
  final offline = args.contains('--offline');

  final manifestFile = File(_manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('No $_manifestPath — cannot check pinned Actions.');
    exit(2);
  }

  final Map<String, dynamic> manifest;
  try {
    manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException catch (e) {
    stderr.writeln('$_manifestPath is not valid JSON: $e');
    exit(2);
  }
  final actions = (manifest['actions'] as List).cast<Map<String, dynamic>>();

  stdout.writeln('== OciDeck check: pinned CI Actions ==');
  stdout.writeln('Manifest: $_manifestPath  (${actions.length} pinned)\n');

  final behind = <String>[];
  var networkFailed = false;

  for (final a in actions) {
    final uses = a['uses'] as String;
    final pinned = a['version'] as String;
    final api = a['releases_api'] as String;

    String status;
    if (offline) {
      status = 'skipped (--offline)';
    } else {
      final latest = await _latestRelease(api);
      if (latest == null) {
        status = 'RELEASE API UNREACHABLE';
        networkFailed = true;
      } else if (_isBehind(pinned, latest)) {
        status = 'BEHIND — latest is $latest';
        behind.add('$uses@$pinned → $latest');
      } else {
        status = 'up to date ($latest)';
      }
    }

    stdout.writeln('  $uses@$pinned');
    stdout.writeln('      latest : $status');
  }

  stdout.writeln('');

  if (behind.isEmpty && !networkFailed) {
    stdout.writeln('OK — every pinned Action is on its latest release.');
    exit(0);
  }

  if (behind.isNotEmpty) {
    stderr.writeln('BEHIND — ${behind.length} pinned Action(s):');
    for (final p in behind) {
      stderr.writeln('  $p');
    }
    stderr.writeln(
      '  Bump the `uses:` in the workflow AND the version in\n'
      '  $_manifestPath in the same commit. Advisory — review the changelog\n'
      '  of the new release before upgrading.',
    );
    exit(1);
  }

  // Only network trouble; nothing is provably behind.
  stderr.writeln(
    'COULD NOT VERIFY — a release API was unreachable.\n'
    '  Re-run with network access, or `--offline` to validate the manifest only.',
  );
  exit(2);
}

/// Latest non-prerelease tag from a GitHub-style `releases/latest` endpoint, or
/// null if it could not be reached/parsed.
Future<String?> _latestRelease(String api) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(api));
    // GitHub's API rejects requests without a User-Agent.
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'ocideck-pinned-actions-check',
    );
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return null;
    }
    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    return data['tag_name'] as String?;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// True when [latest] is a strictly newer release than [pinned]. Both are
/// compared as dotted numeric versions with an optional leading `v`; a tag that
/// is not purely numeric falls back to "differs → treat as behind" so an
/// unexpected format errs on the side of a visible reminder.
bool _isBehind(String pinned, String latest) {
  final p = _parts(pinned);
  final l = _parts(latest);
  if (p == null || l == null) {
    return _norm(pinned) != _norm(latest);
  }
  for (var i = 0; i < 3; i++) {
    if (l[i] != p[i]) return l[i] > p[i];
  }
  return false;
}

String _norm(String v) => v.startsWith('v') ? v.substring(1) : v;

List<int>? _parts(String v) {
  final segs = _norm(v).split('.');
  if (segs.length != 3) return null;
  final out = <int>[];
  for (final s in segs) {
    final n = int.tryParse(s);
    if (n == null) return null;
    out.add(n);
  }
  return out;
}
