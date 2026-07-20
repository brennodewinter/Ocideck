import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-scan guard (in the spirit of asset_path_guard_test.dart) against the
/// bug class fixed in "de handtekening door dezelfde poort als elke andere
/// afbeelding": decoding deck-supplied bytes with a bare `Image.memory` /
/// `MemoryImage`, which decodes at native resolution and so ignores
/// [kMaxImageDecodeDimension].
///
/// The threat is a decode bomb: a uniformly-coloured 30000x30000 PNG is a few
/// KB on disk and ~3.6 GB as RGBA. A deck is a file someone can send you, and
/// the embedded signature (`ocideck_sig_image`) rides along in the front matter,
/// so opening the deck must never be enough to exhaust memory. A layout
/// constraint (`height: 44 * scale`) is not a decode constraint — only
/// `cappedMemoryImage` bounds both axes.
///
/// `pw.MemoryImage` is the `pdf` package's own unrelated class and is fed the
/// app's own rasteriser output, not deck bytes; it is not matched.
void main() {
  test('deck-supplied bytes are never decoded with a bare MemoryImage', () {
    final antiPattern = RegExp(r'\bImage\.memory\(|\bMemoryImage\(');

    // The capped helpers live here and legitimately construct the raw
    // providers they wrap.
    const allowlist = <String>{'lib/utils/image_limits.dart'};

    final offenders = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final rel = file.path.replaceAll(r'\', '/');
      if (allowlist.any(rel.endsWith)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // `cappedMemoryImage(` and `pw.MemoryImage(` are the sanctioned forms.
        if (line.contains('cappedMemoryImage') ||
            line.contains('pw.MemoryImage')) {
          continue;
        }
        if (antiPattern.hasMatch(line)) {
          offenders.add('$rel:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Decode deck-supplied bytes through cappedMemoryImage (both axes '
          'bounded by kMaxImageDecodeDimension), never a bare Image.memory/'
          'MemoryImage:\n${offenders.join('\n')}',
    );
  });
}
