import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/services/export_service.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

Uint8List _png() {
  final image = img.Image(width: 320, height: 180);
  img.fill(image, color: img.ColorRgb8(30, 40, 60));
  return Uint8List.fromList(img.encodePng(image));
}

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

  test('fails gracefully when there are no slides', () async {
    final r = await service.export(deckPath(), ExportFormat.pdf, const []);
    expect(r.success, isFalse);
  });
}
