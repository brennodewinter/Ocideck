import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:path/path.dart' as p;

/// Het openpad voor een plat document loopt door dezelfde fail-closed poorten
/// als een deck (cap → bestaan → UTF-8 → veiligheidsscan), maar deconstrueert de
/// bron niet: wat op schijf staat komt byte-getrouw terug (docs/design/
/// DOCUMENT_MODE.md §3). Deze test bewaakt beide kanten.
FileService _service() =>
    FileService(MarkdownService(), ImageService(), () => ThemeProfile());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('doc_open'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('een plat document opent byte-getrouw (incl. --- en CRLF)', () async {
    const source =
        '# Memo\n\nEen gewoon document.\n\n---\n\nOnder de streep.\r\n';
    final path = p.join(temp.path, 'memo.md');
    File(path).writeAsStringSync(source);

    final result = await _service().openDocumentDetailed(path);
    expect(result.failure, isNull);
    expect(result.document, isNotNull);
    expect(result.document!.toMarkdown(), source);
  });

  test('een niet-bestaand pad geeft notFound', () async {
    final result = await _service().openDocumentDetailed(
      p.join(temp.path, 'weg.md'),
    );
    expect(result.document, isNull);
    expect(result.failure, OpenFailure.notFound);
  });

  test('uitvoerbare inhoud wordt fail-closed geweigerd', () async {
    final path = p.join(temp.path, 'gevaar.md');
    File(path).writeAsStringSync('# Titel\n\n<script>alert(1)</script>\n');

    final result = await _service().openDocumentDetailed(path);
    expect(result.document, isNull);
    expect(result.failure, OpenFailure.unsafe);
  });

  test('binaire (niet-UTF-8) inhoud is onleesbaar', () async {
    final path = p.join(temp.path, 'bin.md');
    File(path).writeAsBytesSync([0xff, 0xfe, 0x00, 0x01, 0x02]);

    final result = await _service().openDocumentDetailed(path);
    expect(result.failure, OpenFailure.unreadable);
  });

  test(
    'een marp-deck komt óók verbatim terug (het pad is soort-agnostisch)',
    () async {
      // openDocumentDetailed opent wat het krijgt; de router (later) stuurt een
      // marp-bestand naar het deckpad. Hier bevestigen we dat het documentpad de
      // bytes niet deconstrueert maar exact teruggeeft.
      const source = '---\nmarp: true\ntheme: ocideck\n---\n\n# Dia\n';
      final path = p.join(temp.path, 'deck.md');
      File(path).writeAsStringSync(source);

      final result = await _service().openDocumentDetailed(path);
      expect(result.failure, isNull);
      expect(result.document!.toMarkdown(), source);
    },
  );

  test('saveDocument schrijft de bron byte-getrouw naar schijf', () async {
    const source = '# Rapport\n\nTekst.\n\n---\n\nMeer.\r\n';
    final path = p.join(temp.path, 'uit.md');
    final written = await saveDocument(MarkdownDocument.parse(source), path);
    expect(written, isNotNull);
    expect(File(path).readAsStringSync(), source);
  });

  test('open → bewerk → opslaan → heropenen is byte-identiek', () async {
    const source = '---\ntitle: Memo\n---\n\n# Kop\n\nInhoud.\n';
    final path = p.join(temp.path, 'memo.md');
    File(path).writeAsStringSync(source);
    final svc = _service();

    final opened = (await svc.openDocumentDetailed(path)).document!;
    const edited = '$source\nExtra regel.\n';
    expect(await saveDocument(opened.withSource(edited), path), isNotNull);

    final reopened = (await svc.openDocumentDetailed(path)).document!;
    expect(reopened.toMarkdown(), edited);
  });

  // Een mem:-verwijzing is vluchtig (import, plakken): de opslag schrijft de
  // bytes als echt bestand weg en de bron wijst er daarna projectrelatief
  // naar — anders staat er een verwijzing naar niets in het .md (#2120).
  group('mem:-afbeeldingen bij opslaan', () {
    tearDown(WebAssetStore.clear);

    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      1, 2, 3, 4,
    ]);

    test(
      'een mem:-afbeelding landt in images/ en de bron wijst ernaar',
      () async {
        final mem = WebAssetStore.put(png, name: 'foto.png');
        final path = p.join(temp.path, 'doc.md');

        final written = await saveDocument(
          MarkdownDocument.parse('tekst\n\n![kat]($mem)\n'),
          path,
        );

        expect(written, isNotNull);
        expect(written!.source, contains('![kat](images/foto.png)'));
        expect(
          File(p.join(temp.path, 'images', 'foto.png')).readAsBytesSync(),
          png,
        );
        expect(File(path).readAsStringSync(), written.source);
      },
    );

    test('een absolute verwijzing wordt naar images/ gekopieerd', () async {
      final bron = File(p.join(temp.path, 'invoer.png'))..writeAsBytesSync(png);
      final path = p.join(temp.path, 'doc.md');

      final written = await saveDocument(
        MarkdownDocument.parse('![foto](${bron.path})\n'),
        path,
      );

      expect(written!.source, contains('![foto](images/invoer.png)'));
      expect(
        File(p.join(temp.path, 'images', 'invoer.png')).readAsBytesSync(),
        png,
      );
    });

    test(
      'een document zonder verwijzingen maakt geen lege images/-map',
      () async {
        final path = p.join(temp.path, 'kaal.md');
        await saveDocument(MarkdownDocument.parse('alleen tekst\n'), path);

        expect(Directory(p.join(temp.path, 'images')).existsSync(), isFalse);
      },
    );
  });
}
