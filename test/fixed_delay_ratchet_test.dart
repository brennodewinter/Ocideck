import 'package:flutter_test/flutter_test.dart';

import '../tool/check_conventions.dart';

/// Het meetinstrument achter de vaste-wachtpuntratchet (`fixedDelaysIn` in
/// `tool/check_conventions.dart`).
///
/// Die poort bestaat sinds de dag dat vier tests om dezelfde reden gerepareerd
/// moesten worden: een `Future.delayed` binnen `runAsync` gokt hoe lang echt
/// werk duurt, en die gok is op de belaste linux-runner soms te krap.
///
/// Hij heeft dat daarna anderhalve maand niet gedaan, en dit bestand is de
/// neerslag daarvan. De poort zocht met een reguliere uitdrukking naar de kale
/// schrijfwijze `Future.delayed(` en las vandaar 400 tekens ver. Drie blinde
/// vlekken zaten daarin, alle drie hieronder als geval:
///
/// 1. **het typeargument** — 126 van de 129 wachtpunten in `test/` schrijven
///    `Future<void>.delayed(`. De poort zag er 3 en meldde groen terwijl
///    `image_carousel_delete_test` negen keer omviel op de linux-gate;
/// 2. **de reikwijdte** — één `pumpWidget` met een widgetboom erin is langer
///    dan 400 tekens, en juist dáár stond het wachtpunt dat omviel;
/// 3. **de omweg** — een wachtpunt in een hulp die vanuit `runAsync` wordt
///    *aangeroepen* staat er niet lexicaal in. `callout_reveal_test._pumpOverlay`
///    had die vorm en is nooit gezien.
///
/// De meting loopt daarom over de AST. Een poort die zijn eigen blinde vlek
/// niet toetst, meet zijn eigen aannames.
void main() {
  Map<String, List<int>> meet(String source) =>
      fixedDelaysIn({'test/x_test.dart': source});

  /// De fixtures zijn echte Dart: de parser is de meting, dus een fragment dat
  /// niet compileert zou hier niets bewijzen.
  String testBestand(String body) =>
      'void main() {\n  test(\'x\', () async {\n$body\n  });\n}\n';

  group('de schrijfwijze van de codebase', () {
    test('het typeargument verbergt het wachtpunt niet', () {
      expect(
        meet(
          testBestand('''
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });'''),
        )['test/x_test.dart'],
        [3],
      );
    });

    test('de kale vorm blijft gevonden', () {
      expect(
        meet(
          testBestand(
            '    await tester.runAsync(() => Future.delayed(pauze));',
          ),
        )['test/x_test.dart'],
        [3],
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
        (i) => '        const SizedBox(width: $i, height: $i),',
      ).join('\n');
      expect(
        meet(
          testBestand('''
    await tester.runAsync(() async {
      await tester.pumpWidget(
        Column(children: [
$vulling
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });'''),
        )['test/x_test.dart'],
        [3],
        reason: 'de aanroep loopt tot haar sluithaakje, niet tot teken 400',
      );
    });

    test('buiten runAsync is een vaste wachttijd geen gok op echt werk', () {
      expect(
        meet(
          testBestand('''
    await tester.runAsync(() async {
      await tester.pump();
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));'''),
        )['test/x_test.dart'],
        isEmpty,
      );
    });
  });

  group('de omweg via een hulp', () {
    test('een hulp die vanuit runAsync wordt aangeroepen telt mee', () {
      // De vorm uit `callout_reveal_test._pumpOverlay`. De oude tekstpoort zag
      // hier niets: binnen de `runAsync` staat geen enkele `Future.delayed`.
      expect(
        meet('''
Future<void> _pumpOverlay(WidgetTester tester) async {
  await tester.pumpWidget(const Placeholder());
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

void main() {
  test('x', () async {
    await tester.runAsync(() async {
      await _pumpOverlay(tester);
    });
  });
}
''')['test/x_test.dart'],
        [8],
        reason: 'het regelnummer wijst de runAsync aan, niet de hulp',
      );
    });

    test('ook een hulp achter een hulp', () {
      expect(
        meet('''
Future<void> _diep() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

Future<void> _midden() async => _diep();

void main() {
  test('x', () async {
    await tester.runAsync(() async {
      await _midden();
    });
  });
}
''')['test/x_test.dart'],
        [9],
      );
    });

    test('een hulp die niemand vanuit runAsync aanroept telt niet', () {
      expect(
        meet('''
Future<void> _ongebruikt() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

void main() {
  test('x', () async {
    await tester.runAsync(() async {
      await tester.pump();
    });
  });
}
''')['test/x_test.dart'],
        isEmpty,
        reason: 'een wachttijd buiten de echte-tijdzone is geen gok op werk',
      );
    });
  });

  test('een tegenvoorbeeld in commentaar of tekst is geen overtreding', () {
    // Zonder dit valt de poort over de uitleg in `pump_until.dart` en over de
    // fixtures in dit bestand — allebei schrijven ze het antipatroon voluit op
    // om te laten zien waaróm het fout is. De AST maakt van commentaar en van
    // een stringliteraal geen aanroepknooppunt, dus dit gaat vanzelf goed.
    expect(
      meet(
        testBestand('''
    await tester.runAsync(() async {
      // NIET: await Future<void>.delayed(const Duration(milliseconds: 80));
      const uitleg = 'await Future<void>.delayed(pauze)';
      await tester.pump(uitleg.length);
    });'''),
      )['test/x_test.dart'],
      isEmpty,
    );
  });

  test('twee wachtpunten in één bestand tellen allebei', () {
    expect(
      meet(
        testBestand('''
    await tester.runAsync(() => Future<void>.delayed(a));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(b));'''),
      )['test/x_test.dart'],
      [3, 5],
    );
  });

  test('een bestand dat niet parseert slaagt niet stilzwijgend', () {
    // De faalvorm die deze hele poort ooit onbruikbaar maakte, is "stil niets
    // meten". Een onparseerbaar bestand mag daar niet opnieuw onder vallen.
    expect(
      meet('void main() { await tester.runAsync( ')['test/x_test.dart'],
      isNotEmpty,
    );
  });
}
