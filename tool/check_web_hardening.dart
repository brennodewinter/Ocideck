// Verifies that a built web bundle keeps its security hardening intact, so a
// future change can't silently re-introduce a third-party dependency or weaken
// the Content-Security-Policy. Run after `make build-web` (the `make check-web`
// target does both). Exits non-zero with a list of every failed invariant.
//
// What it asserts about build/web:
//   * index.html ships a CSP that locks scripts to 'self' + 'wasm-unsafe-eval'
//     (NOT 'unsafe-eval'/'unsafe-inline') and keeps connect-src first-party.
//   * CanvasKit is self-hosted (local wasm + useLocalCanvasKit flag), so the
//     engine never fetches it from the gstatic CDN.
//   * The UI font is bundled, so text needs no fonts.gstatic.com fetch.

import 'dart:io';

void main() {
  final webDir = Directory('build/web');
  if (!webDir.existsSync()) {
    stderr.writeln(
      'build/web not found — run `make build-web` first (or `make check-web`).',
    );
    exit(2);
  }

  final failures = <String>[];
  void require(bool ok, String message) {
    if (!ok) failures.add(message);
  }

  // ── index.html / Content-Security-Policy ───────────────────────────────────
  final indexHtml = File('build/web/index.html');
  if (!indexHtml.existsSync()) {
    failures.add('build/web/index.html is missing.');
  } else {
    final html = indexHtml.readAsStringSync();
    final csp = _extractCsp(html);
    if (csp == null) {
      failures.add('No Content-Security-Policy meta tag in index.html.');
    } else {
      final directives = _parseCsp(csp);
      final scriptSrc = directives['script-src'] ?? const [];
      // script-src is the XSS-critical axis: first-party + the narrow wasm token
      // only — never the dynamic-code escapes. (style-src legitimately keeps
      // 'unsafe-inline'; the Flutter engine injects styles at runtime.)
      require(
        scriptSrc.contains("'self'"),
        "CSP script-src must allow 'self'.",
      );
      require(
        scriptSrc.contains("'wasm-unsafe-eval'"),
        "CSP script-src must allow 'wasm-unsafe-eval' (CanvasKit needs it).",
      );
      require(
        !scriptSrc.contains("'unsafe-inline'"),
        "CSP script-src must NOT allow 'unsafe-inline'.",
      );
      // No directive should ever permit the JS eval escape ('wasm-unsafe-eval'
      // is a distinct token and is fine).
      require(
        !directives.values.any((tokens) => tokens.contains("'unsafe-eval'")),
        "CSP must NOT allow 'unsafe-eval' anywhere (use 'wasm-unsafe-eval').",
      );
      // connect-src allows https: on top of 'self' for the user-initiated
      // URL-import (the browser's CORS policy still gates every cross-origin
      // read). Anything broader (http:, *, data:) would reopen the holes this
      // check exists to guard.
      require(
        _eq(directives['connect-src'], ["'self'", 'https:']),
        "CSP connect-src must be exactly 'self' https: "
        '(first-party plus TLS-only URL-import fetches).',
      );
      require(
        _eq(directives['object-src'], ["'none'"]),
        "CSP should set object-src 'none'.",
      );
      // form-action does NOT fall back to default-src, so leaving it out is not
      // "covered by 'self'" — it leaves form submission unrestricted. The app
      // paints into a canvas and submits no HTML forms, so 'none' costs nothing
      // and closes the destination an injected <form> would otherwise reach.
      // Found by the ZAP baseline (rule 10055), which is exactly the class of
      // gap a directive-by-directive read of the policy tends to miss.
      require(
        _eq(directives['form-action'], ["'none'"]),
        "CSP must set form-action 'none' (it does not fall back to default-src).",
      );
      // default-src is the fallback for every unlisted fetch directive; keep it
      // first-party so a future directive removal can't silently open a hole.
      require(
        _eq(directives['default-src'], ["'self'"]),
        "CSP default-src must be exactly 'self'.",
      );
      // base-uri must stay 'self' (Flutter needs <base href>); a widened
      // base-uri lets injected markup repoint relative URLs.
      require(
        _eq(directives['base-uri'], ["'self'"]),
        "CSP base-uri must be exactly 'self'.",
      );
      // The media/frame axes may use 'self'/data:/blob: but must never gain a
      // remote origin — that would re-open the web SSRF/beacon hole the bundle
      // closes by being first-party only.
      for (final d in ['img-src', 'media-src', 'frame-src', 'child-src']) {
        require(
          directives.containsKey(d),
          'CSP must declare $d (first-party only).',
        );
        require(
          !_hasRemoteOrigin(directives[d]),
          'CSP $d must not allow a remote origin (found: '
          '${directives[d]?.join(' ')}).',
        );
      }
    }
  }

  // ── CanvasKit is self-hosted, not pulled from the gstatic CDN ───────────────
  require(
    File('build/web/canvaskit/canvaskit.wasm').existsSync(),
    'CanvasKit wasm is not self-hosted (build with --no-web-resources-cdn).',
  );
  final bootstrap = File('build/web/flutter_bootstrap.js');
  require(
    bootstrap.existsSync() &&
        bootstrap.readAsStringSync().contains('useLocalCanvasKit":true'),
    'Loader is not pinned to local CanvasKit (useLocalCanvasKit must be true).',
  );

  // ── UI font is bundled (no fonts.gstatic.com fetch) ─────────────────────────
  require(
    _findFile(webDir, 'Roboto-Variable.ttf') != null,
    'Bundled Roboto UI font not found in build/web (would fall back to gstatic).',
  );

  if (failures.isEmpty) {
    stdout.writeln(
      'Web hardening OK: strict CSP, self-hosted CanvasKit, bundled UI font.',
    );
    exit(0);
  }
  stderr.writeln('Web hardening check FAILED:');
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  exit(1);
}

/// Splits a CSP into `{directive: [tokens]}`, e.g. `script-src 'self' x` →
/// `{'script-src': ["'self'", 'x']}`.
Map<String, List<String>> _parseCsp(String csp) {
  final out = <String, List<String>>{};
  for (final part in csp.split(';')) {
    final tokens = part.trim().split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    if (tokens.isEmpty) continue;
    out[tokens.first.toLowerCase()] = tokens.sublist(1);
  }
  return out;
}

/// True when any token is a remote origin — an `http(s):` scheme, a
/// protocol-relative `//host`, a bare host, or the `*` wildcard. First-party
/// keywords (`'self'`) and local schemes (`data:`, `blob:`, `filesystem:`,
/// `mediastream:`) are allowed.
bool _hasRemoteOrigin(List<String>? tokens) {
  if (tokens == null) return false;
  const localSchemes = {
    "'self'",
    'data:',
    'blob:',
    'filesystem:',
    'mediastream:',
    "'none'",
  };
  for (final t in tokens) {
    if (localSchemes.contains(t)) continue;
    if (t == '*' ||
        t.startsWith('http') ||
        t.startsWith('//') ||
        t.contains('.')) {
      return true;
    }
  }
  return false;
}

/// True when [tokens] equals [expected] (order-independent).
bool _eq(List<String>? tokens, List<String> expected) {
  if (tokens == null || tokens.length != expected.length) return false;
  final a = [...tokens]..sort();
  final b = [...expected]..sort();
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Returns the `content="..."` of the CSP meta tag, or null when absent.
String? _extractCsp(String html) {
  final match = RegExp(
    r'<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]*)"',
    caseSensitive: false,
  ).firstMatch(html);
  return match?.group(1);
}

/// Recursively finds the first file named [name] under [dir], or null.
File? _findFile(Directory dir, String name) {
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File && e.uri.pathSegments.last == name) return e;
  }
  return null;
}
