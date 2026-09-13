import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/pdf_evidence_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('pdf_evidence_test');
  });

  tearDown(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('accepts PDF magic bytes and refuses renamed content', () {
    expect(
      isSupportedPdfEvidence(Uint8List.fromList('%PDF-1.7'.codeUnits)),
      isTrue,
    );
    expect(
      isSupportedPdfEvidence(Uint8List.fromList('<script>'.codeUnits)),
      isFalse,
    );
  });

  test('Markdown attachment is open and round-trips special filenames', () {
    const path = 'evidence/rapport definitief (1).pdf';
    final markdown = PdfEvidenceService.markdownFor(path);
    expect(markdown, contains('evidence/rapport%20definitief%20(1).pdf'));
    expect(PdfEvidenceService.attachmentFromMarkdown(markdown)?.path, path);
    expect(
      PdfEvidenceService.attachmentFromMarkdown(
        '[handmatig](evidence/handmatig.pdf)',
      )?.path,
      'evidence/handmatig.pdf',
    );
    expect(
      PdfEvidenceService.attachmentFromMarkdown(
        '[extern](<https://example.test/rapport.pdf>)',
      ),
      isNull,
    );
    expect(
      PdfEvidenceService.attachmentFromMarkdown('[stuk](<evidence/%ZZ.pdf>)'),
      isNull,
    );
  });

  test('reads only contained, bounded PDF bytes', () async {
    final inside = File(p.join(project.path, 'evidence', 'inside.pdf'));
    inside.parent.createSync(recursive: true);
    inside.writeAsBytesSync('%PDF-1.7\nbody'.codeUnits);
    final outside = File(p.join(project.parent.path, 'outside.pdf'))
      ..writeAsBytesSync('%PDF-1.7\noutside'.codeUnits);
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });

    const service = PdfEvidenceService();
    expect(
      await service.read('evidence/inside.pdf', projectPath: project.path),
      isNotNull,
    );
    expect(
      await service.read('../outside.pdf', projectPath: project.path),
      isNull,
    );

    final oversized = File(p.join(project.path, 'evidence', 'large.pdf'));
    oversized.writeAsBytesSync('%PDF-'.codeUnits);
    oversized.openSync(mode: FileMode.append)
      ..truncateSync(maxPdfEvidenceBytes + 1)
      ..closeSync();
    expect(
      await service.read('evidence/large.pdf', projectPath: project.path),
      isNull,
    );
  });
}
