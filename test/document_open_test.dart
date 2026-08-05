import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
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
}
