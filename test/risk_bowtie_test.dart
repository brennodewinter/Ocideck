// Tests voor het Bowtie-bronmodel (#2495): padgroepering, volledigheid,
// rol/zijde-regels en de kwaliteitsbevindingen. Het fixture-dek: twee
// dreigingen, een gedeelde preventieve barrière, één escalatiefactor en
// twee gevolgen — zoals de acceptatie het vraagt.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/ocideck_marked_table.dart';
import 'package:ocideck/services/risk_bowtie.dart';
import 'package:ocideck/services/risk_quality.dart';

const _dossier = '''
<!-- ocideck:bowtie v1 id=bt1 rev=1 cols=path,side,role,element,measure,status,owner -->
| Pad | Zijde | Rol | Element | Maatregel | Status | Eigenaar |
|---|---|---|---|---|---|---|
| P-1 | links | threat | Corrosie | | | |
| P-1 | links | barrier-preventive | Coating inspecteren | M-001 | werkt | J.J. |
| P-1 | links | escalation | Inspectiecapaciteit te kort | M-003 | voorgesteld | |
| P-1 | top | top-event | Breuk in leiding | | | |
| P-1 | rechts | barrier-mitigating | Noodafsluiter | M-002 | werkt | |
| P-1 | rechts | consequence | Overstrooming | | | |
| P-2 | links | threat | Externe graafschade | | | |
| P-2 | links | barrier-preventive | Coating inspecteren | M-001 | werkt | J.J. |
| P-2 | top | top-event | Breuk in leiding | | | |
| P-2 | rechts | barrier-mitigating | Noodafsluiter | M-002 | werkt | |
| P-2 | rechts | consequence | Bodemverontreiniging | | | |

<!-- ocideck:measures v1 id=maatregelen rev=1 next=4 cols=id,type,description,owner,status,evidence,test_date,expires,risks -->
| ID | Type | Beschrijving | Eigenaar | Status | Bewijs | Toetsdatum | Vervalt | Risico's |
|---|---|---|---|---|---|---|---|---|
| M-001 | technisch | Coating inspecteren | J.J. | working | rapport 7 | 2026-02-01 | 2099-01-01 | |
| M-002 | technisch | Noodafsluiter | K.K. | working | test 3 | 2026-02-02 | 2099-01-01 | |
| M-003 | organisch | Inspectiecapaciteit | P.P. | proposed | | | | |
''';

OciMarkedTable _bowtie(String source) =>
    scanOciMarkedTables(source).tables.first;

void main() {
  test('paden groeperen per path, gedeelde barrière telt per pad', () {
    final paths = ociBowtiePaths(_bowtie(_dossier));
    expect(paths.map((p) => p.id), ['P-1', 'P-2']);
    // De gedeelde preventieve barrière (M-001) staat in beide paden.
    expect(paths[0].hasPreventiveBarrier, isTrue);
    expect(paths[1].hasPreventiveBarrier, isTrue);
    expect(paths.every((p) => p.isComplete), isTrue);
  });

  test('een compleet pad is schoon; ontbrekende stukken noemen hun naam', () {
    expect(riskQualityFindings(_dossier).isClean, isTrue);
    final open = _dossier.replaceFirst(
      '| P-2 | rechts | consequence | Bodemverontreiniging | | | |',
      '',
    );
    final report = riskQualityFindings(open);
    final f = report.warnings.singleWhere((w) => w.code == 'bowtie-incomplete');
    expect(f.recordId, 'P-2');
    expect(f.message, contains('gevolg'));
  });

  test('barrière op de verkeerde zijde meldt precies', () {
    final wrong = _dossier.replaceFirst(
      '| P-1 | links | barrier-preventive |',
      '| P-1 | rechts | barrier-preventive |',
    );
    final report = riskQualityFindings(wrong);
    expect(report.warnings.any((w) => w.code == 'bowtie-role-side'), isTrue);
    // En het pad is nu ook incompleet — preventief links ontbreekt.
    expect(report.warnings.any((w) => w.code == 'bowtie-incomplete'), isTrue);
  });

  test('verweesde maatregel en onbekende status melden op rijniveau', () {
    final wrong = _dossier
        .replaceFirst(
          'Coating inspecteren | M-001',
          'Coating inspecteren | M-099',
        )
        .replaceFirst(
          'Noodafsluiter | M-002 | werkt',
          'Noodafsluiter | M-002 | soort-van',
        );
    final report = riskQualityFindings(wrong);
    expect(report.warnings.any((w) => w.code == 'measure-orphan'), isTrue);
    expect(report.warnings.any((w) => w.code == 'bowtie-status'), isTrue);
  });

  test('Nederlandse rol- en statustokens lezen mee', () {
    final nl = _dossier
        .replaceAll('barrier-preventive', 'barriere-preventief')
        .replaceAll('barrier-mitigating', 'barriere-mitigerend')
        .replaceAll('top-event', 'topgebeurtenis')
        .replaceAll('consequence', 'gevolg');
    expect(riskQualityFindings(nl).isClean, isTrue);
  });

  test('Pad toevoegen skelet volgt het contract en de vrije nummering', () {
    final table = _bowtie(_dossier);
    expect(ociNextBowtiePathNumber(table), 3);
    final rows = ociBowtiePathSkeleton(table, 'P-3');
    expect(rows.length, 5);
    expect(rows[0].sublist(0, 3), ['P-3', 'links', 'threat']);
    expect(rows[2].sublist(0, 3), ['P-3', 'top', 'top-event']);
    final out = appendOciTableRows(_dossier, table, rows);
    // Het nieuwe pad staat er als concept bij — compleet als skelet.
    expect(out, contains('| P-3 | links | threat |'));
    final report = riskQualityFindings(out);
    // Het skelet is structureel compleet — geen fouten, geen gaten.
    expect(report.errors, isEmpty);
    expect(report.warnings.any((w) => w.code == 'bowtie-incomplete'), isFalse);
  });
}
