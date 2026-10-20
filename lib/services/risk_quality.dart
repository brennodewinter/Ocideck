/// De risico-kwaliteitscontrole uit #2490: dezelfde toets bij openen, na
/// bewerken, vóór opslaan en vóór export — blokkerende integriteitsfouten
/// apart van inhoudelijke waarschuwingen.
///
/// De controle *leest* alleen; herstel is altijd een menselijke keuze. De
/// enige reparatie die veilig kan lopen zonder een beoordeling te raden is
/// een gekoppelde weergave verversen — want die is per definitie een
/// afschrijving van de bron (D2, §3.6).
library;

import '../models/risk_dossier.dart';
import 'ocideck_marked_table.dart';
import 'ocideck_markers.dart';
import 'risk_calc.dart';
import 'risk_dossier.dart';
import 'risk_view.dart';

/// Blokkerend ([error]) betekent: de cijfers in dit bestand zijn niet
/// betrouwbaar — een dubbel ID, een score buiten schaal, een weergave
/// zonder bron. De mens moet kiezen; de app mag niet raden.
/// [warning] is inhoudelijk: waarneembaar, herstelbaar of toelaatbaar,
/// maar nooit stil opgeborgen.
enum RiskQualitySeverity { error, warning }

/// Welke veilige herstelactie bij een bevinding past. Alleen
/// [refreshView] mag de bron aanraken; alle andere bevindingen vragen om
/// menselijke keuze en tonen alleen waar en wat.
enum RiskQualityRepair { none, refreshView, recalculateCalc }

/// Eén bevinding op één plek: welke tabel, welk record, welke regel —
/// genoeg om ernaartoe te springen in elke weergave van het bestand.
class RiskQualityFinding {
  final RiskQualitySeverity severity;
  final String code;

  /// 1-gebaseerd regelnummer in de bron van [table.blockStart] + rijindex.
  final int line;

  /// De `id=` van de gemarkeerde tabel (`hoofd`), indien bekend.
  final String? tableId;

  /// Het contract-ID van de betrokken record (`R-003`), indien een rij.
  final String? recordId;

  /// Wat afwijkt, in gebruikerstaal.
  final String message;

  /// Waarom dit ertoe doet — het gevolg als je het laat staan.
  final String consequence;

  final RiskQualityRepair repair;

  /// Bij [RiskQualityRepair.refreshView]: de weergave-tabel om te herbouwen.
  final OciMarkedTable? repairTable;

  const RiskQualityFinding({
    required this.severity,
    required this.code,
    required this.line,
    this.tableId,
    this.recordId,
    required this.message,
    required this.consequence,
    this.repair = RiskQualityRepair.none,
    this.repairTable,
  });
}

/// Alle bevindingen van één scan — een momentopname zoals [RiskDossier].
class RiskQualityReport {
  final List<RiskQualityFinding> findings;
  const RiskQualityReport(this.findings);

  bool get hasErrors =>
      findings.any((f) => f.severity == RiskQualitySeverity.error);
  bool get isClean => findings.isEmpty;

  List<RiskQualityFinding> get errors => [
    for (final f in findings)
      if (f.severity == RiskQualitySeverity.error) f,
  ];

  List<RiskQualityFinding> get warnings => [
    for (final f in findings)
      if (f.severity == RiskQualitySeverity.warning) f,
  ];
}

/// De scorekolommen die [RiskDossier] per methode kent, gesplitst in
/// bruto en netto — de netto-lijst voedt óók de "netto zonder
/// grondslag"-controle.
({List<String> bruto, List<String> netto}) _scoreKeys(RiskMethod method) =>
    switch (method) {
      RiskMethod.fmea => (
        bruto: const ['s_b', 'o_b', 'd_b'],
        netto: const ['s_n', 'o_n', 'd_n'],
      ),
      RiskMethod.likelihoodImpact => (
        bruto: const ['l_b', 'i_b'],
        netto: const ['l_n', 'i_n'],
      ),
      RiskMethod.bowtie => (bruto: const [], netto: const []),
    };

/// Regelnummer (1-based) van body-rij [rowIndex] in [table]:
/// markergebied + kop + scheiding zitten ervóór.
int _rowLine(OciMarkedTable table, int rowIndex) =>
    table.tableStart + 3 + rowIndex;

/// Draait de volledige controle over [source]. O(n) over de regels —
/// de scanner loopt het bestand één keer, de records één keer.
RiskQualityReport riskQualityFindings(String source) {
  final dossier = RiskDossier.read(source);
  final findings = <RiskQualityFinding>[];

  // --- ID-integriteit, over álle contracttabellen ----------------------
  for (final table in dossier.scan.tables) {
    if (!(table.marker?.versionSupported ?? false)) continue;
    if (table.kind == OciMarkerKinds.view) continue;
    final seen = <String, int>{};
    final rows = table.bodyRows;
    final idCol = table.cols.indexOf('id');
    for (var i = 0; i < rows.length; i++) {
      final id = (idCol >= 0 && idCol < rows[i].length ? rows[i][idCol] : '')
          .trim();
      if (id.isEmpty) {
        findings.add(
          RiskQualityFinding(
            severity: RiskQualitySeverity.error,
            code: 'missing-id',
            line: _rowLine(table, i),
            tableId: table.id,
            message: 'Rij ${i + 1} heeft geen ID.',
            consequence:
                'Zonder ID kan niets deze rij aanspreken — weergaven, '
                'maatregelen en de controle zelf slaan hem over.',
          ),
        );
        continue;
      }
      if (seen.containsKey(id)) {
        findings.add(
          RiskQualityFinding(
            severity: RiskQualitySeverity.error,
            code: 'duplicate-id',
            line: _rowLine(table, i),
            tableId: table.id,
            recordId: id,
            message:
                '"$id" komt twee keer voor '
                '(ook op regel ${seen[id]! + 1}).',
            consequence:
                'Verwijzingen naar "$id" zijn onzeker: welke rij is bedoeld, '
                'is een menselijke keuze.',
          ),
        );
      } else {
        seen[id] = i;
      }
    }
  }

  // --- Schaal en scores per risicoregister -----------------------------
  for (final table in dossier.riskTables) {
    final marker = table.marker!;
    final method = RiskMethod.parse(marker.attr('method') ?? '');
    if (method == null) continue;
    final scale = dossier.scaleFor(table);
    final scaleName = marker.attr('scale') ?? '';
    if (scale == null) {
      findings.add(
        RiskQualityFinding(
          severity: RiskQualitySeverity.error,
          code: 'scale-unknown',
          line: table.blockStart + 1,
          tableId: table.id,
          message:
              'De schaal "$scaleName" staat niet in dit bestand '
              'en is ook geen ingebouwde naam.',
          consequence:
              'Scores zijn niet te toetsen zolang de schaal '
              'ontbreekt.',
        ),
      );
    }
    final (bruto: brutoKeys, netto: nettoKeys) = _scoreKeys(method);
    final max = scale?.max ?? 0;
    for (var i = 0; i < table.bodyRows.length; i++) {
      final record = RiskRecord(table.contractRows[i]);
      final line = _rowLine(table, i);
      for (final key in [...brutoKeys, ...nettoKeys]) {
        final raw = record.cells[key]?.trim() ?? '';
        if (raw.isEmpty) continue; // onbeoordeeld is toegestaan
        final value = int.tryParse(raw);
        if (value == null) {
          findings.add(
            RiskQualityFinding(
              severity: RiskQualitySeverity.error,
              code: 'score-invalid',
              line: line,
              tableId: table.id,
              recordId: record.id.isEmpty ? null : record.id,
              message:
                  '"$raw" is geen getal voor ${ociContractHeaderName(key)}.',
              consequence:
                  'Een onleesbare score rekent als onbetrouwbaar cijfer, '
                  'niet als nul.',
            ),
          );
        } else if (max > 0 && (value < 1 || value > max)) {
          findings.add(
            RiskQualityFinding(
              severity: RiskQualitySeverity.error,
              code: 'score-out-of-range',
              line: line,
              tableId: table.id,
              recordId: record.id.isEmpty ? null : record.id,
              message:
                  'Score $value voor ${ociContractHeaderName(key)} '
                  'valt buiten de schaal 1–$max.',
              consequence:
                  'Buiten-schaal-scores verstoren RPN, kans×impact '
                  'en elke projectie die erop rekent.',
            ),
          );
        }
      }
      // Netto ingevuld zonder grondslag: geen getoetste/werkende
      // maatregel én geen netto_basis — dat is "laag zonder waarom".
      final hasNetto = nettoKeys.any(
        (key) => (record.cells[key]?.trim() ?? '').isNotEmpty,
      );
      if (hasNetto && record.nettoBasis.isEmpty) {
        final justified = record.measureIds.any(
          (id) => dossier.measureById(id)?.status?.justifiesNetto ?? false,
        );
        if (!justified) {
          findings.add(
            RiskQualityFinding(
              severity: RiskQualitySeverity.warning,
              code: 'netto-unjustified',
              line: line,
              tableId: table.id,
              recordId: record.id.isEmpty ? null : record.id,
              message:
                  'Netto-score zonder getoetste/werkende maatregel '
                  'of netto-grondslag.',
              consequence:
                  'Het residu-risico is niet onderbouwd — een '
                  'export suggereert dan meer zekerheid dan er is.',
            ),
          );
        }
      }
      // Verweesde maatregel-verwijzingen.
      for (final mId in record.measureIds) {
        if (dossier.measureById(mId) == null) {
          findings.add(
            RiskQualityFinding(
              severity: RiskQualitySeverity.warning,
              code: 'measure-orphan',
              line: line,
              tableId: table.id,
              recordId: record.id.isEmpty ? null : record.id,
              message: 'Verwijst naar maatregel "$mId", die niet bestaat.',
              consequence:
                  'De koppeling doet niets; de maatregel telt '
                  'niet mee voor de netto-grondslag.',
            ),
          );
        }
      }
    }
  }

  // --- Maatregelen: levenscyclus en terugverwijzingen -------------------
  for (final table in dossier.measureTables) {
    for (var i = 0; i < table.bodyRows.length; i++) {
      final measure = MeasureRecord(table.contractRows[i]);
      final line = _rowLine(table, i);
      final id = measure.id.isEmpty ? null : measure.id;
      for (final rId in measure.riskIds) {
        if (dossier.riskById(rId) == null) {
          findings.add(
            RiskQualityFinding(
              severity: RiskQualitySeverity.warning,
              code: 'risk-orphan',
              line: line,
              tableId: table.id,
              recordId: id,
              message: 'Verwijst naar risico "$rId", dat niet bestaat.',
              consequence:
                  'De maatregel lijkt een risico te dekken dat '
                  'er niet is.',
            ),
          );
        }
      }
      // Een getoetste/werkende maatregel zonder toetsdatum of bewijs is
      // belofte zonder bewijs (§3.4: die statussen dragen de netto-score).
      final status = measure.status;
      if (status != null && status.justifiesNetto) {
        if (measure.testDate.isEmpty) {
          findings.add(
            RiskQualityFinding(
              severity: RiskQualitySeverity.warning,
              code: 'measure-undated',
              line: line,
              tableId: table.id,
              recordId: id,
              message: 'Status "${status.token}" zonder toetsdatum.',
              consequence:
                  'Er is geen bewijs dat de maatregel werkt — '
                  'netto-scores die erop steunen zijn ongedekt.',
            ),
          );
        }
        final expiry = DateTime.tryParse(measure.expires);
        if (expiry != null && expiry.isBefore(DateTime.now())) {
          findings.add(
            RiskQualityFinding(
              severity: RiskQualitySeverity.warning,
              code: 'measure-expired',
              line: line,
              tableId: table.id,
              recordId: id,
              message: 'De geldigheid (${measure.expires}) is verlopen.',
              consequence:
                  'De maatregel kan vervallen zijn; netto-scores '
                  'die erop rusten vragen hertoetsing.',
            ),
          );
        }
      }
    }
  }

  // --- Bowtie: verweesde maatregel-koppelingen --------------------------
  for (final table in dossier.bowtieTables) {
    for (var i = 0; i < table.bodyRows.length; i++) {
      final element = BowtieElement(table.contractRows[i]);
      final mId = element.measure;
      if (mId.isNotEmpty && dossier.measureById(mId) == null) {
        findings.add(
          RiskQualityFinding(
            severity: RiskQualitySeverity.warning,
            code: 'measure-orphan',
            line: _rowLine(table, i),
            tableId: table.id,
            recordId: element.path.isEmpty ? null : element.path,
            message:
                'Bowtie-element "${element.element}" verwijst naar '
                'maatregel "$mId", die niet bestaat.',
            consequence: 'De barrière lijkt gedekt maar is dat niet.',
          ),
        );
      }
    }
  }

  // --- Afgeleide cellen (calc, §3.7) ------------------------------------
  for (final table in dossier.scan.tables) {
    if (!(table.marker?.versionSupported ?? false)) continue;
    final defs = ociCalcDefs(table);
    if (defs.isEmpty) continue;
    for (final def in defs) {
      if (def.col.isEmpty || !ociCalcExprParses(def.marker)) {
        findings.add(
          RiskQualityFinding(
            severity: RiskQualitySeverity.error,
            code: 'calc-invalid',
            line: table.blockStart + 1,
            tableId: table.id,
            message:
                'Formule op "${def.col.isEmpty ? '?' : def.col}" '
                'is niet te lezen: "${def.expr}".',
            consequence:
                'De afgeleide kolom toont "—" — de marker blijft bewaard '
                'maar rekent niet mee.',
          ),
        );
      }
    }
    final eval = evaluateOciTableCalc(table);
    if (eval.cycleSeen) {
      findings.add(
        RiskQualityFinding(
          severity: RiskQualitySeverity.error,
          code: 'calc-cycle',
          line: table.blockStart + 1,
          tableId: table.id,
          message: 'Een formule verwijst (indirect) naar zichzelf.',
          consequence:
              'De betrokken cellen zijn onbekend — de cyclus vergt een '
              'menselijke keuze over de bedoelde berekening.',
        ),
      );
    }
    var drift = 0;
    var firstDrift = '';
    for (var r = 0; r < eval.results.length; r++) {
      for (var d = 0; d < defs.length; d++) {
        final result = eval.results[r][d];
        final label = table.contractRows[r]['id']?.trim().isNotEmpty == true
            ? table.contractRows[r]['id']!.trim()
            : 'rij ${r + 1}';
        if (result.error != null && result.error != CalcErrors.cycle) {
          findings.add(
            RiskQualityFinding(
              severity: RiskQualitySeverity.error,
              code: result.error!,
              line: _rowLine(table, r),
              tableId: table.id,
              recordId: table.contractRows[r]['id']?.trim(),
              message:
                  'Berekening "${defs[d].col}" op $label mislukt '
                  '(${result.error == CalcErrors.divZero ? 'deling door nul' : 'overflow'}).',
              consequence: 'De cel toont "—" — geen 0, geen oud getal.',
            ),
          );
          continue;
        }
        if (result.error != null) continue; // cyclus al gemeld
        // Drift: de opgeslagen cel ≠ de herberekende waarde. De mens
        // beslist — de reparatie schrijft de uitkomst, niet het oordeel.
        final stored = table.cell(r, defs[d].col);
        final computed = formatCalcValue(result.value);
        if (stored.trim() != computed) {
          drift++;
          firstDrift = firstDrift.isEmpty
              ? 'rij ${r + 1}: "$stored" → "$computed"'
              : firstDrift;
        }
      }
    }
    if (drift > 0) {
      findings.add(
        RiskQualityFinding(
          severity: RiskQualitySeverity.warning,
          code: 'calc-drift',
          line: table.blockStart + 1,
          tableId: table.id,
          message:
              'De opgeslagen afgeleide waarden lopen achter '
              '($firstDrift${drift > 1 ? ', +${drift - 1} meer' : ''}).',
          consequence:
              'De tabel toont niet wat de formule nu oplevert — '
              'herberekenen schrijft de uitkomst bij, nooit de invoer.',
          repair: RiskQualityRepair.recalculateCalc,
          repairTable: table,
        ),
      );
    }
  }

  // --- Gekoppelde weergaven --------------------------------------------
  for (final view in dossier.viewTables) {
    final check = checkOciView(source, view);
    final sourceId = view.marker?.attr('source') ?? '';
    if (check.sourceMissing) {
      findings.add(
        RiskQualityFinding(
          severity: RiskQualitySeverity.error,
          code: 'view-source-missing',
          line: view.blockStart + 1,
          tableId: view.id,
          message:
              'De weergave noemt bron "$sourceId", '
              'die niet in dit bestand staat.',
          consequence:
              'De afschrijving is onherstelbaar zonder bron — '
              'loskoppelen of verwijderen is de menselijke keuze.',
        ),
      );
    } else if (check.mismatches.isNotEmpty) {
      findings.add(
        RiskQualityFinding(
          severity: RiskQualitySeverity.warning,
          code: 'view-mismatch',
          line: view.blockStart + 1,
          tableId: view.id,
          message:
              'De weergave wijkt af van de bron: '
              '${check.mismatches.first}'
              '${check.mismatches.length > 1 ? ' (+${check.mismatches.length - 1} meer)' : ''}.',
          consequence:
              'De tabel toont wat de bron niet meer zegt — '
              'verversen herbouwt hem uit de bron.',
          repair: RiskQualityRepair.refreshView,
          repairTable: view,
        ),
      );
    }
  }

  findings.sort((a, b) => a.line - b.line);
  return RiskQualityReport(findings);
}

/// Leesbare naam van een contractkolom voor meldingen.
String ociContractHeaderName(String key) => key;
