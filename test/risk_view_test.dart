// Tests voor de gekoppelde tabelweergaven uit #2489: materialisatie uit de
// bron, sorteren/filteren, gen-hint versus echte celvergelijking, en de
/// schrijfroutes (nieuw maken, verversen).

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/ocideck_marked_table.dart';
import 'package:ocideck/services/risk_dossier.dart';
import 'package:ocideck/services/risk_view.dart';

const _dossier = '''
<!-- ocideck:risks v1 id=hoofd method=fmea scale=sod-1-10 rev=3 next=4 cols=id,failure,s_b,o_b,d_b,s_n,o_n,d_n -->
| ID | Falingswijze | S_b | O_b | D_b | S_n | O_n | D_n |
|---|---|---|---|---|---|---|---|
| R-1 | Ventiel lekt | 8 | 4 | 3 | 8 | 2 | 3 |
| R-2 | Sensor blind | 6 | 7 | 5 | 6 | 3 | 5 |
| R-3 | Kabel breekt | 3 | 2 | 9 | | | |
''';

OciMarkedTable _view(String attrs, List<String> bodyLines) {
  final source =
      '$_dossier\n<!-- ocideck:view v1 $attrs -->\n'
      '${bodyLines.join('\n')}';
  final scan = scanOciMarkedTables(source);
  return scan.tables.firstWhere((t) => t.marker?.kind == 'view');
}

void main() {
  group('ociViewMaterialize', () {
    test('netto-projectie toont alleen de netto-kolommen', () {
      final view = _view('source=hoofd projection=netto gen=3', const [
        '| ID | Falingswijze | S_n | O_n | D_n |',
        '|---|---|---|---|---|',
        '| R-1 | Ventiel lekt | 8 | 2 | 3 |',
        '| R-2 | Sensor blind | 6 | 3 | 5 |',
        '| R-3 | Kabel breekt | | | |',
      ]);
      final rows = ociViewMaterialize(RiskDossier.read(_dossier), view)!;
      expect(rows.first, ['ID', 'Faalwijze', 'S n', 'O n', 'D n']);
      expect(rows.length, 4);
      expect(rows[3], ['R-3', 'Kabel breekt', '', '', '']);
    });

    test('overview-projectie toont bruto én netto', () {
      final view = _view('source=hoofd projection=overview gen=3', const [
        '| ID |',
        '|---|',
      ]);
      final rows = ociViewMaterialize(RiskDossier.read(_dossier), view)!;
      expect(rows.first, [
        'ID',
        'Faalwijze',
        'S b',
        'O b',
        'D b',
        'S n',
        'O n',
        'D n',
      ]);
      expect(rows[1].first, 'R-1');
    });

    test('sort= dwingt de materialisatiesortering via de gedeelde service', () {
      final view = _view(
        'source=hoofd projection=overview sort=s_b:desc gen=3',
        const ['| ID |', '|---|'],
      );
      final rows = ociViewMaterialize(
        RiskDossier.read(_dossier),
        view,
      )!.skip(1).toList();
      expect(rows.map((r) => r.first), ['R-1', 'R-2', 'R-3']);
    });

    test('filter=key:value houdt alleen passende rijen over', () {
      final view = _view(
        'source=hoofd projection=netto filter=s_b:6 gen=3',
        const ['| ID |', '|---|'],
      );
      final rows = ociViewMaterialize(
        RiskDossier.read(_dossier),
        view,
      )!.skip(1).toList();
      expect(rows.single.first, 'R-2');
    });

    test('missende bron geeft null, geen crash', () {
      final view = _view('source=weg projection=netto gen=1', const [
        '| ID |',
        '|---|',
      ]);
      expect(ociViewMaterialize(RiskDossier.read(_dossier), view), isNull);
    });

    test('afgeleide rpn materialiseert, onbekend rendert —', () {
      final view = _view(
        'source=hoofd cols=id,rpn,rpn_n gen=3',
        const ['| ID |', '|---|'],
      );
      final rows = ociViewMaterialize(
        RiskDossier.read(_dossier),
        view,
      )!.skip(1).toList();
      // R-1: rpn = 8*4*3 = 96, rpn_n = 8*2*3 = 48.
      expect(rows[0], ['R-1', '96', '48']);
      // R-3: rpn = 3*2*9 = 54; geen netto-inschatting → '—', nooit 0.
      expect(rows[2], ['R-3', '54', '—']);
    });
  });

  group('checkOciView', () {
    test('actuele weergave is consistent', () {
      final source =
          '$_dossier\n<!-- ocideck:view v1 source=hoofd projection=netto gen=3 -->\n'
          '| ID | Falingswijze | S_n | O_n | D_n |\n'
          '|---|---|---|---|---|\n'
          '| R-1 | Ventiel lekt | 8 | 2 | 3 |\n'
          '| R-2 | Sensor blind | 6 | 3 | 5 |\n'
          '| R-3 | Kabel breekt | | | |';
      final view = scanOciMarkedTables(source).tables.last;
      final check = checkOciView(source, view);
      expect(check.consistent, isTrue);
      expect(check.staleGen, isFalse);
    });

    test('handedit in de weergave is een mismatch, geen stille acceptatie', () {
      final source =
          '$_dossier\n<!-- ocideck:view v1 source=hoofd projection=netto gen=3 -->\n'
          '| ID | Falingswijze | S_n | O_n | D_n |\n'
          '|---|---|---|---|---|\n'
          '| R-1 | Ventiel lekt | 8 | 2 | 3 |\n'
          '| R-2 | Sensor blind | 6 | 9 | 5 |\n'
          '| R-3 | Kabel breekt | | | |';
      final view = scanOciMarkedTables(source).tables.last;
      final check = checkOciView(source, view);
      expect(check.consistent, isFalse);
      expect(check.mismatches.single, contains('rij 2'));
      expect(check.mismatches.single, contains('9'));
    });

    test('verlopen gen is een hint, géén celvergelijking', () {
      final source =
          '$_dossier\n<!-- ocideck:view v1 source=hoofd projection=netto gen=1 -->\n'
          '| ID | Falingswijze | S_n | O_n | D_n |\n'
          '|---|---|---|---|---|\n'
          '| R-1 | Ventiel lekt | 8 | 2 | 3 |\n'
          '| R-2 | Sensor blind | 6 | 3 | 5 |\n'
          '| R-3 | Kabel breekt | | | |';
      final view = scanOciMarkedTables(source).tables.last;
      final check = checkOciView(source, view);
      expect(check.staleGen, isTrue);
      // De cellen kloppen nog — gen is ouder, de inhoud niet veranderd.
      expect(check.consistent, isTrue);
    });

    test('bron weg → sourceMissing', () {
      final source = '''
<!-- ocideck:view v1 source=weg projection=netto gen=1 -->
| ID |
|---|
''';
      final view = scanOciMarkedTables(source).tables.first;
      expect(checkOciView(source, view).sourceMissing, isTrue);
    });
  });

  group('schrijfroutes', () {
    test('createOciViewBlock maakt marker + gematerialiseerde tabel', () {
      final block = createOciViewBlock(
        RiskDossier.read(_dossier),
        'hoofd',
        'netto',
      )!;
      expect(block, contains('<!-- ocideck:view v1'));
      expect(block, contains('source=hoofd'));
      expect(block, contains('projection=netto'));
      expect(block, contains('gen=3'));
      expect(block, contains('| R-1 | Ventiel lekt | 8 | 2 | 3 |'));
      // De projection-kolommen ook als attr — herleesbaar.
      final view = scanOciMarkedTables(block).tables.first;
      expect(view.cols, ['id', 'failure', 's_n', 'o_n', 'd_n']);
    });

    test(
      'regenerateOciView werkt body én gen bij, rest van het bestand blijft',
      () {
        final stale =
            '$_dossier\n<!-- ocideck:view v1 source=hoofd projection=netto gen=1 -->\n'
            '| ID | Falingswijze | S_n | O_n | D_n |\n'
            '|---|---|---|---|---|\n'
            '| R-1 | OUDE RIJ | 1 | 1 | 1 |\n\n'
            'Tekst eronder.';
        final view = scanOciMarkedTables(stale).tables.last;
        final out = regenerateOciView(stale, view)!;
        expect(out, contains('gen=3'));
        expect(out, contains('Kabel breekt'));
        expect(out, isNot(contains('OUDE RIJ')));
        expect(out, endsWith('Tekst eronder.'));
        // De bron zelf onaangeroerd.
        expect(out, contains('| R-1 | Ventiel lekt | 8 | 4 | 3 |'));
      },
    );
  });
}
