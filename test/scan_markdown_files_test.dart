import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

/// De mapscan achter het openscherm: hij levert presentaties én platte
/// documenten op. Dat laatste is de reden dat dit bestand bestaat — een
/// zoeklijst die alleen decks toont, verstopt de helft van wat OciDeck opent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late FileService service;

  Future<File> write(String relPath, String content) async {
    final file = File(p.join(temp.path, relPath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_scan_md_');
    service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
      homeDirectory: () => temp.path,
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  const deckSource = '---\nmarp: true\ntitle: Het deck\n---\n\n# Dia\n\n- a\n';

  test('finds presentations and documents in one list', () async {
    await write('deck.md', deckSource);
    await write('verslag.md', '# Kwartaalverslag\n\nlopende tekst\n');
    await write('los.txt', 'gewoon platte tekst\n');

    final found = await service.scanMarkdownFiles(temp.path);

    expect(found.map((f) => f.fileName).toSet(), {
      'deck.md',
      'verslag.md',
      'los.txt',
    });
    final deck = found.firstWhere((f) => f.fileName == 'deck.md');
    expect(deck.kind, MarkdownKind.presentation);
    expect(deck, isA<ScannedPresentation>());
    expect(deck.deck!.slides, isNotEmpty);

    final document = found.firstWhere((f) => f.fileName == 'verslag.md');
    expect(document.kind, MarkdownKind.document);
    expect(document.deck, isNull);
    // De eerste kop is de naam die een gebruiker van zijn document herkent.
    expect(document.displayTitle, 'Kwartaalverslag');
    expect(document.content, contains('lopende tekst'));

    // Zonder kop valt hij terug op de bestandsnaam zonder extensie.
    final plain = found.firstWhere((f) => f.fileName == 'los.txt');
    expect(plain.displayTitle, 'los');
  });

  test('a file with executable content is in no list at all', () async {
    await write('deck.md', deckSource);
    await write('kwaad.md', '# Kop\n\n<script>steal()</script>\n');

    final found = await service.scanMarkdownFiles(temp.path);

    expect(found.map((f) => f.fileName), ['deck.md']);
  });

  test('includeDocuments: false is the decks-only list', () async {
    await write('deck.md', deckSource);
    await write('verslag.md', '# Kwartaalverslag\n');

    final found = await service.scanMarkdownFiles(
      temp.path,
      includeDocuments: false,
    );

    expect(found.map((f) => f.fileName), ['deck.md']);
  });

  test('scanPresentations keeps its decks-only promise', () async {
    await write('deck.md', deckSource);
    await write('verslag.md', '# Kwartaalverslag\n');

    final found = await service.scanPresentations(temp.path);

    expect(found.map((f) => f.fileName), ['deck.md']);
    // Het type belooft een deck: aanroepers die dia's nodig hebben, hoeven niet
    // op null te controleren.
    expect(found.single.deck.slides, isNotEmpty);
  });

  test('excludePath skips the file that is already open', () async {
    final open = await write('verslag.md', '# Kwartaalverslag\n');
    await write('ander.md', '# Ander\n');

    final found = await service.scanMarkdownFiles(
      temp.path,
      excludePath: open.path,
    );

    expect(found.map((f) => f.fileName), ['ander.md']);
  });
}
