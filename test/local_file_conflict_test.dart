import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';

/// #1951: detectie van externe bestandswijziging — twee vensters die hetzelfde
/// bestand openen, en wie het laatst opslaat wint. De mtime-vergelijking moet
/// dat opvangen: na openen is het tabblad schoon, maar als het bestand op
/// schijf intussen verandert, geeft `fileChangedExternally()` true terug.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ocideck_conflict_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Schrijf een geldig Marp-deck naar [path] en geef het pad terug.
  String writeDeckFile(String name, {String title = 'Testdeck'}) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsStringSync('---\nmarp: true\n---\n# $title\n');
    return path;
  }

  DeckNotifier makeNotifier() {
    final md = MarkdownService();
    final file = FileService(
      md,
      ImageService(),
      () => const ThemeProfile(),
      homeDirectory: () => tempDir.path,
    );
    return DeckNotifier(md, file);
  }

  test('fileChangedExternally geeft false direct na openen', () async {
    final path = writeDeckFile('deck.md');
    final n = makeNotifier();
    final deck = await n.deckFromFile(path);
    expect(deck, isNotNull);
    n.loadDeck(deck!, filePath: path);
    // Laat de fire-and-forget _recordFileMtime aflopen.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(await n.fileChangedExternally(), isFalse);
  });

  test('fileChangedExternally geeft true na externe wijziging (#1951)', () async {
    final path = writeDeckFile('deck.md');
    final n = makeNotifier();
    final deck = await n.deckFromFile(path);
    expect(deck, isNotNull);
    n.loadDeck(deck!, filePath: path);
    // Laat de fire-and-forget _recordFileMtime aflopen.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Simuleer een ander venster dat het bestand schrijft.
    // Wacht tot de mtime zeker anders is (minimaal 1 seconde op de meeste
    // besturingssystemen, maar lastModified heeft vaak milliseconden-resolutie).
    await Future<void>.delayed(const Duration(milliseconds: 50));
    File(
      path,
    ).writeAsStringSync('---\nmarp: true\n---\n# Gewijzigd door ander\n');

    expect(await n.fileChangedExternally(), isTrue);
  });

  test('fileChangedExternally geeft false na eigen opslaan', () async {
    final path = writeDeckFile('deck.md');
    final n = makeNotifier();
    final deck = await n.deckFromFile(path);
    expect(deck, isNotNull);
    n.loadDeck(deck!, filePath: path);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Eigen opslaan: mtime wordt bijgewerkt, dus geen conflict.
    await n.save();

    expect(await n.fileChangedExternally(), isFalse);
  });

  test('reloadFromDisk laadt de versie van schijf (#1951)', () async {
    final path = writeDeckFile('deck.md', title: 'Origineel');
    final n = makeNotifier();
    final deck = await n.deckFromFile(path);
    expect(deck, isNotNull);
    n.loadDeck(deck!, filePath: path);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Een ander venster schrijft een nieuwe titel.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    File(path).writeAsStringSync('---\nmarp: true\n---\n# Nieuwe titel\n');

    // Herladen: het deck krijgt de nieuwe titel.
    final ok = await n.reloadFromDisk();
    expect(ok, isTrue);
    expect(n.state.deck!.title, 'Nieuwe titel');
    expect(n.state.isDirty, isFalse);
    // Na herladen is er geen conflict meer.
    expect(await n.fileChangedExternally(), isFalse);
  });

  test('fileChangedExternally geeft false zonder bestandspad', () async {
    final n = makeNotifier();
    n.newDeck('Nieuw');
    expect(await n.fileChangedExternally(), isFalse);
  });
}

/// Extension om een deck vanuit een bestandspad te laden zonder de file picker.
extension on DeckNotifier {
  Future<Deck?> deckFromFile(String path) async {
    final file = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
      homeDirectory: () => Directory.current.path,
    );
    return file.openDeck(path);
  }
}
