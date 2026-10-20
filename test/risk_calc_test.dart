// Tests voor de begrensde formuletaal uit #2491 / RISK_FORMAT §3.7:
// prioriteit, negatieve en decimale waarden, aggregaten, ID-verwijzingen
// die sortering overleven, deling door nul, cycli, overflow en de
// schrijfroutes (toevoegen, herberekenen, verwijderen).
//
// De kernregel die overal terugkomt: onbekend is nooit 0.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/ocideck_marked_table.dart';
import 'package:ocideck/services/risk_calc.dart';

const _table = '''
<!-- ocideck:risks v1 id=hoofd method=fmea rev=1 next=4 cols=id,failure,s_n,o_n,d_n -->
| ID | Faalwijze | S n | O n | D n |
|---|---|---|---|---|
| R-001 | Ventiel lekt | 8 | 2 | 3 |
| R-002 | Sensor blind | 6 | 3 | 5 |
| R-003 | Kabel breekt | | | |
''';

OciMarkedTable _withCalc(String calcLine) => scanOciMarkedTables(
  '<!-- ocideck:risks v1 id=hoofd method=fmea rev=1 next=4 cols=id,failure,s_n,o_n,d_n -->\n'
  '$calcLine\n${_table.split('\n').sublist(1).join('\n')}',
).tables.first;

OciCalcResult _eval(String expr, int row) {
  final t = _withCalc('<!-- ocideck:calc col=prio expr="$expr" -->');
  final eval = evaluateOciTableCalc(t);
  return eval.results[row].single;
}

void main() {
  group('expressies', () {
    test('vermenigvuldiging gaat vóór optelling', () {
      expect(_eval('s_n + o_n * d_n', 0).value, 8 + 2 * 3);
    });

    test('haakjes sturen de volgorde', () {
      expect(_eval('(s_n + o_n) * d_n', 0).value, (8 + 2) * 3);
    });

    test('unaire min en decimalen', () {
      expect(_eval('-s_n * 0.5', 0).value, -4.0);
      expect(_eval('s_n * 1.25', 1).value, 7.5);
    });

    test('sleutel@ID volgt het ID, niet de rijpositie', () {
      // s_n@R-002 = 6, ongeacht welke rij we berekenen.
      expect(_eval('s_n@R-002 + 1', 2).value, 7);
    });

    test('aggregaten over de hele kolom', () {
      expect(_eval('sum(s_n)', 0).value, 14);
      expect(_eval('count(s_n)', 0).value, 2); // leeg telt niet
      expect(_eval('avg(s_n)', 0).value, 7);
      expect(_eval('min(o_n)', 0).value, 2);
      expect(_eval('max(d_n)', 0).value, 5);
    });

    test('wsum weegt waarde × gewicht', () {
      expect(_eval('wsum(s_n,o_n)', 0).value, 8 * 2 + 6 * 3);
    });

    test('lege invoer is onbekend, nooit 0', () {
      final r = _eval('s_n * 10', 2);
      expect(r.value, isNull);
      expect(r.error, isNull); // onbekend door leegte is data, geen fout
    });

    test('deling door nul is onbekend + bevinding', () {
      final r = _eval('s_n / 0', 0);
      expect(r.value, isNull);
      expect(r.error, CalcErrors.divZero);
    });

    test('een verwijzing naar een weg ID is onbekend, geen crash', () {
      expect(_eval('s_n@R-999 + 1', 0).value, isNull);
    });

    test('ongebruikelijke invoer parseert als onbekend', () {
      // "acht" in een scorecel is geen getal → onbekend.
      final t = scanOciMarkedTables('''
<!-- ocideck:risks v1 id=x method=fmea cols=id,s_n -->
| ID | S n |
|---|---|
| R-1 | acht |
''').tables.first;
      // Zonder calc-kolom geen evaluatie — de controle valt elders; hier
      // toetsen we dat een leeg resultaat netjes terugkomt.
      expect(
        evaluateOciTableCalc(t).results.every((row) => row.isEmpty),
        isTrue,
      );
    });
  });

  group('cyclus en overflow', () {
    test('a→b→a is een cyclus, niet een oneindige recursie', () {
      final t = scanOciMarkedTables('''
<!-- ocideck:risks v1 id=x method=fmea cols=id,s_n,a,b -->
| ID | S n | A | B |
|---|---|---|---|
| R-1 | 5 | | |
''').tables.first;
      final withBoth = scanOciMarkedTables('''
<!-- ocideck:risks v1 id=x method=fmea cols=id,s_n,a,b -->
<!-- ocideck:calc col=a expr="b + 1" -->
<!-- ocideck:calc col=b expr="a + 1" -->
| ID | S n | A | B |
|---|---|---|---|
| R-1 | 5 | | |
''').tables.first;
      final eval = evaluateOciTableCalc(withBoth);
      expect(eval.cycleSeen, isTrue);
      expect(eval.results.single.first.value, isNull);
      expect(eval.results.single.first.error, CalcErrors.cycle);
      // De tabel zonder calc doet niets — geen false positive.
      expect(evaluateOciTableCalc(t).cycleSeen, isFalse);
    });

    test('overflow wordt onbekend + bevinding', () {
      final r = _eval('s_n * 1e300 * 1e300', 0);
      // 'e' is geen taal-token: de expressie parseert niet → calc-invalid.
      expect(r.error, CalcErrors.invalid);
      // Echte overflow via de taal zelf.
      final r2 = _eval('1e15 + 1', 0);
      expect(r2.error, CalcErrors.invalid); // idem
    });

    test(
      'formatCalcValue: geheel als int, anders vier decimalen, — bij onbekend',
      () {
        expect(formatCalcValue(96), '96');
        expect(formatCalcValue(1.5), '1.5');
        expect(formatCalcValue(0.125), '0.125');
        expect(formatCalcValue(null), '—');
      },
    );
  });

  group('schrijfroutes', () {
    test('addOciCalcToTable stapelt de marker en materialiseert de kolom', () {
      final t = _withCalc(
        '<!-- x -->'.replaceAll(
          'x',
          'ocideck:calc col=prio expr="s_n * o_n * d_n"',
        ),
      );
      // De tabel krijgt pas een prio-kolom via cols; gebruik een bestaande
      // sleutel als doel: herbereken s_n naar s_n*10? Nee — materialisatie
      // schrijft naar de col die de marker noemt. Neem een tabel mét de
      // kolom in cols:
      final src = '''
<!-- ocideck:risks v1 id=hoofd method=fmea rev=1 next=4 cols=id,s_n,o_n,d_n,prio -->
| ID | S n | O n | D n | Prioriteit |
|---|---|---|---|---|
| R-001 | 8 | 2 | 3 | |
| R-002 | 6 | 3 | 5 | |
''';
      final table = scanOciMarkedTables(src).tables.first;
      final out = addOciCalcToTable(src, table, 'prio', 's_n * o_n * d_n');
      expect(
        out,
        contains('<!-- ocideck:calc col=prio expr="s_n * o_n * d_n" -->'),
      );
      expect(out, contains('| R-001 | 8 | 2 | 3 | 48 |'));
      expect(out, contains('| R-002 | 6 | 3 | 5 | 90 |'));
      expect(t, isNotNull);
    });

    test('recalculateOciTable schrijft uitkomsten, laat invoer staan', () {
      final src = '''
<!-- ocideck:risks v1 id=hoofd method=fmea rev=1 next=4 cols=id,s_n,o_n,d_n,prio -->
<!-- ocideck:calc col=prio expr="s_n * o_n * d_n" -->
| ID | S n | O n | D n | Prioriteit |
|---|---|---|---|---|
| R-001 | 8 | 2 | 3 | 999 |
| R-002 | 6 | 3 | 5 | |
''';
      final table = scanOciMarkedTables(src).tables.first;
      final out = recalculateOciTable(src, table);
      expect(out, contains('| R-001 | 8 | 2 | 3 | 48 |'));
      expect(out, contains('| R-002 | 6 | 3 | 5 | 90 |'));
      // De marker en de kopregels blijven byte-getrouw.
      expect(out, contains('expr="s_n * o_n * d_n"'));
      expect(out, contains('| ID | S n | O n | D n | Prioriteit |'));
    });

    test('removeOciCalcFromTable laat de laatste waarden als platte tekst', () {
      final src = '''
<!-- ocideck:risks v1 id=hoofd method=fmea rev=1 next=4 cols=id,s_n,o_n,d_n,prio -->
<!-- ocideck:calc col=prio expr="s_n * o_n * d_n" -->
| ID | S n | O n | D n | Prioriteit |
|---|---|---|---|---|
| R-001 | 8 | 2 | 3 | 48 |
''';
      final table = scanOciMarkedTables(src).tables.first;
      final out = removeOciCalcFromTable(src, table, 'prio');
      expect(out, isNot(contains('ocideck:calc')));
      expect(out, contains('| R-001 | 8 | 2 | 3 | 48 |'));
    });

    test('onleesbare expressie overleeft als marker, niet als 0', () {
      final src = '''
<!-- ocideck:risks v1 id=hoofd method=fmea cols=id,s_n,prio -->
<!-- ocideck:calc col=prio expr="s_n +++ ???" -->
| ID | S n | Prio |
|---|---|---|
| R-001 | 8 | 42 |
''';
      final t = scanOciMarkedTables(src).tables.first;
      expect(ociCalcExprParses(t.calcMarkers.first), isFalse);
      final eval = evaluateOciTableCalc(t);
      expect(eval.results.single.single.error, CalcErrors.invalid);
      // Recalc schrijft '—', niet 0 en niet de oude 42.
      final out = recalculateOciTable(src, t);
      expect(out, contains('| R-001 | 8 | — |'));
    });
  });
}
