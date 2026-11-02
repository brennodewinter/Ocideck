import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/deck_source_search.dart';

void main() {
  test(
    'source finds decoded displayed values without matching JSON keys or paths',
    () {
      const source = '''# Inleiding
```chart
{"title":"Zichtbaar \\u0041ntwoord", "source":"/hidden/target.csv", "x":["Links"], "series":[{"name":"Reeks","data":[1]}]}
```
```cockpit
{"layout":"hidden-layout", "meters":[{"type":"speedometer","label":"Meting","unit":"km/u"}]}
```
```question
{"kind":"openText", "prompt":"Een **zichtbare** vraag", "answers":[{"text":"geheim antwoord","correct":true}], "hints":["zichtbare hint"],"feedback":{"correct":"Goed gedaan"}}
```
Na **afloop** leesbaar.
''';
      final index = DeckSourceSearchIndex(source);
      for (final query in [
        'title',
        'source',
        'hidden',
        'correct',
        'layout',
        'geheim antwoord',
      ]) {
        expect(index.matches(query), isEmpty, reason: query);
      }
      for (final query in [
        'Meting',
        'km/u',
        'Links',
        'Reeks',
        'Een zichtbare vraag',
        'zichtbare hint',
        'Goed gedaan',
        'Na afloop leesbaar',
      ]) {
        expect(index.matches(query), hasLength(1), reason: query);
      }
      final escaped = index.matches('Antwoord').single;
      expect(source.substring(escaped.start, escaped.end), r'\u0041ntwoord');
      expect(index.context(escaped), contains('Zichtbaar Antwoord'));
    },
  );

  test(
    'duplicate keys use the rendered value and ordinary code keeps its content',
    () {
      const source = '''```chart
{"title":"oud", "title":"nieuw"}
```
```text
source type correct
```
''';
      final index = DeckSourceSearchIndex(source);
      expect(index.matches('oud'), isEmpty);
      expect(index.matches('nieuw'), hasLength(1));
      expect(index.matches('correct'), hasLength(1));
    },
  );

  test(
    'nested machine fences remain ordinary code and invalid specs stay hidden',
    () {
      const source = '''````text
```question
{"prompt":"gewoon codewoord"}
```
````
```question
{"prompt":"ongeldige JSON"
```
''';
      final index = DeckSourceSearchIndex(source);
      expect(index.matches('prompt'), hasLength(1));
      expect(index.matches('ongeldige JSON'), isEmpty);
    },
  );
  test(
    'notes opt-in follows the parser while preserving exact source positions',
    () {
      const source = '''# Dia
<!-- _class: bullets -->
<!-- _style: background: red -->
<!-- ocideck_image_alt: geheim alternatief -->
Zichtbare tekst. <!-- intern commentaar --> Daarna.
<!--
Een **sprekersnotitie** met geheim.
-->
<!-- notitie achteraan -->
''';
      expect(DeckSourceSearchIndex(source).matches('sprekersnotitie'), isEmpty);
      final index = DeckSourceSearchIndex(source, includeNotes: true);
      final match = index.matches('sprekersnotitie').single;
      expect(source.substring(match.start, match.end), 'sprekersnotitie');
      expect(index.matches('notitie achteraan'), hasLength(1));
      for (final hidden in [
        'background',
        'bullets',
        'geheim alternatief',
        'intern commentaar',
      ]) {
        expect(index.matches(hidden), isEmpty, reason: hidden);
      }
    },
  );
}
