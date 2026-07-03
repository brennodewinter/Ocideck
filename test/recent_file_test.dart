import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/recent_file.dart';

void main() {
  test('round-trip behoudt alle metadata', () {
    final file = RecentFile(
      path: '/decks/briefing.md',
      openedAt: DateTime.utc(2026, 7, 4, 10, 30),
      slideCount: 24,
      tlp: TlpLevel.amber,
      lastExportFormat: 'PDF',
      lastExportAt: DateTime.utc(2026, 7, 3, 9),
    );
    final decoded = RecentFile.decodeList(RecentFile.encodeList([file]));
    expect(decoded, hasLength(1));
    final back = decoded.first;
    expect(back.path, file.path);
    expect(back.openedAt, file.openedAt);
    expect(back.slideCount, 24);
    expect(back.tlp, TlpLevel.amber);
    expect(back.lastExportFormat, 'PDF');
    expect(back.lastExportAt, file.lastExportAt);
  });

  test('minimale entry (alleen pad) round-tript met defaults', () {
    final decoded = RecentFile.decodeList(
      RecentFile.encodeList([const RecentFile(path: '/a.md')]),
    );
    expect(decoded.single.slideCount, 0);
    expect(decoded.single.tlp, TlpLevel.none);
    expect(decoded.single.openedAt, isNull);
    expect(decoded.single.lastExportFormat, isNull);
  });

  test('onleesbare of vreemde JSON levert een lege lijst op', () {
    expect(RecentFile.decodeList(null), isEmpty);
    expect(RecentFile.decodeList(''), isEmpty);
    expect(RecentFile.decodeList('geen json'), isEmpty);
    expect(RecentFile.decodeList('{"niet":"een lijst"}'), isEmpty);
    expect(RecentFile.decodeList('[42, "tekst"]'), isEmpty);
  });

  test('entries zonder pad worden weggefilterd', () {
    expect(RecentFile.decodeList('[{"slideCount": 3}]'), isEmpty);
  });

  test('legacy paden-lijst migreert naar entries zonder metadata', () {
    final migrated = RecentFile.fromLegacyPaths(['/a.md', '', '/b.md']);
    expect(migrated.map((f) => f.path), ['/a.md', '/b.md']);
    expect(migrated.first.tlp, TlpLevel.none);
  });

  test('onbekende TLP-sleutel valt terug op none', () {
    expect(
      RecentFile.decodeList('[{"path":"/a.md","tlp":"paars"}]').single.tlp,
      TlpLevel.none,
    );
  });
}
