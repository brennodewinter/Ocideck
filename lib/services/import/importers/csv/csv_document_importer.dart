// CSV → Markdown converter voor de documentimport.
//
// Headless: geen Flutter, geen IO — draait op bytes, dus ook op web. Leest
// met [parseCsvRows], dezelfde scanner als de grafiekdata en het klembord,
// en legt het resultaat als één anonieme tabel neer (CSV kent geen bladen).
//
// Twee bronkeuzes die een CSV niet zelf maakt: de tekencodering en het
// scheidingsteken. De codering is UTF-8 met een latin-1-terugval — een
// cp1252-export uit een Nederlands Excel zou anders elke diakriet verminken.
// Het scheidingsteken wordt geroken tussen `;`, `,` en tab: de kandidaat die
// het breedste én meest regelmatige rooster oplevert wint, en geen enkele
// kandidaat betekent dat de regels als één kolom overgaan.

import 'dart:convert';

import '../../models/document_conversion.dart';
import '../../utils/import_budget.dart';
import '../../utils/spreadsheet_markdown.dart';
import '../../../../utils/csv.dart';

/// Zet de bytes van een `.csv` om in Markdown. [title] is de naam die boven
/// het document komt — de aanroeper levert hem uit de bestandsnaam.
DocumentConversion convertCsvDetailed(
  List<int> bytes, {
  String title = '',
  ImportBudget budget = ImportBudget.standard,
}) {
  if (bytes.length > budget.maxSourceBytes) {
    throw ImportBudgetException('${budget.maxSourceBytes} bytes');
  }
  return DocumentConversion(
    markdown: spreadsheetToMarkdown(title, [
      (name: '', rows: _rows(_decodeText(bytes), budget)),
    ], budget: budget),
  );
}

/// De tekst van de sheet: UTF-8 als het kan (met zonder BOM), anders latin-1.
/// Een `.csv` draagt zijn codering nergens in zichzelf, dus dit is gokken —
/// maar latin-1 faalt nooit, en een misgok blijft zichtbaar in plaats van
/// stil weg te vallen.
String _decodeText(List<int> bytes) {
  var slice = bytes;
  if (slice.length >= 3 &&
      slice[0] == 0xEF &&
      slice[1] == 0xBB &&
      slice[2] == 0xBF) {
    slice = slice.sublist(3);
  }
  try {
    return utf8.decode(slice);
  } on FormatException {
    return latin1.decode(slice);
  }
}

List<List<String>> _rows(String text, ImportBudget budget) {
  // Een bestand heet `.csv` en mag gegolfd zijn — regels met wisselende
  // kolomaantallen zijn legaal. Dus niet de klembordregel ("elke rij even
  // breed"), maar: het scheidingsteken dat de meeste cellen oplevert terwijl
  // de eerste rij er minstens twee heeft, wint. Gegolfde rijen vult de
  // Markdown-tabel zelf aan tot rechthoek.
  List<List<String>>? best;
  var bestCells = 0;
  ImportBudgetException? rejected;
  void checkBudget(int rows, int columns, int cells) {
    if (rows > budget.maxSheetRows) {
      throw ImportBudgetException('${budget.maxSheetRows} rijen');
    }
    if (columns > budget.maxSheetCols) {
      throw ImportBudgetException('${budget.maxSheetCols} kolommen');
    }
    if (cells > budget.maxSheetCells) {
      throw ImportBudgetException('${budget.maxSheetCells} tabelcellen');
    }
  }

  for (final delimiter in const [';', ',', '\t']) {
    late final List<List<String>> rows;
    try {
      rows = parseCsvRows(
        text,
        delimiter: delimiter,
        trimUnquoted: true,
        checkBudget: checkBudget,
      );
    } on ImportBudgetException catch (e) {
      rejected = e;
      continue;
    }
    if (rows.isEmpty || rows.first.length < 2) continue;
    final cells = rows.fold<int>(0, (sum, r) => sum + r.length);
    if (cells > bestCells) {
      best = rows;
      bestCells = cells;
    }
  }
  if (best != null) return best;
  if (rejected != null) throw rejected;
  // Geen scheidingsteken gevonden: één kolom, elke regel een cel.
  final normalized = text.replaceAll('\r\n', '\n');
  if ('\n'.allMatches(normalized).length + 1 > budget.maxSheetRows) {
    throw ImportBudgetException('${budget.maxSheetRows} rijen');
  }
  return [
    for (final line in normalized.split('\n'))
      if (line.trim().isNotEmpty) [line.trim()],
  ];
}
