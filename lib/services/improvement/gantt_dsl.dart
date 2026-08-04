// Gantt-slidetype: tabel → Mermaid gantt-DSL converter (GANTT_SLIDETYPE §3.1).
//
// Pure Dart, geen Flutter-imports — testbaar in isolatie, zoals flow_slide.dart
// en tree_slide.dart. De tabel is de bron van waarheid (Slide.tableRows); de DSL
// is afgeleid en wordt nooit opgeslagen, net als flow's roll-up strip.
library;

/// De vijf vaste kolommen van een gantt-tabel, op volgorde.
const ganttColumnCount = 5;

/// De vaste kop die een nieuwe gantt-dia meekrijgt (GANTT_SLIDETYPE §2.2).
/// Nederlands — de opslagtaal van de `.md`, zoals checklist- en scope-koppen.
const ganttStarterRows = [
  ['Taak', 'Start', 'Duur', 'Voortgang', 'Afhankelijk van'],
  ['', '', '', '', ''],
  ['', '', '', '', ''],
];

/// Maximaal aantal taken op één gantt-dia. Een dia is een samenvatting, geen
/// planbestand — meer dan dit leest niet meer als één overzicht. De converter
/// kapt af; de editor waarschuwt. `ponytail:` ceiling: 30, upgrade door een
/// pagineringsstrategie zoals bullets-rich-text.
const ganttMaxTasks = 30;

final _reDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _reDuration = RegExp(r'^\s*(\d+)\s*([dwh])\s*$', caseSensitive: false);

/// Zet de tabelrijen van een gantt-dia om in Mermaid gantt-DSL.
///
/// [rows] zijn de tabelrijen zonder de koprij. [scale] is de as-granulariteit:
/// `'auto'` (default), `'day'`, `'week'` of `'month'`. [sections] laat een rij
/// wiens Taak-cel met `## ` begint uitpakken als een Mermaid `section`-kop.
String ganttTableToMermaid({
  required List<List<String>> rows,
  String scale = 'auto',
  bool sections = false,
}) {
  // Eerste pas: id's toewijzen (t1, t2, …) en naam→id map bouwen. Dubbele
  // taaknamen krijgen een suffix, zodat afhankelijkheidsverwijzingen eenduidig
  // blijven — al is een dubbele naam in de praktijk al een datafout.
  final nameToId = <String, String>{};
  final ids = <int, String>{};
  final nameCount = <String, int>{};
  var nextId = 1;
  for (var i = 0; i < rows.length; i++) {
    final name = _cell(rows[i], 0).trim();
    if (name.isEmpty) continue;
    if (sections && name.startsWith('## ')) continue;
    final base = name.startsWith('Milestone: ')
        ? name.substring('Milestone: '.length).trim()
        : name;
    final n = nameCount[base] = (nameCount[base] ?? 0) + 1;
    final id = n == 1 ? 't$nextId' : 't${nextId}_$n';
    nextId++;
    ids[i] = id;
    if (n == 1) nameToId[base] = id;
  }

  // As-formaat: dag → %Y-%m-%d, week → %Y-%m-%d (Mermaid heeft geen week-as),
  // maand → %Y-%m. Auto: kies op basis van de spanne tussen vroegste start en
  // laatste einddatum.
  final axisFormat = scale == 'auto'
      ? _autoAxisFormat(rows, ids)
      : switch (scale) {
          'day' || 'week' => '%Y-%m-%d',
          'month' => '%Y-%m',
          _ => '%Y-%m-%d',
        };

  final buf = StringBuffer('gantt\n')
    ..writeln('    dateFormat YYYY-MM-DD')
    ..writeln('    axisFormat $axisFormat');

  for (var i = 0; i < rows.length; i++) {
    final rawName = _cell(rows[i], 0).trim();
    if (rawName.isEmpty) continue;

    // Sectiekop: een rij wiens Taak-cel met `## ` begint, alleen onder de
    // sections-vlag. Zonder de vlag is het een gewone taaknaam.
    if (sections && rawName.startsWith('## ')) {
      buf.writeln('    section ${rawName.substring(3).trim()}');
      continue;
    }

    final id = ids[i];
    if (id == null) continue; // lege naam overgeslagen in de eerste pas

    final isMilestone = rawName.startsWith('Milestone: ');
    final name = isMilestone
        ? rawName.substring('Milestone: '.length).trim()
        : rawName;

    final start = _cell(rows[i], 1).trim();
    final duration = _cell(rows[i], 2).trim();
    final status = _cell(rows[i], 3).trim().toLowerCase();
    final deps = _cell(rows[i], 4).trim();

    // Start: een geldige ISO-datum, of afgeleid uit de afhankelijkheid (`after
    // <id>`). Heeft de taak een afhankelijkheid, dan wint `after` — de start-
    // datum in de tabel is dan een handige aanwijzing die Mermaid negeert. Is
    // er geen afhankelijkheid en geen geldige datum, dan valt de taak uit (de
    // tabel is de waarheid; een slechte datum is een datafout, geen crash).
    final afterRefs = _resolveDeps(deps, nameToId);
    final startSpec = afterRefs.isNotEmpty
        ? afterRefs.join(', ')
        : (_reDate.hasMatch(start) ? start : null);

    if (startSpec == null) continue;
    if (!isMilestone && !_reDuration.hasMatch(duration)) continue;

    final statusToken = switch (status) {
      'done' || 'active' || 'crit' => ' :$status, ',
      _ => ' :',
    };

    if (isMilestone) {
      buf.writeln('    $name :milestone, $id, $startSpec, 0d');
    } else {
      buf.writeln('    $name$statusToken$id, $startSpec, $duration');
    }
  }

  return buf.toString();
}

/// Lost de komma-gescheiden taaknamen in [deps] op naar `after <id>`-verwijzingen.
/// Een naam die niet in [nameToId] staat wordt stil gedropt — de tabel is de
/// waarheid; een losse verwijzing is een datafout, geen renderfout.
List<String> _resolveDeps(String deps, Map<String, String> nameToId) {
  if (deps.isEmpty) return const [];
  final refs = <String>[];
  for (final raw in deps.split(',')) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final id = nameToId[name];
    if (id != null) refs.add('after $id');
  }
  return refs;
}

/// Kiest het as-formaat op basis van de spanne tussen vroegste start en laatste
/// einddatum. < 14 dagen → dag, < 90 → week (toont %Y-%m-%d), anders maand.
String _autoAxisFormat(List<List<String>> rows, Map<int, String> ids) {
  DateTime? earliest;
  DateTime? latest;
  for (var i = 0; i < rows.length; i++) {
    if (ids[i] == null) continue;
    final start = _cell(rows[i], 1).trim();
    if (_reDate.hasMatch(start)) {
      final d = DateTime.tryParse(start);
      if (d != null) {
        earliest = earliest == null || d.isBefore(earliest) ? d : earliest;
        latest = latest == null || d.isAfter(latest) ? d : latest;
      }
    }
  }
  if (earliest == null || latest == null) return '%Y-%m-%d';
  final days = latest.difference(earliest).inDays;
  if (days < 14) return '%Y-%m-%d';
  if (days < 90) return '%Y-%m-%d';
  return '%Y-%m';
}

String _cell(List<String> row, int col) => col < row.length ? row[col] : '';
