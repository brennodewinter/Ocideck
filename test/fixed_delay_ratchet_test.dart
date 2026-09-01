import 'package:flutter_test/flutter_test.dart';

import '../tool/check_conventions.dart';

/// Het meetinstrument achter de vaste-wachtpuntratchet (`fixedDelaysIn` in
/// `tool/check_conventions.dart`).
///
/// Die poort bestaat sinds de dag dat vier tests om dezelfde reden gerepareerd
/// moesten worden: een `Future.delayed` binnen `runAsync` gokt hoe lang echt
/// werk duurt, en die gok is op de belaste linux-runner soms te krap.
///
/// Hij heeft dat daarna anderhalve maand niet gedaan. De poort zocht de kale
/// schrijfwijze `Future.delayed(` en keek 400 tekens ver, terwijl de codebase
/// `Future<void>.delayed(` schrijft en `pumpWidget` er makkelijk 400 tekens
/// tussen zet. Van de 129 wachtpunten in `test/` zag hij er 3 — en meldde
/// groen terwijl `image_carousel_delete_test` negen keer omviel op precies de
/// fout die hij hoort te vangen.
///
/// Beide blinde vlekken staan hieronder als geval. Een poort die zijn eigen
/// blinde vlek niet toetst, meet zijn eigen aannames.
void main() {
  Map<String, List<int>> meet(String source) =>
      fixedDelaysIn({'test/x_test.dart': source});

  group('de schrijfwijze van de codebase', () {
    test('het typeargument verbergt het wachtpunt niet', () {
      // Dit is de vorm die 126 van de 129 keer in test/ staat.
      expect(
        meet('''
void main() {
  test('x', () async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });
}
''')['test/x_test.dart'],
        [3],
      );
    });

    test('de kale vorm blijft gevonden', () {
      expect(
        meet('''
await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
''')['test/x_test.dart'],
        [1],
      );
    });
  });

  group('hoe ver de aanroep reikt', () {
    test('een wachtpunt achter een grote widgetboom telt mee', () {
      // De vorm uit `image_carousel_delete_test.pumpPicker`: de `pumpWidget`
      // ertussen is ruim langer dan het venster van 400 tekens dat hier ooit
      // stond, en juist dit wachtpunt liet de gate negen keer omvallen.
      final vulling = List.generate(
        40,
        (i) => '      const SizedBox(width: $i, height: $i),',
      ).join('\n');
      expect(
        meet('''
await tester.runAsync(() async {
  await tester.pumpWidget(
    Column(children: [
$vulling
    ]),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
});
''')['test/x_test.dart'],
        [1],
        reason:
            'de aanroep loopt door tot haar sluithaakje, niet tot tekst 400',
      );
    });

    test('het volgende blok wordt er niet bij getrokken', () {
      expect(
        meet('''
await tester.runAsync(() async {
  await tester.pump();
});
await Future<void>.delayed(const Duration(milliseconds: 300));
''')['test/x_test.dart'],
        isEmpty,
        reason: 'buiten runAsync is een vaste wachttijd geen gok op echt werk',
      );
    });

    test('een haakje in een string telt niet als sluithaakje', () {
      expect(
        meet('''
await tester.runAsync(() async {
  expect(find.text('klaar :-)'), findsOneWidget);
  await Future<void>.delayed(const Duration(milliseconds: 50));
});
''')['test/x_test.dart'],
        [1],
      );
    });
  });

  test('een tegenvoorbeeld in commentaar is geen overtreding', () {
    // Zonder dit valt de poort over de uitleg in `pump_until.dart`, die het
    // antipatroon voluit opschrijft om te laten zien waaróm het fout is.
    expect(
      meet('''
await tester.runAsync(() async {
  // NIET: await Future<void>.delayed(const Duration(milliseconds: 80));
  await tester.pump();
});
''')['test/x_test.dart'],
      isEmpty,
    );
  });

  test('twee wachtpunten in één bestand tellen allebei', () {
    expect(
      meet('''
await tester.runAsync(() => Future<void>.delayed(a));
await tester.pump();
await tester.runAsync(() => Future<void>.delayed(b));
''')['test/x_test.dart'],
      [1, 3],
    );
  });
}
