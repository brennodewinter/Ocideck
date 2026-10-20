import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/risk_dossier.dart';
import 'package:ocideck/services/ocideck_marked_table.dart';
import 'package:ocideck/services/ocideck_markers.dart';
import 'package:ocideck/services/risk_dossier.dart';

void main() {
  group('markergammatica (RISK_FORMAT §2)', () {
    test('leest soort, versie en attributen uit één regel', () {
      final m = parseOciTableMarker(
        '<!-- ocideck:risks v1 id=hoofd method=fmea rev=3 -->',
      )!;
      expect(m.kind, 'risks');
      expect(m.version, 1);
      expect(m.attr('id'), 'hoofd');
      expect(m.intAttr('rev'), 3);
      expect(m.kindKnown, isTrue);
      expect(m.versionSupported, isTrue);
    });

    test('aangehaalde waarden met spaties en pijpen overleven de rondreis', () {
      const line = '<!-- ocideck:calc col=rpn expr="s_n * o_n | x" -->';
      final m = parseOciTableMarker(line)!;
      expect(m.attr('expr'), 's_n * o_n | x');
      expect(m.toComment(), line);
    });

    test('aanhalingstekens en backslashes in waarden escapen heen en weer', () {
      final m = OciTableMarker(
        kind: 'view',
        version: 1,
        attrs: {'note': 'hij zei "ja" \\ echt'},
      );
      final round = parseOciTableMarker(m.toComment())!;
      expect(round.attr('note'), 'hij zei "ja" \\ echt');
    });

    test('een onbekende soort en vreemde tokens reizen ongemoeid mee', () {
      const line = '<!-- ocideck:quantum v9 id=q1 weird-token k=v -->';
      final m = parseOciTableMarker(line)!;
      expect(m.kind, 'quantum');
      expect(m.kindKnown, isFalse);
      expect(m.versionSupported, isFalse);
      expect(m.extras, ['weird-token']);
      expect(m.attr('k'), 'v');
    });

    test('ocideck_-diadirectieven zijn geen tabelmarker', () {
      expect(parseOciTableMarker('<!-- ocideck_template: fmea -->'), isNull);
      expect(isOciTableMarkerLine('<!-- ocideck_template: fmea -->'), isFalse);
    });

    test('withAttr zet, wijzigt en verwijdert zonder de volgorde te raken', () {
      final m = OciTableMarker(
        kind: 'risks',
        version: 1,
        attrs: {'id': 'hoofd', 'rev': '3'},
      );
      expect(
        m.withAttr('rev', '4').toComment(),
        '<!-- ocideck:risks v1 id=hoofd rev=4 -->',
      );
      expect(
        m.withAttr('method', 'fmea').toComment(),
        '<!-- ocideck:risks v1 id=hoofd rev=3 method=fmea -->',
      );
      expect(
        m.withAttr('rev', null).toComment(),
        '<!-- ocideck:risks v1 id=hoofd -->',
      );
    });
  });

  group('scanner (RISK_FORMAT §5)', () {
    test('het voorbeelddossier levert zes gemarkeerde tabellen', () {
      final source = File(
        'docs/design/examples/risk-dossier.md',
      ).readAsStringSync();
      final scan = scanOciMarkedTables(source);
      expect(scan.tables, hasLength(6));
      expect(scan.tables.map((t) => t.kind).toList(), [
        'scale',
        'risks',
        'measures',
        'view',
        'view',
        'bowtie',
      ]);
      expect(scan.orphanMarkerLines, isEmpty);

      final hoofd = scan.tables[1];
      expect(hoofd.id, 'hoofd');
      expect(hoofd.rev, 3);
      expect(hoofd.next, 4);
      expect(hoofd.cols, hasLength(16));
      expect(hoofd.cell(0, 'id'), 'R-001');
      expect(hoofd.cell(0, 's_b'), '7');
      expect(hoofd.cell(2, 'd_b'), '8');
    });

    test('een marker zonder tabel bindt niet maar verdwijnt ook niet', () {
      const source =
          '<!-- ocideck:risks v1 id=zwever -->\n'
          '\n'
          'Gewone tekst ertussen.\n';
      final scan = scanOciMarkedTables(source);
      expect(scan.tables, isEmpty);
      expect(scan.orphanMarkerLines, [
        (0, '<!-- ocideck:risks v1 id=zwever -->'),
      ]);
    });

    test('markers in een fenced blok zijn letterlijke tekst', () {
      const source =
          '```\n'
          '<!-- ocideck:risks v1 id=nep -->\n'
          '| A |\n|---|\n| 1 |\n'
          '```\n';
      expect(scanOciMarkedTables(source).tables, isEmpty);
    });

    test('een gestapelde calc-marker reist op de draagtabel mee', () {
      const source =
          '<!-- ocideck:risks v1 id=hoofd next=2 -->\n'
          '<!-- ocideck:calc col=rpn expr="s_b * o_b * d_b" -->\n'
          '\n'
          '| ID | S |\n|---|---|\n| R-001 | 5 |\n';
      final t = scanOciMarkedTables(source).tables.single;
      expect(t.marker!.kind, 'risks');
      expect(t.calcMarkers, hasLength(1));
      expect(t.calcMarkers.single.attr('expr'), 's_b * o_b * d_b');
    });
  });

  group('terugschrijven (RISK_FORMAT §5)', () {
    const source =
        '# Kop\n'
        '\n'
        '<!-- ocideck:risks v1 id=hoofd rev=3 next=4 cols=id,failure,s_b -->\n'
        '| ID | Faalwijze | S b |\n'
        '|---|---|---|\n'
        '| R-001 | Sensor valt uit | 7 |\n'
        '| R-002 | Display wijkt af | 5 |\n'
        '\n'
        'Naloop.\n';

    test('alleen een attribuut wijzigen raakt uitsluitend de markerregel', () {
      final t = scanOciMarkedTables(source).tables.single;
      final next = rewriteOciMarkedTableAttr(source, t, 'rev', '4');
      expect(
        next,
        contains(
          '<!-- ocideck:risks v1 id=hoofd rev=4 next=4 cols=id,failure,s_b -->',
        ),
      );
      // De rest van het bestand is byte-identiek.
      expect(
        next.split('\n').skip(3).join('\n'),
        source.split('\n').skip(3).join('\n'),
      );
    });

    test('body-rijen vervangen laat kop, scheiding en markers staan', () {
      final t = scanOciMarkedTables(source).tables.single;
      final next = rewriteOciMarkedTable(
        source,
        t,
        bodyRows: [
          ['R-002', 'Display wijkt af', '5'],
          ['R-001', 'Sensor valt uit', '7'],
        ],
      );
      expect(
        next,
        source.replaceFirst(
          '| R-001 | Sensor valt uit | 7 |\n| R-002 | Display wijkt af | 5 |',
          '| R-002 | Display wijkt af | 5 |\n| R-001 | Sensor valt uit | 7 |',
        ),
      );
    });

    test('een cel met een pijp escapet zoals elke OciDeck-tabel', () {
      final t = scanOciMarkedTables(source).tables.single;
      final next = rewriteOciMarkedTable(
        source,
        t,
        bodyRows: [
          ['R-001', 'A|B', '7'],
          ['R-002', 'Display wijkt af', '5'],
        ],
      );
      expect(next, contains(r'| R-001 | A\|B | 7 |'));
    });

    test('bumpRev telt één bij op de draagmarker', () {
      final t = scanOciMarkedTables(source).tables.single;
      expect(bumpOciMarkedTableRev(source, t), contains('rev=4'));
    });
  });

  group('dossier-leeslaag', () {
    test('risico- en maatregelrecords met afgeleide scores', () {
      final source = File(
        'docs/design/examples/risk-dossier.md',
      ).readAsStringSync();
      final dossier = RiskDossier.read(source);

      expect(dossier.risks, hasLength(3));
      expect(dossier.measures, hasLength(3));

      final r1 = dossier.riskById('R-001')!;
      expect(r1.failure, 'Sensor valt uit');
      expect(r1.rpnBruto, 7 * 4 * 5);
      expect(r1.rpnNetto, 7 * 2 * 3);
      expect(r1.nettoBasis, contains('getoetst'));
      expect(r1.measureIds, ['M-001']);

      // R-002 heeft geen netto-scores: "niet berekenbaar", nooit 0.
      final r2 = dossier.riskById('R-002')!;
      expect(r2.rpnBruto, 5 * 3 * 6);
      expect(r2.rpnNetto, isNull);

      final m1 = dossier.measureById('M-001')!;
      expect(m1.status, MeasureStatus.working);
      expect(m1.status!.justifiesNetto, isTrue);
      expect(dossier.measureById('M-003')!.status, MeasureStatus.planned);
      expect(dossier.measureById('M-003')!.status!.justifiesNetto, isFalse);

      expect(dossier.scaleFor(dossier.riskTables.single)!.id, 'sod-1-10');
      expect(dossier.viewTables, hasLength(2));
      expect(dossier.bowtieElements, hasLength(6));
    });

    test('ID-allocatie via next= is een eenrichtingsteller', () {
      const source =
          '<!-- ocideck:risks v1 id=hoofd next=4 cols=id,failure -->\n'
          '| ID | Faalwijze |\n|---|---|\n| R-003 | Klep hangt |\n';
      final t = scanOciMarkedTables(source).tables.single;
      final (id, next) = allocateOciContractId(source, t)!;
      expect(id, 'R-004');
      expect(next, contains('next=5'));
      // Een tabel zonder next= deelt geen ID's uit.
      const noNext =
          '<!-- ocideck:risks v1 id=hoofd cols=id,failure -->\n'
          '| ID | Faalwijze |\n|---|---|\n| R-003 | Klep hangt |\n';
      expect(
        allocateOciContractId(
          noNext,
          scanOciMarkedTables(noNext).tables.single,
        ),
        isNull,
      );
    });

    test('het voorbeelddossier overleeft een ongemoeide rondreis', () {
      final source = File(
        'docs/design/examples/risk-dossier.md',
      ).readAsStringSync();
      final scan = scanOciMarkedTables(source);
      var out = source;
      // Elke tabel "herschreven" zonder wijziging moet byte-identiek blijven.
      for (final t in scan.tables) {
        out = rewriteOciMarkedTable(out, t);
      }
      expect(out, source);
    });
  });
}
