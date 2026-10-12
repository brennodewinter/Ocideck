import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/utils/markdown_keywords.dart';
import 'package:ocideck/utils/tlp_explanation.dart';

void main() {
  test('trefwoorden komen alleen uit keywords:, niet uit de tekst', () {
    const source = '''
---
title: Rapport
keywords: alfa, Beta
---

Hier staat alfa niet als trefwoord-filter, en gamma ook.

''';
    expect(markdownKeywords(source), ['alfa', 'Beta']);
    expect(markdownHasKeywords(source, ['alfa', 'beta']), isTrue);
    expect(markdownHasKeywords(source, ['gamma']), isFalse);
    expect(
      markdownHasKeywords('gamma staat alleen in de tekst', ['gamma']),
      isFalse,
    );
  });

  test('TLP-toelichting komt onder de titel en verdubbelt niet', () {
    const body = '# Rapport\n\nInleiding.\n';
    const sentence = 'TLP:RED — alleen voor de genoemde ontvangers.';
    const paragraph = '$sentence\nBestemd voor: Alice';
    final once = insertTlpExplanation(body, paragraph, sentence);
    expect(once, startsWith('# Rapport\n\n$paragraph\n'));
    expect(once, contains('Inleiding.'));
    final twice = insertTlpExplanation(once, paragraph, sentence);
    expect(twice, once);
  });

  test('startmap valt terug op de eerste bibliotheek', () {
    const docs = '/tmp/docs';
    const decks = '/tmp/decks';
    final settings = AppSettings(
      connections: const [
        LocalConnection(id: 'a', name: 'Docs', path: docs),
        LocalConnection(id: 'b', name: 'Decks', path: decks),
      ],
      documentStartDirectory: docs,
      presentationStartDirectory: '/weg',
    );
    expect(settings.startDirectoryFor(document: true), docs);
    expect(settings.startDirectoryFor(document: false), docs);
    expect(settings.homeDirectory, docs);
  });
}
