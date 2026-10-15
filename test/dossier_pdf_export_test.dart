import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/document_dossier_store.dart';
import 'package:ocideck/services/dossier_pdf_export.dart';

import 'pdf/pdf_text_probe.dart';

void main() {
  late Directory root;
  late DocumentDossierStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dossier-pdf-');
    store = DocumentDossierStore(File('${root.path}/dossier/dossier.json'));
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'one document PDF has ordered sources and optional metadata leaves',
    () async {
      final first = File('${root.path}/first.md')
        ..writeAsStringSync('# Eerste bron\n\nDe eerste inhoud.\n');
      final second = File('${root.path}/second.md')
        ..writeAsStringSync('# Dia als tekst\n\nPresentatie-inhoud.\n');
      var dossier = await store.create(
        'Mijn dossier',
        description: 'Korte uitleg',
      );
      dossier = await store.addFile(dossier, first, title: 'Eerste stuk');
      dossier = await store.addFile(dossier, second, title: 'Tweede stuk');
      final enriched = dossier.entries.first.copyWith(
        description: 'Kern van het stuk',
        documentDate: '2026-10-15',
        author: 'De opsteller',
      );
      dossier = dossier.copyWith(entries: [enriched, dossier.entries.last]);

      final withLeaves = await buildDossierPdf(
        dossier,
        store,
        settings: const AppSettings(),
      );
      final withoutLeaves = await buildDossierPdf(
        dossier,
        store,
        includeInterleaves: false,
        settings: const AppSettings(),
      );
      final text = pdfVisibleText(withLeaves);
      expect(text, contains('Mijn dossier'));
      expect(text, contains('Kern van het stuk'));
      expect(text, contains('2026-10-15'));
      expect(text, contains('De opsteller'));
      expect(text, contains(enriched.sha256));
      expect(
        text.indexOf('De eerste inhoud'),
        lessThan(text.indexOf('Presentatie-inhoud')),
      );
      expect(
        pdfPageCount(withLeaves),
        greaterThan(pdfPageCount(withoutLeaves)),
      );
      expect(
        pdfVisibleText(withoutLeaves),
        isNot(contains('Kern van het stuk')),
      );
    },
  );

  test('redacted export removes marked and detected personal data', () async {
    final source = File('${root.path}/sensitive.md')
      ..writeAsStringSync(
        '# Bron\n\nGeheim [[zeg dit niet]] en BSN 728398242.\n',
      );
    var dossier = await store.create('Dossier');
    dossier = await store.addFile(dossier, source);
    await expectLater(
      buildDossierPdf(dossier, store, settings: const AppSettings()),
      throwsA(isA<DossierPdfPrivacyException>()),
    );
    final text = pdfVisibleText(
      await buildDossierPdf(
        dossier,
        store,
        settings: const AppSettings(),
        privacyAcknowledged: true,
      ),
    );
    expect(text, isNot(contains('zeg dit niet')));
    expect(text, isNot(contains('728398242')));
    expect(text, contains('Bron'));
  });

  test('changed and missing source abort before returning PDF bytes', () async {
    final source = File('${root.path}/source.md')..writeAsStringSync('# Bron');
    var dossier = await store.create('Dossier');
    dossier = await store.addFile(dossier, source);
    await source.writeAsString('# Gewijzigd');
    await expectLater(
      buildDossierPdf(dossier, store, settings: const AppSettings()),
      throwsA(isA<FileSystemException>()),
    );
    await source.delete();
    await expectLater(
      buildDossierPdf(dossier, store, settings: const AppSettings()),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'source classification is enforced before PDF bytes are returned',
    () async {
      final source = File('${root.path}/classified.md')
        ..writeAsStringSync('---\ntlp: red\n---\n# Vertrouwelijk\n');
      var dossier = await store.create('Dossier');
      dossier = await store.addFile(dossier, source);
      await expectLater(
        buildDossierPdf(
          dossier,
          store,
          settings: const AppSettings(maxReleaseExportTlpKey: 'green'),
        ),
        throwsA(isA<DossierPdfClassificationException>()),
      );
    },
  );

  test('relative image may be embedded, path escape is rejected', () async {
    final assets = Directory('${root.path}/assets')..createSync();
    File(
      '${assets.path}/pixel.png',
    ).writeAsBytesSync(img.encodePng(img.Image(width: 1, height: 1)));
    final source = File('${root.path}/source.md')
      ..writeAsStringSync('# Bron\n\n![Pixel](assets/pixel.png)');
    var dossier = await store.create('Dossier');
    dossier = await store.addFile(dossier, source);
    final bytes = await buildDossierPdf(
      dossier,
      store,
      settings: const AppSettings(),
    );
    expect(bytes.take(4), [37, 80, 68, 70]);

    final unsafe = File('${root.path}/escape.md')
      ..writeAsStringSync('# Bron\n\n![Geheim](../outside.png)');
    dossier = await store.addFile(dossier, unsafe);
    await expectLater(
      buildDossierPdf(dossier, store, settings: const AppSettings()),
      throwsA(isA<FileSystemException>()),
    );
  });
}
