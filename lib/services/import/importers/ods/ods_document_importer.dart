// ODS (OpenDocument Spreadsheet) → Markdown converter voor de documentimport.
//
// Leest een `.ods` (ISO 26300, zip met `content.xml`) en legt elk `table:table`
// neer als een kop plus GFM-tabel. Headless: geen Flutter, geen IO — draait op
// bytes, dus ook op web. Deelt het ODF-XML-model met de ODT- en ODP-importeurs
// en gebruikt daarom dezelfde namespace-agnostische helpers.
//
// De celtekst komt uit `text:p` — dat is de *opgemaakte* waarde zoals Calc die
// toont ("1.234,56", "15-01-2024"), wat de datum- en getalnotatie van deze
// kant gratis maakt. Alleen als er geen tekst staat vallen `office:value`- en
// `office:date-value`-attributen terug.
//
// `table:number-rows-repeated` en `-columns-repeated` worden geëxpandeerd maar
// geclampt op het budget: een leeg Calc-blad declareert zijn miljoen rijen als
// één herhaalde knoop, en dat is compressie, geen inhoud.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/document_conversion.dart';
import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../../utils/spreadsheet_markdown.dart';
import '../../utils/xml_utils.dart';
import '../odp/odp_context.dart' show childrenLocal, descendantsLocal;

/// Zet de bytes van een `.ods` om in Markdown. [title] komt boven het
/// document — de aanroeper levert hem uit de bestandsnaam.
///
/// Gooit [ImportBudgetException] bij overschrijding van het budget en
/// [FormatException] bij een beschadigd of incompleet archief.
DocumentConversion convertOdsDetailed(
  List<int> bytes, {
  String title = '',
  ImportBudget budget = ImportBudget.standard,
}) {
  final archive = safeDecodeZip(bytes, budget: budget);
  final content = _readXml(archive, 'content.xml', budget);
  if (content == null) {
    throw const FormatException('content.xml ontbreekt — geen geldig .ods');
  }

  final spreadsheet = descendantsLocal(content, 'spreadsheet').firstOrNull;
  if (spreadsheet == null) {
    throw const FormatException(
      'Geen <office:spreadsheet> gevonden — geen geldig .ods',
    );
  }

  var truncated = false;
  final sheets = <SheetGrid>[];
  for (final table in childrenLocal(spreadsheet, 'table')) {
    final rows = _tableRows(table, budget, () => truncated = true);
    sheets.add((name: _attr(table, 'name') ?? '', rows: rows));
  }

  final notImported = <String>[
    // Een afgekapte herhaling met inhoud is verlies, geen opmaak.
    if (truncated) 'object',
    for (final _ in descendantsLocal(content, 'image')) 'afbeelding',
    for (final _ in descendantsLocal(content, 'chart')) 'object',
  ];
  return DocumentConversion(
    markdown: spreadsheetToMarkdown(title, sheets),
    notImported: notImported,
  );
}

/// De rijen van één `table:table`. Loopt de directe kinderen en de ODF-
/// groepeerders (`table-header-rows`, `table-rows`, `table-row-group`) zodat
/// een geneste tabel in een cel níet als rij van het blad meetelt.
List<List<String>> _tableRows(
  XmlElement table,
  ImportBudget budget,
  void Function() onTruncate,
) {
  final rows = <List<String>>[];
  var maxCols = 0;

  void visit(XmlElement parent) {
    for (final child in parent.children.whereType<XmlElement>()) {
      switch (child.name.local) {
        case 'table-header-rows':
        case 'table-rows':
        case 'table-row-group':
          visit(child);
        case 'table-row':
          final wanted = _repeatOf(child, 'number-rows-repeated');
          final cells = _rowCells(child, budget, onTruncate);
          if (cells.length > maxCols) maxCols = cells.length;
          final hasContent = cells.any((c) => c.isNotEmpty);
          var taken = 0;
          while (taken < wanted && rows.length < budget.maxSheetRows) {
            rows.add(List.of(cells));
            taken++;
          }
          if (taken < wanted && hasContent) onTruncate();
        default:
          break;
      }
    }
  }

  visit(table);
  for (final row in rows) {
    while (row.length < maxCols) {
      row.add('');
    }
  }
  return rows;
}

/// De cellen van één rij, met `number-columns-repeated` geëxpandeerd tot de
/// kolomgrens. `covered-table-cell` is de schaduw van een samengevoegde cel —
/// een lege plek, net als in de tabel. Weggevallen herhalingen tellen alleen
/// als verlies wanneer ze inhoud droegen; een miljoen lege cellen afkappen is
/// geen verlies maar ademruimte.
List<String> _rowCells(
  XmlElement row,
  ImportBudget budget,
  void Function() onTruncate,
) {
  final cells = <String>[];
  var overBudget = false;
  for (final tc in row.children.whereType<XmlElement>()) {
    final local = tc.name.local;
    if (local != 'table-cell' && local != 'covered-table-cell') continue;
    final text = local == 'covered-table-cell' ? '' : _cellText(tc);
    final wanted = _repeatOf(tc, 'number-columns-repeated');
    final remaining = budget.maxSheetCols - cells.length;
    final taken = wanted > remaining ? remaining : wanted;
    if (taken < wanted && text.isNotEmpty) overBudget = true;
    for (var i = 0; i < taken; i++) {
      cells.add(text);
    }
  }
  if (overBudget) onTruncate();
  return cells;
}

/// De `number-…-repeated` van [el], of 1 als die ontbreekt.
int _repeatOf(XmlElement el, String attr) {
  return int.tryParse(_attr(el, attr) ?? '') ?? 1;
}

/// De getoonde tekst van een cel: de `text:p`-inhoud (al geformatteerd), met
/// de `office:value`-familie als terugval voor cellen zonder tekst.
String _cellText(XmlElement cell) {
  final parts = <String>[];
  for (final p in descendantsLocal(cell, 'p')) {
    final t = p.innerText.trim();
    if (t.isNotEmpty) parts.add(t);
  }
  if (parts.isNotEmpty) return parts.join(' <br> ');
  return _attr(cell, 'date-value')?.replaceFirst(RegExp(r'T.*$'), '') ??
      _attr(cell, 'time-value') ??
      _attr(cell, 'boolean-value') ??
      _attr(cell, 'value') ??
      '';
}

XmlDocument? _readXml(Archive archive, String name, ImportBudget budget) {
  for (final f in archive) {
    if (f.name == name) {
      return parseXmlSafe(utf8.decode(f.content as List<int>), budget: budget);
    }
  }
  return null;
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
