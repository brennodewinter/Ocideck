import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-scan guard (in the spirit of asset_path_guard_test.dart) against the
/// class of bug fixed in "Close SSRF on the live remote-media path": a network
/// sink that turns a (possibly deck-supplied) URL into a request without going
/// through `NetGuard`. New sinks must apply the guard:
///   * a deck-supplied media URL → `NetGuard.isAllowedMediaUrlResolved` before
///     `NetworkImage` / `VideoPlayerController.networkUrl`;
///   * a raw `HttpClient` → `NetGuard.safeResolve(Trusted)` + socket pinning.
///
/// The allowlist is by FILE (stable across line edits): these files already
/// apply the guard. A sink appearing in any *other* file fails this test —
/// forcing a conscious decision to route it through NetGuard rather than
/// silently reintroducing the hole.
void main() {
  Iterable<File> dartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  String rel(File f) => f.path.replaceFirst(RegExp(r'^.*/lib/'), 'lib/');

  void scan({
    required RegExp sink,
    required Set<String> allowedFiles,
    required String guidance,
  }) {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      if (allowedFiles.contains(rel(file))) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue; // skip comments
        if (sink.hasMatch(line)) {
          offenders.add('${rel(file)}:${i + 1}  ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: '$guidance\n${offenders.join('\n')}');
  }

  test('media fetch sinks stay behind the NetGuard resolve gate', () {
    scan(
      sink: RegExp(r'NetworkImage\(|\.networkUrl\(|Image\.network\('),
      allowedFiles: {
        'lib/utils/image_limits.dart', // cappedNetworkImage wrapper
        'lib/widgets/slides/previews/media_previews.dart', // gated callers
        // media_previews.dart was split for size; its gated image sink now
        // lives in this part of the same slide_preview library.
        'lib/widgets/slides/previews/media_previews_image.dart',
      },
      guidance:
          'New remote-media fetch sink. Gate the URL on '
          'NetGuard.isAllowedMediaUrlResolved before fetching, and add the file '
          'to the allowlist:',
    );
  });

  test('raw HttpClient use stays where the host is resolved and pinned', () {
    scan(
      sink: RegExp(r'HttpClient\('),
      allowedFiles: {
        'lib/utils/net_guard.dart',
        // importFromUrl: safeResolve + pin (import-part van file_service).
        'lib/services/parts/file_service_import.dart',
        'lib/services/webdav_service.dart', // safeResolveTrusted + pin
      },
      guidance:
          'New raw HttpClient. Resolve the host through NetGuard.safeResolve '
          '(or safeResolveTrusted) and pin the socket to the returned address, '
          'then add the file to the allowlist:',
    );
  });
}
