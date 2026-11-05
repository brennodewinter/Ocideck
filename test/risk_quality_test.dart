// Tests voor de risico-kwaliteitscontrole (#2490): dezelfde bevindingen bij
// openen, bewerken, opslaan en export — want de scanner is een pure functie
// over de bron en kent geen sessie.
//
// Blokkerend (error): dubbel/ontbrekend ID, onleesbare of buiten-schaal
// score, weergave zonder bron. Waarschuwing: verouderde weergave,
// verweesde verwijzingen, netto zonder grondslag, verlopen maatregel.
// Herstel is nooit stil: de enige aangeboden reparatie is de weergave
// herbouwen uit de bron.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/risk_dossier.dart';
import 'package:ocideck/services/ocideck_marked_table.dart';
import 'package:ocideck/services/risk_quality.dart';
import 'package:ocideck/services/risk_view.dart';

const _base = '''
<!-- ocideck:risks v1 id=hoofd method=fmea scale=sod-1-10 rev=1 next=4 cols=id,failure,s_b,o_b,d_b,s_n,o_n,d_n,measures,netto_basis -->
| ID | Faalwijze | S b | O b | D b | S n | O n | D n | Maatregelen | Netto-basis |
|---|---|---|---|---|---|---|---|---|---|
| R-001 | Ventiel lekt | 8 | 4 | 3 | 8 | 2 | 3 | M-001 | herijkt na montage |
| R-002 | Sensor blind | 6 | 7 | 5 | | | | | |

<!-- ocideck:measures v1 id=maatregelen rev=1 next=2 cols=id,type,description,owner,status,evidence,test_date,expires,risks -->
| ID | Type | Beschrijving | Eigenaar | Status | Bewijs | Toetsdatum | Vervalt | Risico's |
|---|---|---|---|---|---|---|---|---|
| M-001 | technisch | Dubbele afdichting | Jan | tested | rapport 12 | 2026-01-15 | 2099-01-01 | R-001 |
''';

void main() {
  test('een schoon dossier levert geen bevindingen', () {
    expect(riskQualityFindings(_base).isClean, isTrue);
  });

  test('dubbel ID is blokkerend en noemt beide rijen', () {
    final source = _base.replaceFirst(
      '| R-002 | Sensor blind',
      '| R-001 | Sensor blind',
    );
    final report = riskQualityFindings(source);
    final f = report.errors.singleWhere((f) => f.code == 'duplicate-id');
    expect(f.recordId, 'R-001');
    expect(f.message, contains('regel 1'));
  });

  test('rij zonder ID is blokkerend', () {
    final source = _base.replaceFirst('| R-002 |', '| |');
    final report = riskQualityFindings(source);
    expect(report.errors.any((f) => f.code == 'missing-id'), isTrue);
  });

  test('onleesbare en buiten-schaal-scores zijn blokkerend', () {
    final source = _base
        .replaceFirst(
          '| R-001 | Ventiel lekt | 8 |',
          '| R-001 | Ventiel lekt | acht |',
        )
        .replaceFirst(
          '| R-002 | Sensor blind | 6 |',
          '| R-002 | Sensor blind | 99 |',
        );
    final report = riskQualityFindings(source);
    expect(report.errors.any((f) => f.code == 'score-invalid'), isTrue);
    expect(report.errors.any((f) => f.code == 'score-out-of-range'), isTrue);
  });

  test('sod-1-5 is ingebouwd en toetst scores op 1 tot en met 5', () {
    final schoon = _base
        .replaceFirst('scale=sod-1-10', 'scale=sod-1-5')
        .replaceFirst(
          '| R-001 | Ventiel lekt | 8 | 4 | 3 | 8 | 2 | 3 |',
          '| R-001 | Ventiel lekt | 4 | 2 | 2 | 4 | 1 | 2 |',
        )
        .replaceFirst(
          '| R-002 | Sensor blind | 6 | 7 | 5 |',
          '| R-002 | Sensor blind | 3 | 4 | 3 |',
        );
    expect(riskQualityFindings(schoon).isClean, isTrue);

    final teHoog = schoon.replaceFirst(
      '| R-002 | Sensor blind | 3 | 4 | 3 |',
      '| R-002 | Sensor blind | 3 | 6 | 3 |',
    );
    final report = riskQualityFindings(teHoog);
    expect(report.errors.any((f) => f.code == 'scale-unknown'), isFalse);
    expect(report.errors.any((f) => f.code == 'score-out-of-range'), isTrue);
  });

  test('Nederlandse maatregelstatussen worden herkend', () {
    expect(MeasureStatus.parse('voorgesteld'), MeasureStatus.proposed);
    expect(MeasureStatus.parse('Gepland'), MeasureStatus.planned);
    expect(MeasureStatus.parse('ingevoerd'), MeasureStatus.implemented);
    expect(MeasureStatus.parse('getoetst'), MeasureStatus.tested);
    expect(MeasureStatus.parse('werkt'), MeasureStatus.working);
    expect(MeasureStatus.parse('werkt  niet'), MeasureStatus.ineffective);
    expect(MeasureStatus.parse('working'), MeasureStatus.working);
    expect(MeasureStatus.parse('misschien'), isNull);

    final source = _base.replaceFirst(
      '| tested | rapport 12 |',
      '| getoetst | rapport 12 |',
    );
    expect(riskQualityFindings(source).isClean, isTrue);
  });

  test('onbekende schaalnaam is blokkerend', () {
    final source = _base.replaceFirst('scale=sod-1-10', 'scale=fantasy-9');
    final report = riskQualityFindings(source);
    expect(report.errors.any((f) => f.code == 'scale-unknown'), isTrue);
  });

  test('netto zonder grondslag is een waarschuwing, geen stil oordeel', () {
    // R-002 netto ingevuld, geen maatregel, geen basis.
    final source = _base.replaceFirst(
      '| R-002 | Sensor blind | 6 | 7 | 5 | | | | | |',
      '| R-002 | Sensor blind | 6 | 7 | 5 | 6 | 3 | 5 | | |',
    );
    final report = riskQualityFindings(source);
    final f = report.warnings.singleWhere((w) => w.code == 'netto-unjustified');
    expect(f.recordId, 'R-002');
  });

  test('een geplande maatregel rechtvaardigt geen netto-score', () {
    final source = _base
        .replaceFirst(
          '| R-002 | Sensor blind | 6 | 7 | 5 | | | | | |',
          '| R-002 | Sensor blind | 6 | 7 | 5 | 6 | 3 | 5 | M-002 | |',
        )
        .replaceFirst(
          '| M-001 | technisch | Dubbele afdichting | Jan | tested | rapport 12 | 2026-01-15 | 2099-01-01 | R-001 |',
          '| M-001 | technisch | Dubbele afdichting | Jan | tested | rapport 12 | 2026-01-15 | 2099-01-01 | R-001 |\n'
              '| M-002 | technisch | Extra sensor | Kees | planned | | | | R-002 |',
        );
    final report = riskQualityFindings(source);
    expect(report.warnings.any((w) => w.code == 'netto-unjustified'), isTrue);
  });

  test('verweesde verwijzingen melden in beide richtingen', () {
    final source = _base
        .replaceFirst('| M-001 |', '| M-001 |')
        .replaceFirst('R-001 |', 'R-001 |') // noop, leesbaarheid
        .replaceFirst('| R-001 | Ventiel lekt', '| R-001 | Ventiel lekt')
        .replaceFirst('M-001 | herijkt', 'M-099 | herijkt')
        .replaceFirst('| R-001 |\n', '| R-999 |\n');
    final report = riskQualityFindings(source);
    expect(report.warnings.any((w) => w.code == 'measure-orphan'), isTrue);
    expect(report.warnings.any((w) => w.code == 'risk-orphan'), isTrue);
  });

  test('verlopen maatregel en ontbrekende toetsdatum waarschuwen', () {
    final source = _base.replaceFirst(
      '2099-01-01 | R-001 |',
      '2020-01-01 | R-001 |',
    );
    final report = riskQualityFindings(source);
    expect(report.warnings.any((w) => w.code == 'measure-expired'), isTrue);
  });

  test('een weergave die van de bron afwijkt is herstelbaar via verversen', () {
    final source =
        '$_base\n<!-- ocideck:view v1 source=hoofd projection=netto gen=1 cols=id,failure,s_n,o_n,d_n -->\n'
        '| ID | Faalwijze | S n | O n | D n |\n'
        '|---|---|---|---|---|\n'
        '| R-001 | VERLOPEN | 9 | 9 | 9 |';
    final report = riskQualityFindings(source);
    final f = report.warnings.singleWhere((w) => w.code == 'view-mismatch');
    expect(f.repair, RiskQualityRepair.refreshView);

    // Herstel = herbouwen uit de bron; daarna is de controle schoon.
    final fixed = regenerateOciView(source, f.repairTable!)!;
    expect(riskQualityFindings(fixed).isClean, isTrue);
  });

  test('een weergave zonder bron is blokkerend en niet auto-herstelbaar', () {
    final source =
        '$_base\n<!-- ocideck:view v1 source=weg projection=netto gen=1 -->\n'
        '| ID |\n|---|';
    final report = riskQualityFindings(source);
    final f = report.errors.singleWhere((e) => e.code == 'view-source-missing');
    expect(f.repair, RiskQualityRepair.none);
  });

  test('een losgekoppelde kopie is een gewone tabel zonder bevindingen', () {
    // Loskoppelen wist de marker — wat overblijft is proza-tabel, geen
    // contract meer. De controle ziet er niets in.
    final source =
        '$_base\n| ID | Faalwijze | S n | O n | D n |\n'
        '|---|---|---|---|---|\n'
        '| R-001 | OUDE KOPIE | 9 | 9 | 9 |';
    expect(riskQualityFindings(source).isClean, isTrue);
  });

  // #2803: een externe editor die na een HTML-commentaar een lege regel
  // zet, maakt een dossier ongemerkt kapot. De controle meldt dat nu als
  // 'marker-detached' met één herstelhandeling.
  test('tijdlijnmarker los van zijn tabel is blokkerend en herstelbaar', () {
    const source =
        '<!-- timeline -->\n\n| Tijd | Wat |\n|---|---|\n| 1 | x |\n';
    final report = riskQualityFindings(source);
    final f = report.errors.singleWhere((e) => e.code == 'marker-detached');
    expect(f.line, 1);
    expect(f.repair, RiskQualityRepair.reattachMarker);

    final fixed = reattachDetachedMarker(source, f.line)!;
    expect(fixed, '<!-- timeline -->\n| Tijd | Wat |\n|---|---|\n| 1 | x |\n');
    expect(
      riskQualityFindings(
        fixed,
      ).findings.where((x) => x.code == 'marker-detached'),
      isEmpty,
    );
  });

  test('een van zijn stapel afgesplitste oci-marker is herstelbaar', () {
    // Marker+witregel+tabel bindt al; wat breekt is de stapel: een lege
    // regel tussen twee markers maakt de eerste een wees (#2803).
    const source =
        '<!-- ocideck:risks v1 id=hoofd cols=id,v -->\n\n'
        '<!-- ocideck:calc v1 col=v expr="1" -->\n'
        '| ID | V |\n|---|---|\n| R-001 | 1 |\n';
    final report = riskQualityFindings(source);
    final f = report.errors.singleWhere((e) => e.code == 'marker-detached');
    expect(f.line, 1);

    // De herstelknop voegt de marker weer aan zijn stapel toe; de witregel
    // tussen stapel en tabel is legaal en blijft staan.
    final fixed = reattachDetachedMarker(source, f.line)!;
    expect(riskQualityFindings(fixed).isClean, isTrue);
  });

  test('een marker zonder tabel is een aparte, lichtere bevinding', () {
    const source =
        '<!-- ocideck:risks v1 id=zwever cols=id -->\n\n'
        'Gewone tekst ertussen.\n\n'
        '<!-- timeline -->\n\nOok geen tabel.\n';
    final report = riskQualityFindings(source);
    expect(report.errors, isEmpty);
    final orphans = report.warnings.where((w) => w.code == 'marker-orphan');
    expect(orphans, hasLength(2));
    expect(orphans.map((w) => w.line), [1, 5]);
  });

  test('een direct gebonden tijdlijn en markers in fences zijn schoon', () {
    const source =
        '<!-- timeline -->\n| Tijd | Wat |\n|---|---|\n| 1 | x |\n\n'
        '```\n<!-- timeline -->\n\n| niet | echt |\n|---|---|\n```\n';
    final report = riskQualityFindings(source);
    expect(
      report.findings.where(
        (f) => f.code == 'marker-detached' || f.code == 'marker-orphan',
      ),
      isEmpty,
    );
  });

  // #2804: een register met scoring=single legt één score vast; netto
  // hoort daar niet en is een waarschuwing als het toch ingevuld is.
  test('scoring=single verwacht geen netto en geen netto_basis', () {
    const schoon = '''
<!-- ocideck:risks v1 id=hoofd method=fmea scale=sod-1-5 scoring=single rev=1 next=2 cols=id,failure,s_b,o_b,d_b -->
| ID | Faalwijze | S | O | D |
|---|---|---|---|---|
| R-001 | Ventiel lekt | 4 | 2 | 2 |
''';
    expect(riskQualityFindings(schoon).isClean, isTrue);

    const metNetto = '''
<!-- ocideck:risks v1 id=hoofd method=fmea scale=sod-1-5 scoring=single rev=1 next=2 cols=id,failure,s_b,o_b,d_b,s_n,netto_basis -->
| ID | Faalwijze | S | O | D | S n | Netto-basis |
|---|---|---|---|---|---|---|
| R-001 | Ventiel lekt | 4 | 2 | 2 | 2 | herijkt |
''';
    final report = riskQualityFindings(metNetto);
    final f = report.warnings.singleWhere((w) => w.code == 'netto-in-single');
    expect(f.recordId, 'R-001');
  });

  test('bevindingen dragen hun regelnummer voor navigatie', () {
    final source = _base.replaceFirst('| R-002 |', '| |');
    final report = riskQualityFindings(source);
    final f = report.errors.single;
    // Regel 5 in de fixture is de R-002-rij.
    expect(f.line, 5);
  });
}
