import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Auto evidence hashing (PENTEST_MIAUW §10.2 / 3.3 / 4.8 / 4.11). MIAUW mandates
/// a **SHA1** hash for every received document / evidence artefact; a **SHA-256**
/// is added alongside as a stronger modern digest. Computing these from the file
/// bytes and building the appendix hash tables is mechanical bookkeeping — the
/// pure helpers here make it deterministic and testable (the caller reads the
/// bytes, e.g. via `ImageService.readSlideImageBytes` for an evidence slide).

/// The SHA1 + SHA-256 digests of one artefact.
class EvidenceHashes {
  const EvidenceHashes({required this.sha1, required this.sha256});

  final String sha1;
  final String sha256;
}

/// Compute the SHA1 + SHA-256 of [bytes]. Pure and synchronous.
EvidenceHashes computeEvidenceHashes(Uint8List bytes) => EvidenceHashes(
  sha1: sha1.convert(bytes).toString(),
  sha256: sha256.convert(bytes).toString(),
);

/// Render a Markdown table of the evidence hashes (file · SHA1 · SHA-256) for a
/// MIAUW appendix (4.8 / 4.11). Preserves the insertion order of [hashes]; an
/// empty map yields an empty string (no table).
String evidenceHashTable(Map<String, EvidenceHashes> hashes) {
  if (hashes.isEmpty) return '';
  final buf = StringBuffer()
    ..writeln('| Bestand | SHA1 | SHA-256 |')
    ..writeln('| --- | --- | --- |');
  for (final entry in hashes.entries) {
    buf.writeln(
      '| ${entry.key} | ${entry.value.sha1} | ${entry.value.sha256} |',
    );
  }
  return buf.toString().trimRight();
}
