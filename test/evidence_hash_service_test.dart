import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/evidence_hash_service.dart';

void main() {
  group('computeEvidenceHashes', () {
    test('matches the known SHA1/SHA-256 of "abc"', () {
      final h = computeEvidenceHashes(Uint8List.fromList('abc'.codeUnits));
      expect(h.sha1, 'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(
        h.sha256,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('matches the known digests of the empty input', () {
      final h = computeEvidenceHashes(Uint8List(0));
      expect(h.sha1, 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(
        h.sha256,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });

  group('evidenceHashTable', () {
    test('empty input yields no table', () {
      expect(evidenceHashTable(const {}), '');
    });

    test('renders a Markdown table preserving order', () {
      final table = evidenceHashTable({
        'a.png': const EvidenceHashes(sha1: 'aa', sha256: 'bb'),
        'b.png': const EvidenceHashes(sha1: 'cc', sha256: 'dd'),
      });
      expect(table, contains('| Bestand | SHA1 | SHA-256 |'));
      expect(table, contains('| a.png | aa | bb |'));
      expect(table.indexOf('a.png'), lessThan(table.indexOf('b.png')));
    });
  });
}
