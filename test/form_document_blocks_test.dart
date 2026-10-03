import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form_document_blocks.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

/// Een geldig formulier; de regelnummers (0-gebaseerd) staan in de commentaren.
const String formulier = '''<!-- form id=f version=1 -->
# Formulier

Welkom.

<!-- notice -->
We bewaren je gegevens.
<!-- /notice -->

## A. Jij

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
Sari
<!-- /field id=naam -->

<!-- field id=verhaal type=prose -->
## Het verhaal
> uitleg
<!-- answer -->

<!-- /field id=verhaal -->

Tot slot.
''';

void main() {
  group('scanFormBlocks', () {
    test('legt kop, notice en velden vast als atomaire blokken', () {
      final scan = scanFormBlocks(formulier);
      expect(scan.blocks.map((b) => b.kind), [
        FormBlockKind.header,
        FormBlockKind.notice,
        FormBlockKind.field,
        FormBlockKind.field,
      ]);
      // regelindex 0: de form-marker; 5-7: notice; 11-15: eerste veld.
      expect(
        [for (final b in scan.blocks) (b.start, b.end)],
        [(0, 1), (5, 8), (11, 16), (17, 23)],
      );
    });

    test('isAtomicLine en blockAt kennen alleen regels in een blok', () {
      final scan = scanFormBlocks(formulier);
      for (final line in [0, 5, 6, 7, 11, 13, 15, 17, 22]) {
        expect(scan.isAtomicLine(line), isTrue, reason: 'regel $line');
      }
      for (final line in [1, 3, 4, 8, 9, 10, 16, 23, 24]) {
        expect(scan.isAtomicLine(line), isFalse, reason: 'regel $line');
        expect(scan.blockAt(line), isNull);
      }
      expect(scan.blockAt(13)!.kind, FormBlockKind.field);
    });

    test(
      'de markerregels zijn alleen de drie per veld, twee per notice, en de kop',
      () {
        expect(scanFormBlocks(formulier).markerLines, {
          0,
          5,
          7,
          11,
          13,
          15,
          17,
          20,
          22,
        });
      },
    );

    test('een notice na de velden staat in documentvolgorde', () {
      const na = '''<!-- form id=f -->
<!-- field id=a type=text -->
L
<!-- answer -->
<!-- /field id=a -->
<!-- notice -->
x
<!-- /notice -->
''';
      expect(scanFormBlocks(na).blocks.map((b) => b.kind), [
        FormBlockKind.header,
        FormBlockKind.field,
        FormBlockKind.notice,
      ]);
    });

    test('front matter erboven schuift de indices mee', () {
      final scan = scanFormBlocks('---\ntheme: x\n---\n\n$formulier');
      expect(scan.blocks.first.start, 4);
    });

    test('een document zonder formulier levert niets', () {
      for (final doc in [
        '',
        '# Titel\n\ntekst',
        '<!-- toc -->\n# a',
        '<!-- a note -->',
      ]) {
        final scan = scanFormBlocks(doc);
        expect(scan.isEmpty, isTrue, reason: doc);
        expect(scan.isAtomicLine(0), isFalse);
      }
    });

    test('markers in een codeblok maken er geen formulier van', () {
      final readme =
          '```\n<!-- form id=f -->\n<!-- field id=a type=text -->\n```\n';
      expect(scanFormBlocks(readme).isEmpty, isTrue);
    });

    test(
      'een kapot formulier levert geen atomaire bereiken: het blijft zichtbaar kapot',
      () {
        final kapot = formulier.replaceFirst('<!-- /field id=naam -->\n', '');
        expect(parseForm(kapot), isA<BrokenForm>());
        expect(scanFormBlocks(kapot).isEmpty, isTrue);
        final dubbel = formulier
            .replaceFirst('id=verhaal', 'id=naam')
            .replaceFirst('/field id=verhaal', '/field id=naam');
        expect(scanFormBlocks(dubbel).isEmpty, isTrue);
      },
    );

    test('hetzelfde tekstobject geeft dezelfde scan terug', () {
      final a = scanFormBlocks(formulier);
      expect(identical(scanFormBlocks(formulier), a), isTrue);
      expect(
        identical(scanFormBlocks(String.fromCharCodes(formulier.codeUnits)), a),
        isTrue,
      );
    });

    test('CRLF-bronnen geven dezelfde bereiken', () {
      final lf = scanFormBlocks(
        formulier,
      ).blocks.map((b) => (b.start, b.end)).toList();
      final crlf = scanFormBlocks(
        formulier.replaceAll('\n', '\r\n'),
      ).blocks.map((b) => (b.start, b.end)).toList();
      expect(crlf, lf);
    });

    test('een groot formulier en een groot gewoon document zijn snel', () {
      final b = StringBuffer('<!-- form id=f -->\n');
      for (var i = 0; i < 2000; i++) {
        b.write(
          '<!-- field id=f$i type=text -->\nL$i\n<!-- answer -->\nx\n<!-- /field id=f$i -->\n',
        );
      }
      final sw = Stopwatch()..start();
      expect(scanFormBlocks(b.toString()).blocks.length, 2001);
      expect(sw.elapsedMilliseconds, lessThan(3000));
      final plain = List.generate(
        20000,
        (i) => 'regel $i met <!-- een opmerking -->',
      ).join('\n');
      sw
        ..reset()
        ..start();
      expect(scanFormBlocks(plain).isEmpty, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('stripFormMarkers', () {
    test(
      'maakt van elke markerregel een lege regel, en houdt het aantal regels',
      () {
        final out = stripFormMarkers(formulier);
        expect(out.split('\n').length, formulier.split('\n').length);
        expect(out, isNot(contains('<!--')));
        expect(out, contains('**Naam**'));
        expect(out, contains('Sari'));
        expect(out, contains('## Het verhaal'));
        expect(out, contains('> uitleg'));
        expect(out, contains('We bewaren je gegevens.'));
      },
    );

    test(
      'alleen markerregels verdwijnen: elke andere regel blijft byte-gelijk',
      () {
        final scan = scanFormBlocks(formulier);
        final before = formulier.split('\n');
        final after = stripFormMarkers(formulier).split('\n');
        for (var i = 0; i < before.length; i++) {
          expect(
            after[i],
            scan.markerLines.contains(i) ? '' : before[i],
            reason: 'regel $i',
          );
        }
      },
    );

    test('CRLF blijft CRLF', () {
      final out = stripFormMarkers(formulier.replaceAll('\n', '\r\n'));
      final scan = scanFormBlocks(formulier);
      final lines = out.split('\n');
      for (final i in scan.markerLines) {
        expect(lines[i], '\r', reason: 'regel $i');
      }
      expect(out, isNot(contains('<!--')));
    });

    test(
      'een markerregel in een antwoord is antwoordtekst en blijft staan',
      () {
        final doc = formulier.replaceFirst('Sari', 'a\n<!-- notice -->\nb');
        final out = stripFormMarkers(doc);
        expect(
          out,
          contains('<!-- notice -->'),
          reason: 'het is tekst van de inzender',
        );
      },
    );

    test('een document zonder (geldig) formulier komt ongewijzigd terug', () {
      const plain = '# Titel\n\n<!-- toc -->\n';
      expect(identical(stripFormMarkers(plain), plain), isTrue);
      final kapot = formulier.replaceFirst('<!-- /field id=naam -->\n', '');
      expect(stripFormMarkers(kapot), kapot);
    });
  });

  test('het voorbeeld in FILE_FORMAT §14.14 is een geldig formulier', () {
    // Een beschrijving van het formaat die zelf niet ontleedt is een belofte
    // die niemand heeft nagelopen.
    final doc = File('docs/FILE_FORMAT.md').readAsStringSync();
    final section = doc.substring(doc.indexOf('### 14.14 Form'));
    final example = RegExp(
      r'````markdown\n(.*?)````',
      dotAll: true,
    ).firstMatch(section)!.group(1)!;

    expect(parseForm(example), isA<ParsedForm>());
    expect(scanFormBlocks(example).blocks.map((b) => b.kind), [
      FormBlockKind.header,
      FormBlockKind.notice,
      FormBlockKind.field,
    ]);
  });
}
