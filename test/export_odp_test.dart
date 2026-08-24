// ODP (OpenDocument Presentation) export (issue #1769): bouwt een ODP-ZIP
// met één gerenderde afbeelding per slide — dezelfde aanpak als PPTX.
//
// Deze test bewijst:
// 1. De ODT-structuur klopt (mimetype eerste entry, manifest, content, meta).
// 2. Elke slide wordt een <draw:page> met een <draw:image>.
// 3. De afbeeldingen staan als aparte PNG-bestanden in Pictures/.
// 4. TLP-classificatie staat in de metadata.
// 5. Classificatie-gate blokkeert een over-geclassificeerde export.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:path/path.dart' as p;

Uint8List _png() {
  final image = img.Image(width: 320, height: 180);
  img.fill(image, color: img.ColorRgb8(30, 40, 60));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory tmp;
  late ExportService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ocideck_odp');
    service = ExportService();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  String deckPath() => p.join(tmp.path, 'deck.md');

  test(
    'odp-structuur: mimetype eerste entry, manifest, content, meta',
    () async {
      final r = await service.export(deckPath(), ExportFormat.odp, [
        _png(),
        _png(),
        _png(),
      ], metadata: const ExportDocumentMetadata(title: 'Test Deck'));
      expect(r.success, isTrue, reason: r.error);

      final archive = ZipDecoder().decodeBytes(
        await File(r.outputPath!).readAsBytes(),
      );

      // mimetype moet de eerste entry zijn.
      expect(archive.first.name, 'mimetype');
      expect(
        String.fromCharCodes(archive.first.content as List<int>),
        'application/vnd.oasis.opendocument.presentation',
      );

      // De vereiste structuur-bestanden aanwezig.
      expect(archive.find('META-INF/manifest.xml'), isNotNull);
      expect(archive.find('content.xml'), isNotNull);
      expect(archive.find('meta.xml'), isNotNull);
    },
  );

  test('odp: elke slide wordt een <draw:page> met een <draw:image>', () async {
    final r = await service.export(deckPath(), ExportFormat.odp, [
      _png(),
      _png(),
      _png(),
    ], metadata: const ExportDocumentMetadata(title: 'Drie Slides'));
    expect(r.success, isTrue, reason: r.error);

    final archive = ZipDecoder().decodeBytes(
      await File(r.outputPath!).readAsBytes(),
    );
    final content = _readEntry(archive, 'content.xml');

    // Drie slides → drie <draw:page>-elementen.
    expect(content, contains('<draw:page'));
    expect(
      RegExp(r'<draw:page ').allMatches(content).length,
      3,
      reason: 'Expected 3 <draw:page> elements',
    );

    // Elke page heeft een <draw:image> die naar Pictures/ wijst.
    expect(content, contains('<draw:image'));
    expect(content, contains('Pictures/image1.png'));
    expect(content, contains('Pictures/image2.png'));
    expect(content, contains('Pictures/image3.png'));

    // De PNG-bestanden staan in de ZIP.
    expect(archive.find('Pictures/image1.png'), isNotNull);
    expect(archive.find('Pictures/image2.png'), isNotNull);
    expect(archive.find('Pictures/image3.png'), isNotNull);
  });

  test('odp: de bestandsnaam eindigt op .odp', () async {
    final r = await service.export(deckPath(), ExportFormat.odp, [
      _png(),
    ], metadata: const ExportDocumentMetadata(title: 'Naamtest'));
    expect(r.success, isTrue, reason: r.error);
    expect(p.extension(r.outputPath!), '.odp');
  });

  test('odp: TLP-classificatie staat in de metadata', () async {
    final r = await service.export(
      deckPath(),
      ExportFormat.odp,
      [_png()],
      tlp: TlpLevel.amber,
      metadata: const ExportDocumentMetadata(
        title: 'Vertrouwelijk',
        tlp: TlpLevel.amber,
      ),
    );
    expect(r.success, isTrue, reason: r.error);

    final archive = ZipDecoder().decodeBytes(
      await File(r.outputPath!).readAsBytes(),
    );
    final meta = _readEntry(archive, 'meta.xml');

    expect(meta, contains('TLP'));
    expect(meta, contains('AMBER'));
  });

  test(
    'odp: classificatie-gate blokkeert een over-geclassificeerde export',
    () async {
      const policy = ClassificationEnforcementPolicy(
        maxReleaseLevel: TlpLevel.green,
      );
      final r = await service.export(
        deckPath(),
        ExportFormat.odp,
        [_png()],
        tlp: TlpLevel.red,
        enforcementPolicy: policy,
      );

      expect(r.success, isFalse);
      expect(r.outputPath, isNull);
      // Fail-closed: geen bestand geproduceerd.
      final produced = tmp.listSync().whereType<File>().where(
        (f) => p.extension(f.path) == '.odp',
      );
      expect(produced, isEmpty);
    },
  );

  test('odp: lege slide-lijst wordt geweigerd', () async {
    final r = await service.export(
      deckPath(),
      ExportFormat.odp,
      [],
      metadata: const ExportDocumentMetadata(title: 'Leeg'),
    );

    expect(r.success, isFalse);
  });
}

String _readEntry(Archive archive, String name) {
  final entry = archive.find(name);
  if (entry == null) {
    fail('Entry $name niet gevonden in ODP-ZIP');
  }
  return String.fromCharCodes(entry.content as List<int>);
}
