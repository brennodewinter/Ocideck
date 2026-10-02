// XLSX (OOXML Spreadsheet) → Markdown converter voor de documentimport.
//
// Leest een `.xlsx` (ECMA-376, zip met XML) en legt elk werkblad neer als een
// kop plus GFM-tabel. Headless: geen Flutter, geen IO — draait op bytes, dus
// ook op web.
//
// Wat er wel en niet meekomt is bewust beperkt tot wat een Markdown-tabel kan
// dragen: de *waarde* van elke cel zoals Excel die zou tonen. Formules geven
// hun opgeslagen resultaat (`<v>`), datums hun kalenderdatum via
// `xl/styles.xml`, booleans TRUE/FALSE. Opmaak, samengevoegde cellen,
// draaitabellen, afbeeldingen en grafieken hebben geen Markdown-tegenhanger;
// die laatste twee tellen mee in `notImported` in plaats van stil te vallen.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/document_conversion.dart';
import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../../utils/spreadsheet_markdown.dart';
import '../../utils/xml_utils.dart';
import '../odp/odp_context.dart'
    show childLocal, childrenLocal, descendantsLocal;

/// Zet de bytes van een `.xlsx` om in Markdown. [title] komt boven het
/// document — de aanroeper levert hem uit de bestandsnaam.
///
/// Gooit [ImportBudgetException] bij overschrijding van het budget en
/// [FormatException] bij een beschadigd of incompleet archief.
DocumentConversion convertXlsxDetailed(
  List<int> bytes, {
  String title = '',
  ImportBudget budget = ImportBudget.standard,
}) {
  final ctx = _XlsxContext(safeDecodeZip(bytes, budget: budget), budget);

  final workbook = ctx.readXml('xl/workbook.xml');
  if (workbook == null) {
    throw const FormatException(
      'xl/workbook.xml ontbreekt — geen geldig .xlsx',
    );
  }
  final rels = ctx.workbookRelationships();
  final shared = ctx.sharedStrings();
  final dateStyle = ctx.dateStyles();

  final sheets = <SheetGrid>[];
  for (final sheet in descendantsLocal(workbook, 'sheet')) {
    final name = _attr(sheet, 'name') ?? '';
    final target = rels[_attr(sheet, 'id')];
    if (target == null) continue;
    final doc = ctx.readXml(_normalizeTarget(target));
    if (doc == null) continue;
    sheets.add((name: name, rows: _sheetRows(doc, shared, dateStyle)));
  }

  return DocumentConversion(
    markdown: spreadsheetToMarkdown(title, sheets),
    notImported: ctx.notImported(),
  );
}

/// Het archief met zijn deel- en parse-cache, zoals de zusterimporteurs die
/// ook hebben. Houdt bovendien de drie tabellen bij die losse werkblad-XML
/// betekenis geven: relatie-id's, de gedeelde strings en de datumstijlen.
class _XlsxContext {
  _XlsxContext(this.archive, this.budget);

  final Archive archive;
  final ImportBudget budget;
  final _parsed = <String, XmlDocument?>{};
  Map<String, String>? _relationships;
  List<String>? _shared;
  List<_DateStyle>? _dateStyles;

  String? readPart(String path) {
    for (final f in archive) {
      if (f.name == path) return utf8.decode(f.content as List<int>);
    }
    return null;
  }

  XmlDocument? readXml(String path) => _parsed.putIfAbsent(path, () {
    final src = readPart(path);
    return src == null ? null : parseXmlSafe(src, budget: budget);
  });

  /// `r:id` → archiefpad uit `xl/_rels/workbook.xml.rels`.
  Map<String, String> workbookRelationships() {
    if (_relationships != null) return _relationships!;
    final rels = <String, String>{};
    final doc = readXml('xl/_rels/workbook.xml.rels');
    if (doc != null) {
      for (final rel in descendantsLocal(doc, 'Relationship')) {
        final id = _attr(rel, 'Id');
        final target = _attr(rel, 'Target');
        if (id != null && target != null) rels[id] = target;
      }
    }
    return _relationships = rels;
  }

  /// De gedeelde stringtabel: elke `<si>` is één opgesomde celtekst, die met
  /// rijke runs als meerdere `<t>`-fragmenten kan staan.
  List<String> sharedStrings() {
    if (_shared != null) return _shared!;
    final shared = <String>[];
    final doc = readXml('xl/sharedStrings.xml');
    if (doc != null) {
      for (final si in descendantsLocal(doc, 'si')) {
        shared.add(descendantsLocal(si, 't').map((t) => t.innerText).join());
      }
    }
    return _shared = shared;
  }

  /// Per `xf`-index uit `cellXfs`: is de notatie een datum/tijd, en heeft hij
  /// een tijdcomponent? Een datum staat in de sheet als serienummer; zonder
  /// deze tabel zou de gebruiker `45292` zien waar 1-1-2024 stond.
  List<_DateStyle> dateStyles() {
    if (_dateStyles != null) return _dateStyles!;
    final styles = <_DateStyle>[];
    final doc = readXml('xl/styles.xml');
    if (doc != null) {
      final custom = <int, String>{};
      for (final fmt in descendantsLocal(doc, 'numFmt')) {
        final id = int.tryParse(_attr(fmt, 'numFmtId') ?? '');
        final code = _attr(fmt, 'formatCode');
        if (id != null && code != null) custom[id] = code;
      }
      final cellXfs = descendantsLocal(doc, 'cellXfs').firstOrNull;
      if (cellXfs != null) {
        for (final xf in childrenLocal(cellXfs, 'xf')) {
          final id = int.tryParse(_attr(xf, 'numFmtId') ?? '') ?? 0;
          styles.add(_dateStyleOf(id, custom[id]));
        }
      }
    }
    return _dateStyles = styles;
  }

  /// Afbeeldingen en grafieken zijn geen celinhoud — ze tellen als verlies.
  List<String> notImported() {
    final kinds = <String>[];
    for (final f in archive) {
      if (f.name.startsWith('xl/media/')) kinds.add('afbeelding');
      if (f.name.startsWith('xl/charts/') && f.name.endsWith('.xml')) {
        kinds.add('object');
      }
    }
    return kinds;
  }
}

/// De rijen van één werkblad als kolommatig rooster.
///
/// Het `r`-attribuut van een cel (`"BC12"`) bepaalt zijn kolom — cellen zonder
/// inhoud staan simpelweg niet in het bestand, dus posities tellen is niet
/// genoeg om gaten goed te leggen. Rijnummers worden bewust géén gat waard:
/// een blad met alleen rij 1 en rij 40000 is een tabel van twee rijen, niet
//  van veertigduizend.
List<List<String>> _sheetRows(
  XmlDocument sheet,
  List<String> shared,
  List<_DateStyle> dateStyles,
) {
  final data = descendantsLocal(sheet, 'sheetData').firstOrNull;
  if (data == null) return const [];

  final rows = <List<String>>[];
  var maxCols = 0;
  for (final row in childrenLocal(data, 'row')) {
    final cells = <String>[];
    var nextCol = 0;
    for (final c in childrenLocal(row, 'c')) {
      final ref = _attr(c, 'r');
      final col = ref == null ? nextCol : _columnIndex(ref);
      while (cells.length < col) {
        cells.add('');
      }
      cells.add(_cellText(c, shared, dateStyles));
      nextCol = col + 1;
    }
    if (cells.length > maxCols) maxCols = cells.length;
    rows.add(cells);
  }
  // Rechthoek maken: rijen eindigen in de bron bij hun laatste niet-lege cel.
  for (final row in rows) {
    while (row.length < maxCols) {
      row.add('');
    }
  }
  return rows;
}

/// `"BC"` → 54: kolomletter naar nul-gebaseerde index.
int _columnIndex(String cellRef) {
  var col = 0;
  for (final unit in cellRef.codeUnits) {
    if (unit < 0x41 || unit > 0x5A) break; // stopt bij het eerste cijfer
    col = col * 26 + (unit - 0x41 + 1);
  }
  return col - 1;
}

/// De zichtbare tekst van één cel: de opgeslagen waarde, via het type (`t`)
/// en de datumstijl (`s`) op de juiste schaal gezet.
String _cellText(
  XmlElement cell,
  List<String> shared,
  List<_DateStyle> dateStyles,
) {
  final v = childLocal(cell, 'v')?.innerText ?? '';
  switch (_attr(cell, 't')) {
    case 's':
      return shared.elementAtOrNull(int.tryParse(v) ?? -1) ?? '';
    case 'inlineStr':
      return descendantsLocal(cell, 't').map((t) => t.innerText).join();
    case 'b':
      return v == '1' ? 'TRUE' : 'FALSE';
    case 'e':
    case 'str':
    case 'd':
      return v.trim();
    default:
      final styleIndex = int.tryParse(_attr(cell, 's') ?? '');
      final style = styleIndex == null || styleIndex >= dateStyles.length
          ? null
          : dateStyles[styleIndex];
      if (style != null && style.isDate) {
        final serial = double.tryParse(v);
        if (serial != null) return _serialToText(serial, style.hasTime);
      }
      return v.trim();
  }
}

/// Serienummer → `yyyy-mm-dd`, met ` hh:mm` als de notatie tijd kent en de
/// fractie niet nul is. Epoche 1899-12-30: zo valt serienummer 1 op
/// 1900-01-01 én blijft Excel's denkbeeldige 29-02-1900 buiten schot voor
/// elke datum ná die dag — wie die wél importeert, ziet één dag verschil.
String _serialToText(double serial, bool withTime) {
  final instant = DateTime.utc(
    1899,
    12,
    30,
  ).add(Duration(microseconds: (serial * 86400 * 1000000).round()));
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      '${instant.year.toString().padLeft(4, '0')}-'
      '${two(instant.month)}-${two(instant.day)}';
  if (!withTime || (instant.hour == 0 && instant.minute == 0)) return date;
  return '$date ${two(instant.hour)}:${two(instant.minute)}';
}

class _DateStyle {
  const _DateStyle(this.isDate, this.hasTime);
  final bool isDate;
  final bool hasTime;
}

/// De ingebouwde datum- en tijdnotatie-id's uit ECMA-376 (14–22, 27–36,
/// 45–47 en 50–58). Alles daarbuiten is getal, munteenheid of tekst.
bool _isBuiltinDateFormat(int numFmtId) =>
    (numFmtId >= 14 && numFmtId <= 22) ||
    (numFmtId >= 27 && numFmtId <= 36) ||
    (numFmtId >= 45 && numFmtId <= 47) ||
    (numFmtId >= 50 && numFmtId <= 58);

/// Of een notatie een datum/tijd voorstelt. Voor een eigen `formatCode` wordt
/// eerst de ballast gestript (`[Rood]`-kleuren, `"m"`-letterlijke teksten,
/// `\`-ontsnappingen); wat overblijft aan `y`/`d`/`h`/`s`/`m` beslist. Een `m`
/// alleen is tweeslachtig (maand én minuut), dus telt mee zodra er ook een
/// `y` of `d` is.
_DateStyle _dateStyleOf(int numFmtId, String? customCode) {
  if (customCode == null) {
    final date = _isBuiltinDateFormat(numFmtId);
    return _DateStyle(
      date,
      date &&
          (numFmtId >= 18 && numFmtId <= 22 ||
              numFmtId >= 45 && numFmtId <= 47),
    );
  }
  final cleaned = customCode
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'"[^"]*"'), '')
      .replaceAll(RegExp(r'\\.'), '')
      .toLowerCase();
  final hasDate = cleaned.contains('y') || cleaned.contains('d');
  final hasTime = cleaned.contains('h') || cleaned.contains('s');
  // Een `m` is tweeslachtig — maand én minuut — maar telt in beide gevallen
  // als tijdsaanduiding; alleen een `m` als letterlijke tekst ( `"m"` ) is
  // hierboven al met de quotes weggestript.
  return _DateStyle(hasDate || hasTime || cleaned.contains('m'), hasTime);
}

/// `worksheets/sheet1.xml` → `xl/worksheets/sheet1.xml`; een absoluut target
/// (`/xl/…`) blijft zoals hij is.
String _normalizeTarget(String target) {
  if (target.startsWith('/')) return target.substring(1);
  if (target.startsWith('xl/')) return target;
  return 'xl/$target';
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
