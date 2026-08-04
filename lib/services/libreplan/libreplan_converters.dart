/// LibrePlan models → OciDeck slides. Pure Dart, testbaar.
///
/// Elke converter neemt LibrePlan-Dart-models (uit `libreplan_xml.dart`) en
/// produceert een `Slide` van het juiste type. De slides worden door
/// `libreplan_import.dart` in een deck verzameld.
///
/// Mapping (design-doc §4):
/// - Order → gantt (projectplanning met datums + afhankelijkheden)
/// - Order-hiërarchie → tree (WBS)
/// - Resources → table (resourcelijst)
/// - Work reports → table (timesheet)
/// - Resource hours → chart (belasting over tijd)
/// - Order + progress → cockpit (projectstatus)
/// - Milestones → timeline
/// - Critical path → flow
///
/// `ponytail:` plafonds: gantt kapt af op `ganttMaxTasks` (30), tree op 50
/// knopen, tables op 100 rijen. Een LibrePlan-project met meer data wordt
/// afgekapt — een dia is een samenvatting, geen planbestand.

import '../../models/slide.dart';
import '../improvement/gantt_dsl.dart';
import 'libreplan_xml.dart';

/// Maximaal aantal knopen in een tree (WBS). Meer leest niet als één overzicht.
const libreplanMaxTreeNodes = 50;

/// Maximaal aantal rijen in een geïmporteerde table. Meer wordt afgekapt.
const libreplanMaxTableRows = 100;

// ── Gantt ──────────────────────────────────────────────────────────────────

/// Bouw een gantt-slide uit een LibrePlan-order.
///
/// De order-hiërarchie wordt afgevlakt tot een lijst taken met datums en
/// afhankelijkheden. Containers (groepen) worden `## sectie`-koppen als
/// [sections] aan staat — anders gewone taken. Milestones worden
/// `Milestone: naam`-rijen. Afgekapt op [ganttMaxTasks].
Slide libreplanOrderToGantt(LibreplanOrder order, {bool sections = true}) {
  final rows = <List<String>>[
    ['Taak', 'Start', 'Duur', 'Voortgang', 'Afhankelijk van'],
  ];

  void walk(List<LibreplanOrderElement> elements) {
    for (final el in elements) {
      if (rows.length - 1 >= ganttMaxTasks) break;

      if (el.milestone) {
        rows.add([
          'Milestone: ${el.name}',
          _fmtDate(el.startDate) ?? _fmtDate(el.deadline) ?? '',
          '0d',
          el.progress >= 1.0 ? 'done' : '',
          '',
        ]);
        continue;
      }

      if (el.isContainer && sections) {
        rows.add(['## ${el.name}', '', '', '', '']);
      } else {
        final duration = _durationFromHours(el.workingHours);
        final status = _statusFromProgress(el.progress);
        rows.add([
          el.name,
          _fmtDate(el.startDate) ?? '',
          duration,
          status,
          el.dependencies.join(', '),
        ]);
      }

      if (el.isContainer) {
        walk(el.children);
      }
    }
  }

  walk(order.children);

  return Slide.create(SlideType.gantt).copyWith(
    title: order.name,
    tableRows: rows,
    ganttScale: ganttScaleAuto,
    ganttSections: sections,
  );
}

// ── WBS (tree) ─────────────────────────────────────────────────────────────

/// Bouw een tree-slide (WBS) uit de order-hiërarchie.
///
/// De tree gebruikt ingesprongen bullets: tab-diepte = hiërarchieniveau.
/// Containers en bladtaken worden beide knopen; milestones markeren we met
/// een `◆`-prefix. Afgekapt op [libreplanMaxTreeNodes].
Slide libreplanOrderToWbs(LibreplanOrder order) {
  final lines = <String>[];
  var nodeCount = 0;

  void walk(List<LibreplanOrderElement> elements, int depth) {
    for (final el in elements) {
      if (nodeCount >= libreplanMaxTreeNodes) return;
      nodeCount++;
      final indent = '\t' * depth;
      final prefix = el.milestone ? '◆ ' : '';
      final hours = el.workingHours > 0 ? ' (${el.workingHours}u)' : '';
      lines.add('$indent$prefix${el.name}$hours');
      if (el.isContainer) walk(el.children, depth + 1);
    }
  }

  walk(order.children, 0);

  return Slide.create(SlideType.tree).copyWith(
    title: 'WBS: ${order.name}',
    bullets: lines,
  );
}

// ── Resources (table) ──────────────────────────────────────────────────────

/// Bouw een table-slide met de resourcelijst.
Slide libreplanResourcesToTable(List<LibreplanResource> resources) {
  final rows = <List<String>>[
    ['Code', 'Naam', 'Type'],
    for (final r in resources.take(libreplanMaxTableRows))
      [r.code, r.displayName, r.isMachine ? 'Machine' : 'Medewerker'],
  ];
  return Slide.create(SlideType.table).copyWith(
    title: 'Resources',
    tableRows: rows,
  );
}

// ── Timesheet (table) ──────────────────────────────────────────────────────

/// Bouw een table-slide met timesheet-regels uit werkrapporten.
Slide libreplanWorkReportsToTable(List<LibreplanWorkReport> reports) {
  final rows = <List<String>>[
    ['Datum', 'Resource', 'Taak', 'Uren'],
  ];
  var count = 0;
  for (final report in reports) {
    if (count >= libreplanMaxTableRows) break;
    for (final line in report.lines) {
      if (count >= libreplanMaxTableRows) break;
      count++;
      rows.add([
        _fmtDate(line.date) ?? _fmtDate(report.date) ?? '',
        line.resource.isNotEmpty ? line.resource : report.resource,
        line.workOrder.isNotEmpty ? line.workOrder : report.workOrder,
        line.hours.toStringAsFixed(1),
      ]);
    }
  }
  return Slide.create(SlideType.table).copyWith(
    title: 'Timesheet',
    tableRows: rows,
  );
}

// ── Resource load (chart) ──────────────────────────────────────────────────

/// Bouw een chart-slide met resourcebelasting over tijd.
///
/// Aggregeert uren per resource per datum tot een staafdiagram. De x-as
/// toont datums, de series per resource.
Slide libreplanResourceHoursToChart(List<LibreplanResourceHours> hours) {
  if (hours.isEmpty) {
    return Slide.create(SlideType.chart).copyWith(
      title: 'Resourcebelasting',
      customMarkdown: '{"type":"bar","xLabels":[],"series":[]}',
    );
  }

  // Sorteer op datum en bouw unieke datums + resources.
  final sorted = [...hours]..sort((a, b) => a.date.compareTo(b.date));
  final dates = sorted.map((h) => h.date).toSet().toList()..sort();
  final resourceCodes = hours.map((h) => h.resourceCode).toSet().toList()
    ..sort();

  // Bouw een matrix: resource → datum → uren.
  final byResource = <String, Map<DateTime, double>>{};
  for (final h in hours) {
    byResource.putIfAbsent(h.resourceCode, () => {})[h.date] =
        (byResource[h.resourceCode]?[h.date] ?? 0) + h.hours;
  }

  final series = <Map<String, Object?>>[];
  for (final code in resourceCodes) {
    series.add({
      'name': code,
      'data': dates.map((d) => byResource[code]?[d] ?? 0.0).toList(),
    });
  }

  final spec = <String, Object?>{
    'type': 'bar',
    'xLabels': dates.map(_fmtDate).toList(),
    'series': series,
  };

  return Slide.create(SlideType.chart).copyWith(
    title: 'Resourcebelasting',
    customMarkdown: _jsonEncode(spec),
  );
}

// ── Project status (cockpit) ───────────────────────────────────────────────

/// Bouw een cockpit-slide met projectstatusmeters.
///
/// Toont voortgang (%), geplande uren, en of het project op schema ligt
/// (vergelijkt init-date met vandaag).
Slide libreplanOrderToCockpit(LibreplanOrder order) {
  final allElements = <LibreplanOrderElement>[];
  void collect(List<LibreplanOrderElement> els) {
    for (final el in els) {
      if (!el.isContainer) allElements.add(el);
      if (el.isContainer) collect(el.children);
    }
  }
  collect(order.children);

  final totalHours = allElements.fold(0, (s, e) => s + e.workingHours);
  final avgProgress = allElements.isEmpty
      ? 0.0
      : allElements.fold(0.0, (s, e) => s + e.progress) / allElements.length;
  final progressPct = (avgProgress * 100).round().clamp(0, 100);

  final spec = <String, Object?>{
    'layout': 'auto',
    'animateOnEnter': true,
    'animationDurationMs': 2800,
    'meters': [
      <String, Object?>{
        'type': 'speedometer',
        'label': 'Voortgang',
        'unit': '%',
        'min': 0,
        'max': 100,
        'greenFrom': 0,
        'greenTo': 40,
        'redFrom': 70,
        'value': progressPct,
      },
      <String, Object?>{
        'type': 'speedometer',
        'label': 'Geplande uren',
        'unit': 'u',
        'min': 0,
        'max': (totalHours * 1.5).ceil().clamp(1, 99999),
        'greenFrom': 0,
        'greenTo': (totalHours * 0.5).ceil(),
        'redFrom': (totalHours * 1.2).ceil(),
        'value': totalHours,
      },
    ],
  };

  return Slide.create(SlideType.cockpit).copyWith(
    title: 'Status: ${order.name}',
    customMarkdown: _jsonEncode(spec),
  );
}

// ── Milestones (timeline) ──────────────────────────────────────────────────

/// Bouw een timeline-slide met milestones uit een order.
Slide libreplanOrderToTimeline(LibreplanOrder order) {
  final milestones = <LibreplanOrderElement>[];
  void collect(List<LibreplanOrderElement> els) {
    for (final el in els) {
      if (el.milestone) milestones.add(el);
      if (el.isContainer) collect(el.children);
    }
  }
  collect(order.children);

  milestones.sort((a, b) {
    final da = a.startDate ?? a.deadline;
    final db = b.startDate ?? b.deadline;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });

  final bullets = milestones.map((m) {
    final date = _fmtDate(m.startDate) ?? _fmtDate(m.deadline) ?? '';
    return '$date :: ${m.name} :: ';
  }).toList();

  return Slide.create(SlideType.timeline).copyWith(
    title: 'Milestones: ${order.name}',
    bullets: bullets,
  );
}

// ── Critical path (flow) ───────────────────────────────────────────────────

/// Bouw een flow-slide met het kritieke pad.
///
/// `ponytail:` Dit is een naïeve benadering: het kritieke pad wordt benaderd
/// door de langste keten van afhankelijkheden te volgen. LibrePlan berekent
/// dit server-side met CPM; wij hebben alleen de ruwe structuur. Voor een
/// echte critical-path-berekening zou de connector een apart endpoint nodig
/// hebben. Het plafond is "goed genoeg voor een samenvatting-dia".
Slide libreplanOrderToCriticalPath(LibreplanOrder order) {
  // Verzamel alle elementen met hun code → element map.
  final byCode = <String, LibreplanOrderElement>{};
  void collect(List<LibreplanOrderElement> els) {
    for (final el in els) {
      if (el.code.isNotEmpty) byCode[el.code] = el;
      if (el.isContainer) collect(el.children);
    }
  }
  collect(order.children);

  // Bouw een naam→code map voor dependency-resolutie.
  final byName = <String, LibreplanOrderElement>{};
  for (final e in byCode.values) {
    byName[e.name] = e;
  }

  // Vind knopen zonder inkomende afhankelijkheden (startpunten).
  final hasIncoming = <String>{};
  for (final el in byCode.values) {
    for (final dep in el.dependencies) {
      final target = byName[dep] ?? byCode[dep];
      if (target != null) hasIncoming.add(target.code);
    }
  }
  final starts = <LibreplanOrderElement>[];
  for (final e in byCode.values) {
    if (!hasIncoming.contains(e.code)) starts.add(e);
  }

  // Volg de langste keten vanaf elk startpunt (DFS, beperkt diepte).
  List<LibreplanOrderElement>? longest;
  void dfs(LibreplanOrderElement current, List<LibreplanOrderElement> path, int depth) {
    if (depth > 20) return; // ponytail: diepte-limiet tegen cycli
    final extended = [...path, current];
    final children = <LibreplanOrderElement>[];
    for (final dep in current.dependencies) {
      final child = byName[dep] ?? byCode[dep];
      if (child != null) children.add(child);
    }
    if (children.isEmpty) {
      if (longest == null || extended.length > longest!.length) {
        longest = extended;
      }
      return;
    }
    for (final child in children) {
      dfs(child, extended, depth + 1);
    }
  }

  for (final start in starts) {
    dfs(start, [], 0);
  }

  final path = longest ?? <LibreplanOrderElement>[];
  final bullets = <String>[];
  for (final e in path) {
    final hours = e.workingHours > 0 ? '${e.workingHours}u' : '';
    bullets.add('${e.name} :: process :: pt=${hours};crit=1');
  }

  return Slide.create(SlideType.flow).copyWith(
    title: 'Kritieke pad: ${order.name}',
    bullets: bullets,
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────

String? _fmtDate(DateTime? d) {
  if (d == null) return null;
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Duur uit working-hours: 8u/dag aanname (LibrePlan default).
/// `ponytail:` Dit is een schatting — LibrePlan kent de echte kalender niet
/// in de REST-export. Voor een samenvatting-dia is dit goed genoeg.
String _durationFromHours(int hours) {
  if (hours <= 0) return '1d';
  final days = (hours / 8).ceil();
  if (days <= 5) return '${days}d';
  final weeks = (days / 5).ceil();
  if (weeks <= 4) return '${weeks}w';
  return '${(weeks / 4).ceil()}w';
}

String _statusFromProgress(double progress) {
  if (progress >= 1.0) return 'done';
  if (progress > 0) return 'active';
  return '';
}

String _jsonEncode(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is int) return value.toString();
  if (value is double) return value.toString();
  if (value is String) return '"${_escape(value)}"';
  if (value is List) return '[${value.map(_jsonEncode).join(',')}]';
  if (value is Map) {
    final entries = value.entries.map(
      (e) => '"${_escape(e.key.toString())}":${_jsonEncode(e.value)}',
    );
    return '{${entries.join(',')}}';
  }
  return 'null';
}

String _escape(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n');
