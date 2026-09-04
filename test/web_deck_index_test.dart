import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/web_deck_index.dart';

void main() {
  group('parseAutoindexHtml', () {
    test('Nginx autoindex: haalt .md-links eruit, negeert de rest', () {
      const html = '''
<html><head><title>Index of /decks/</title></head>
<body><h1>Index of /decks/</h1><hr><pre>
<a href="../">../</a>
<a href="intro.md">intro.md</a>
<a href="budget.xlsx">budget.xlsx</a>
<a href="slides/">slides/</a>
<a href="eindrapport.md">eindrapport.md</a>
</pre><hr></body></html>
''';
      final entries = parseAutoindexHtml(html, 'https://host/decks/');
      expect(entries, hasLength(2));
      // Alfabetisch gesorteerd op naam.
      expect(entries[0].name, 'eindrapport.md');
      expect(entries[0].url, 'https://host/decks/eindrapport.md');
      expect(entries[1].name, 'intro.md');
      expect(entries[1].url, 'https://host/decks/intro.md');
    });

    test('Apache autoindex: tabel met .md-links', () {
      const html = '''
<table>
  <tr><th><a href="Name">Name</a></th><th>Last modified</th></tr>
  <tr><td><a href="welcome.md">welcome.md</a></td><td>2026-09-01</td></tr>
  <tr><td><a href="data.json">data.json</a></td><td>2026-08-15</td></tr>
</table>
''';
      final entries = parseAutoindexHtml(html, 'https://host/decks/');
      expect(entries, hasLength(1));
      expect(entries.single.name, 'welcome.md');
      expect(entries.single.url, 'https://host/decks/welcome.md');
    });

    test('dubbele links worden ontdubbeld', () {
      const html = '''
<a href="dup.md">dup.md</a>
<a href="dup.md">dup.md</a>
''';
      final entries = parseAutoindexHtml(html, 'https://host/decks/');
      expect(entries, hasLength(1));
    });

    test('lege of ongeldig HTML geeft lege lijst', () {
      expect(parseAutoindexHtml('', 'https://host/decks/'), isEmpty);
      expect(parseAutoindexHtml('geen html', 'https://host/decks/'), isEmpty);
    });

    test('ongeldige baseUrl geeft lege lijst', () {
      expect(
        parseAutoindexHtml('<a href="x.md">x.md</a>', 'geen-url'),
        isEmpty,
      );
    });

    test('relatieve URL wordt opgelost tegen baseUrl', () {
      const html = '<a href="sub/deck.md">sub/deck.md</a>';
      final entries = parseAutoindexHtml(html, 'https://host/decks/');
      expect(entries.single.url, 'https://host/decks/sub/deck.md');
      // pathSegments.last is de bestandsnaam, niet de map.
      expect(entries.single.name, 'deck.md');
    });

    test('hoofdletterongevoelige .md-extensie', () {
      const html = '''
<a href="upper.MD">upper.MD</a>
<a href="lower.md">lower.md</a>
''';
      final entries = parseAutoindexHtml(html, 'https://host/decks/');
      expect(entries, hasLength(2));
    });
  });
}
