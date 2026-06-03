import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

Uint8List _png() {
  final image = img.Image(width: 320, height: 180);
  img.fill(image, color: img.ColorRgb8(30, 40, 60));
  return Uint8List.fromList(img.encodePng(image));
}

/// A photo-like PNG full of pseudo-random pixels, where lossless PNG is large
/// and JPEG compression pays off — used to assert the compressed PDF shrinks.
Uint8List _noisyPng() {
  // Wider than ExportService's compressed target width so the export exercises
  // both the JPEG re-encode and the downscale path.
  final image = img.Image(width: 1600, height: 900);
  var seed = 1234567;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      image.setPixelRgb(
        x,
        y,
        seed & 0xff,
        (seed >> 8) & 0xff,
        (seed >> 16) & 0xff,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Matches a leading UTC timestamp prefix: `YYYYMMDDHHMMSS ` (e.g. `20260603124547 `).
final _dtgPrefix = RegExp(r'^\d{14} ');

void main() {
  late Directory tmp;
  late ExportService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ocideck_export');
    service = ExportService();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  String deckPath() => p.join(tmp.path, 'deck.md');

  test('exports a PDF that starts with the PDF magic header', () async {
    final images = [_png(), _png()];
    final r = await service.export(deckPath(), ExportFormat.pdf, images);

    expect(r.success, isTrue, reason: r.error);
    final bytes = await File(r.outputPath!).readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('exports a valid PPTX zip with the expected parts', () async {
    final images = [_png(), _png()];
    final r = await service.export(deckPath(), ExportFormat.pptx, images);

    expect(r.success, isTrue, reason: r.error);
    expect(p.extension(r.outputPath!), '.pptx');

    final bytes = await File(r.outputPath!).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, contains('[Content_Types].xml'));
    expect(names, contains('_rels/.rels'));
    expect(names, contains('ppt/presentation.xml'));
    expect(names, contains('ppt/slideMasters/slideMaster1.xml'));
    expect(names, contains('ppt/slideLayouts/slideLayout1.xml'));
    expect(names, contains('ppt/theme/theme1.xml'));
    expect(names, contains('ppt/slides/slide1.xml'));
    expect(names, contains('ppt/slides/slide2.xml'));
    expect(names, contains('ppt/media/image1.png'));
    expect(names, contains('ppt/media/image2.png'));

    // Every XML part must be well-formed.
    for (final file in archive.files) {
      if (file.name.endsWith('.xml') || file.name.endsWith('.rels')) {
        final content = utf8.decode(file.content as List<int>);
        expect(
          () => XmlDocument.parse(content),
          returnsNormally,
          reason: '${file.name} is not well-formed XML',
        );
      }
    }
  });

  test('PPTX without notes has no notesSlide/notesMaster parts', () async {
    final r = await service.export(deckPath(), ExportFormat.pptx, [_png()]);
    final archive = ZipDecoder().decodeBytes(
      await File(r.outputPath!).readAsBytes(),
    );
    final names = archive.files.map((f) => f.name).toSet();
    expect(names.any((n) => n.startsWith('ppt/notesSlides/')), isFalse);
    expect(names.any((n) => n.startsWith('ppt/notesMasters/')), isFalse);
  });

  test('PPTX embeds speaker notes only for slides that have them', () async {
    final r = await service.export(
      deckPath(),
      ExportFormat.pptx,
      [_png(), _png()],
      notes: ['', 'Vergeet de cijfers niet <3 & co'],
    );
    expect(r.success, isTrue, reason: r.error);

    final archive = ZipDecoder().decodeBytes(
      await File(r.outputPath!).readAsBytes(),
    );
    final names = archive.files.map((f) => f.name).toSet();

    // Notes machinery is present for the noted slide only.
    expect(names, contains('ppt/notesMasters/notesMaster1.xml'));
    expect(names, contains('ppt/notesSlides/notesSlide2.xml'));
    expect(names, isNot(contains('ppt/notesSlides/notesSlide1.xml')));

    String partText(String name) => utf8.decode(
      archive.files.firstWhere((f) => f.name == name).content as List<int>,
    );

    // The note text is present and XML-escaped.
    final notes2 = partText('ppt/notesSlides/notesSlide2.xml');
    expect(notes2, contains('Vergeet de cijfers niet &lt;3 &amp; co'));
    // The slide links to its notesSlide.
    expect(
      partText('ppt/slides/_rels/slide2.xml.rels'),
      contains('notesSlide2.xml'),
    );

    // Every XML part (including the new notes parts) must be well-formed.
    for (final file in archive.files) {
      if (file.name.endsWith('.xml') || file.name.endsWith('.rels')) {
        expect(
          () => XmlDocument.parse(utf8.decode(file.content as List<int>)),
          returnsNormally,
          reason: '${file.name} is not well-formed XML',
        );
      }
    }
  });

  test('compressed PDF is written as a separate -compact file', () async {
    final images = [_png(), _png()];
    final r = await service.export(
      deckPath(),
      ExportFormat.pdf,
      images,
      compress: true,
    );

    expect(r.success, isTrue, reason: r.error);
    expect(p.basename(r.outputPath!), endsWith(' deck-compact.pdf'));
    expect(p.basename(r.outputPath!), matches(_dtgPrefix));
    final bytes = await File(r.outputPath!).readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('compressed PDF is smaller than the lossless PDF', () async {
    final images = [_noisyPng(), _noisyPng()];

    final lossless = await service.export(deckPath(), ExportFormat.pdf, images);
    final compressed = await service.export(
      deckPath(),
      ExportFormat.pdf,
      images,
      compress: true,
    );

    expect(lossless.success, isTrue, reason: lossless.error);
    expect(compressed.success, isTrue, reason: compressed.error);

    final losslessSize = await File(lossless.outputPath!).length();
    final compressedSize = await File(compressed.outputPath!).length();
    expect(compressedSize, lessThan(losslessSize));
  });

  test('writes into outputDirectory and creates it when missing', () async {
    final exportDir = p.join(tmp.path, 'exports', 'pdf');
    expect(Directory(exportDir).existsSync(), isFalse);

    final r = await service.export(deckPath(), ExportFormat.pdf, [
      _png(),
    ], outputDirectory: exportDir);

    expect(r.success, isTrue, reason: r.error);
    expect(p.dirname(r.outputPath!), exportDir);
    expect(p.basename(r.outputPath!), endsWith(' deck.pdf'));
    expect(p.basename(r.outputPath!), matches(_dtgPrefix));
    expect(File(r.outputPath!).existsSync(), isTrue);
  });

  test('without outputDirectory the export lands next to the deck', () async {
    final r = await service.export(deckPath(), ExportFormat.pdf, [_png()]);

    expect(r.success, isTrue, reason: r.error);
    expect(p.dirname(r.outputPath!), tmp.path);
  });

  test('natoDtg formats a UTC YYYYMMDDHHMMSS timestamp', () {
    final t = DateTime.utc(2026, 6, 3, 12, 45, 47);
    expect(ExportService.natoDtg(t), '20260603124547');
  });

  test('natoDtg converts non-UTC input to UTC (zone-independent)', () {
    final utc = DateTime.utc(2026, 1, 5, 9, 7, 3);
    // toLocal() then format must still yield the original UTC timestamp,
    // whatever the machine's time zone is.
    expect(ExportService.natoDtg(utc.toLocal()), '20260105090703');
  });

  test('fails gracefully when there are no slides', () async {
    final r = await service.export(deckPath(), ExportFormat.pdf, const []);
    expect(r.success, isFalse);
  });

  test('HTML export writes a self-contained .html from Markdown', () async {
    final htmlService = ExportService(
      htmlService: MarpHtmlService(loadAsset: (a) => File(a).readAsString()),
    );
    final r = await htmlService.export(
      deckPath(),
      ExportFormat.html,
      const [], // HTML needs no rasterized slides
      markdown: '# Titel\n\n---\n\n# Tweede',
    );

    expect(r.success, isTrue, reason: r.error);
    expect(p.extension(r.outputPath!), '.html');
    expect(p.basename(r.outputPath!), matches(_dtgPrefix));

    final html = await File(r.outputPath!).readAsString();
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('# Titel'));
  });

  test('HTML export fails without Markdown', () async {
    final r = await service.export(deckPath(), ExportFormat.html, const []);
    expect(r.success, isFalse);
  });
}
