// Freshness monitor for the third-party CI versions we pin to an EXACT value.
//
//   dart run tool/check_pinned_versions.dart            (or: make check-pins)
//   dart run tool/check_pinned_versions.dart --offline  (validate manifest only)
//
// Unlike the vendored JS bundles (which `make deps-check` scans for CVEs), a
// pin drifting behind its upstream is not a vulnerability in itself — it just
// means a bump is available and unnoticed. This is the CI analogue of that
// check: it reads .github/pinned-ci-versions.json and asks each upstream for
// its latest version, so a stale pin stands out instead of silently ageing.
//
// It covers two kinds of pin, because they rot the same way while looking
// nothing alike in the workflow (#802):
//
//   actions — `uses: owner/repo@vX.Y.Z`
//   tools   — a binary a `run:` block downloads by version (the three scanners)
//
// The scanners are the reason this exists. A secret scanner that stands still
// keeps exiting 0 while missing the credential shapes invented after it, and
// "green" then means "it did not know what to look for" — the same failure as a
// history scan on a shallow clone. Floating major-tag Actions (…@v4) auto-update
// and are out of scope here by design.
//
// This tool answers "is there something newer". That the pins in the manifest
// actually MATCH the workflows is a different question, checked offline and
// inside the suite by test/pinned_versions_manifest_test.dart.
//
// Exit codes:  0 = every pin is on its latest release (or --offline and the
//                  manifest is well formed)
//              1 = at least one pin is behind — bump it + the manifest
//              2 = could not run the check (missing/invalid manifest, unknown
//                  source, or the upstream API was unreachable)
//
// Advisory: it is NOT wired into `make check`/`check-full` (it needs network and
// a bump is a prompt, not a regression). Run it periodically, like
// `make deps-outdated`.

import 'dart:convert';
import 'dart:io';

const _manifestPath = '.github/pinned-ci-versions.json';

/// One pinned thing, flattened from either manifest list so the reporting loop
/// does not care which kind it came from.
class _Pin {
  _Pin({
    required this.label,
    required this.version,
    required this.source,
    required this.api,
  });

  final String label;
  final String version;
  final String source;
  final String api;
}

Future<void> main(List<String> args) async {
  final offline = args.contains('--offline');

  final manifestFile = File(_manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('No $_manifestPath — cannot check pinned versions.');
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

  final List<_Pin> pins;
  try {
    pins = _readPins(manifest);
  } on FormatException catch (e) {
    stderr.writeln('$_manifestPath is malformed: ${e.message}');
    exit(2);
  }

  stdout.writeln('== OciDeck check: pinned CI versions ==');
  stdout.writeln('Manifest: $_manifestPath  (${pins.length} pinned)\n');

  final behind = <String>[];
  var networkFailed = false;

  for (final pin in pins) {
    String status;
    if (offline) {
      status = 'skipped (--offline)';
    } else {
      final latest = await _latestVersion(pin.source, pin.api);
      if (latest == null) {
        status = 'UPSTREAM UNREACHABLE';
        networkFailed = true;
      } else if (_isBehind(pin.version, latest)) {
        status = 'BEHIND — latest is $latest';
        behind.add('${pin.label}@${pin.version} → $latest');
      } else {
        status = 'up to date ($latest)';
      }
    }

    stdout.writeln('  ${pin.label}@${pin.version}');
    stdout.writeln('      latest : $status');
  }

  stdout.writeln('');

  if (behind.isEmpty && !networkFailed) {
    stdout.writeln(
      offline
          ? 'OK — the manifest is well formed (versions not checked).'
          : 'OK — every pinned CI version is on its latest release.',
    );
    exit(0);
  }

  if (behind.isNotEmpty) {
    stderr.writeln('BEHIND — ${behind.length} pinned version(s):');
    for (final p in behind) {
      stderr.writeln('  $p');
    }
    stderr.writeln(
      '  Bump the version in EVERY workflow that carries it AND in\n'
      '  $_manifestPath in the same commit — the suite fails if they\n'
      '  disagree. Advisory — review the changelog of the new release first.',
    );
    exit(1);
  }

  // Only network trouble; nothing is provably behind.
  stderr.writeln(
    'COULD NOT VERIFY — an upstream API was unreachable.\n'
    '  Re-run with network access, or `--offline` to validate the manifest only.',
  );
  exit(2);
}

/// Flattens both manifest lists into one, rejecting an entry that is missing a
/// field the check needs. Throwing here rather than skipping is deliberate: a
/// half-filled entry that got silently ignored would be a pin nobody watches,
/// which is the exact thing this tool exists to prevent.
List<_Pin> _readPins(Map<String, dynamic> manifest) {
  final pins = <_Pin>[];

  String field(Map<String, dynamic> entry, String key, String kind) {
    final value = entry[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('a $kind entry has no `$key`');
    }
    return value;
  }

  for (final entry
      in (manifest['actions'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
    pins.add(
      _Pin(
        label: field(entry, 'uses', 'actions'),
        version: field(entry, 'version', 'actions'),
        source: field(entry, 'source', 'actions'),
        api: field(entry, 'api', 'actions'),
      ),
    );
  }

  for (final entry
      in (manifest['tools'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
    pins.add(
      _Pin(
        label: field(entry, 'name', 'tools'),
        version: field(entry, 'version', 'tools'),
        source: field(entry, 'source', 'tools'),
        api: field(entry, 'api', 'tools'),
      ),
    );
  }

  if (pins.isEmpty) {
    throw const FormatException('no pins listed at all');
  }
  for (final pin in pins) {
    if (pin.source != 'github_release' && pin.source != 'pypi') {
      throw FormatException(
        '${pin.label} has an unknown source "${pin.source}" '
        '(expected github_release or pypi)',
      );
    }
  }
  return pins;
}

/// Latest published version from [api], or null if it could not be
/// reached/parsed. Two shapes, because the three scanners do not all ship the
/// same way: a GitHub release carries `tag_name`, PyPI carries `info.version`.
Future<String?> _latestVersion(String source, String api) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(api));
    // GitHub's API rejects requests without a User-Agent.
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'ocideck-pinned-versions-check',
    );
    req.headers.set(
      HttpHeaders.acceptHeader,
      source == 'pypi' ? 'application/json' : 'application/vnd.github+json',
    );
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return null;
    }
    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (source == 'pypi') {
      return (data['info'] as Map<String, dynamic>?)?['version'] as String?;
    }
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
