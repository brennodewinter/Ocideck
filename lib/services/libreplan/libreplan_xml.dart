/// LibrePlan REST XML → Dart models. Pure Dart, geen netwerk, testbaar.
///
/// LibrePlan's REST API (`/ws/rest/<service-path>/`) retourneert XML met
/// namespace `http://rest.ws.libreplan.dev`. Deze laag parseert dat defensief:
/// ontbrekende velden worden getolereerd, onbekende velden genegeerd, een veld
/// dat niet parseert wordt overgeslagen — niet gecrasht. Zie het design-doc
/// §5.4 ("XML parsing safety").
///
/// De `xml`-package parset, voert niet uit: geen XXE (geen externe entities),
/// geen code-evaluatie. De parser krijgt alleen XML van een door de gebruiker
/// aangewezen LibrePlan-server, nooit uit een deck of een onvertrouwde bron.
/// `ponytail:` plafond: een kwaadaardige server (of MITM op plain HTTP) kan
/// pathologische XML sturen; de parser-limieten vangen dat, de connector faalt
/// gesloten met een zichtbare fout.
library;

import 'package:xml/xml.dart';

/// Maximaal aantal geneste elementen voordat de parser weigert. Voorkomt
/// pathologisch diepe XML (billion laughs-variant). Het design-doc stelt
/// max depth 100 voor (§5.4, open vraag 5).
const libreplanXmlMaxDepth = 100;

/// Maximaal aantal bytes dat de parser accepteert. Voorkomt dat een
/// kwaadaardige server het geheugen vult met een gigantisch document.
/// 10 MB is ruim voldoende voor een LibrePlan-projectsnapshot.
const libreplanXmlMaxBytes = 10 * 1024 * 1024;

// ── Models ─────────────────────────────────────────────────────────────────

/// Een LibrePlan-project (OrderDTO). Bevat de hiërarchische structuur van
/// order elements (taken/groepen).
class LibreplanOrder {
  final String code;
  final String name;
  final DateTime? initDate;
  final List<LibreplanOrderElement> children;

  const LibreplanOrder({
    required this.code,
    required this.name,
    this.initDate,
    this.children = const [],
  });
}

/// Een order element: een taak (`order-line`) of een groep (`order-line-group`).
/// Groepen hebben kinderen; bladtaken hebben hours-groups.
class LibreplanOrderElement {
  final String code;
  final String name;
  final DateTime? startDate;
  final DateTime? deadline;
  final double progress;
  final bool milestone;
  final List<String> dependencies;
  final List<LibreplanOrderElement> children;
  final int workingHours;

  const LibreplanOrderElement({
    required this.code,
    required this.name,
    this.startDate,
    this.deadline,
    this.progress = 0.0,
    this.milestone = false,
    this.dependencies = const [],
    this.children = const [],
    this.workingHours = 0,
  });

  /// Of dit een container is (heeft kinderen).
  bool get isContainer => children.isNotEmpty;
}

/// Een LibrePlan-resource: een machine of een medewerker.
class LibreplanResource {
  final String code;
  final String name;
  final bool isMachine;
  final String firstName;
  final String surname;
  final String nif;

  const LibreplanResource({
    required this.code,
    required this.name,
    this.isMachine = false,
    this.firstName = '',
    this.surname = '',
    this.nif = '',
  });

  /// Weergavenaam: machines gebruiken `name`, medewerkers gebruiken
  /// "voornaam achternaam" (of `name` als die leeg is).
  String get displayName {
    if (isMachine) return name;
    final full = '$firstName $surname'.trim();
    return full.isNotEmpty ? full : name;
  }
}

/// Gewerkte uren per resource per datum (uit resourceshours-endpoint).
class LibreplanResourceHours {
  final String resourceCode;
  final DateTime date;
  final double hours;

  const LibreplanResourceHours({
    required this.resourceCode,
    required this.date,
    required this.hours,
  });
}

/// Een werkrapport (timesheet) met regels.
class LibreplanWorkReport {
  final String code;
  final DateTime? date;
  final String resource;
  final String workOrder;
  final List<LibreplanWorkReportLine> lines;

  const LibreplanWorkReport({
    required this.code,
    this.date,
    this.resource = '',
    this.workOrder = '',
    this.lines = const [],
  });
}

/// Een regel in een werkrapport: uren op een taak voor een resource op een datum.
class LibreplanWorkReportLine {
  final String code;
  final double hours;
  final DateTime? date;
  final String resource;
  final String workOrder;

  const LibreplanWorkReportLine({
    required this.code,
    this.hours = 0,
    this.date,
    this.resource = '',
    this.workOrder = '',
  });
}

/// Een declaratie van uitgaven (ExpenseSheetDTO).
class LibreplanExpenseSheet {
  final String code;
  final DateTime? date;
  final String resource;
  final double total;

  const LibreplanExpenseSheet({
    required this.code,
    this.date,
    this.resource = '',
    this.total = 0,
  });
}

// ── Parsing ────────────────────────────────────────────────────────────────

/// Fout bij het parsen van LibrePlan-XML. Bevat nooit de response body (die
/// kan projectdata bevatten) — alleen de reden.
class LibreplanXmlException implements Exception {
  const LibreplanXmlException(this.reason);
  final String reason;

  @override
  String toString() => 'LibreplanXmlException: $reason';
}

/// Parse een order-list XML (uit `/ws/rest/orderelements/`).
///
/// Retourneert een lijst met projecten. Een lege of ongeldig XML retourneert
/// een lege lijst (fail-closed: liever geen slides dan kapotte slides).
List<LibreplanOrder> parseOrderList(String xml) {
  final doc = _parseSafely(xml);
  if (doc == null) return [];
  final root = _findRoot(doc, 'order-list');
  if (root == null) return [];
  return root
      .findElements('order', namespace: '*')
      .map(_parseOrder)
      .toList();
}

/// Parse een resource-list XML (uit `/ws/rest/resources/`).
List<LibreplanResource> parseResourceList(String xml) {
  final doc = _parseSafely(xml);
  if (doc == null) return [];
  final root = _findRoot(doc, 'resource-list');
  if (root == null) return [];
  final resources = <LibreplanResource>[];
  for (final el in root.children) {
    if (el is! XmlElement) continue;
    final local = el.name.local;
    if (local == 'machine') {
      resources.add(_parseResource(el, isMachine: true));
    } else if (local == 'worker') {
      resources.add(_parseResource(el, isMachine: false));
    }
  }
  return resources;
}

/// Parse een work-report-list XML (uit `/ws/rest/workreports/`).
List<LibreplanWorkReport> parseWorkReportList(String xml) {
  final doc = _parseSafely(xml);
  if (doc == null) return [];
  final root = _findRoot(doc, 'work-report-list');
  if (root == null) return [];
  return root
      .findElements('work-report', namespace: '*')
      .map(_parseWorkReport)
      .toList();
}

/// Parse een resource-worked-hours-list XML (uit `/ws/rest/resourceshours/`).
List<LibreplanResourceHours> parseResourceHoursList(String xml) {
  final doc = _parseSafely(xml);
  if (doc == null) return [];
  // De root kan verschillende namen hebben afhankelijk van de LibrePlan-versie;
  // zoek naar elementen die er als resource-hours uitzien.
  final hours = <LibreplanResourceHours>[];
  for (final el in doc.descendantElements) {
    final local = el.name.local;
    if (local == 'resource-worked-hours' || local == 'resource-hours') {
      final resourceCode = _attr(el, 'resource') ?? _attr(el, 'code') ?? '';
      // work-report-line kan direct of in een work-report-line-list zitten.
      final linesEl = _child(el, 'work-report-line-list');
      final lineSource = linesEl ?? el;
      final lines = lineSource.findElements('work-report-line', namespace: '*');
      for (final line in lines) {
        final date = _parseDate(_attr(line, 'date'));
        final h = _parseDouble(_attr(line, 'hours'));
        if (date != null && h > 0) {
          hours.add(LibreplanResourceHours(
            resourceCode: resourceCode,
            date: date,
            hours: h,
          ));
        }
      }
    }
  }
  return hours;
}

/// Parse een expense-sheet-list XML (uit `/ws/rest/expenses/`).
List<LibreplanExpenseSheet> parseExpenseSheetList(String xml) {
  final doc = _parseSafely(xml);
  if (doc == null) return [];
  final root = _findRoot(doc, 'expense-sheet-list');
  if (root == null) return [];
  return root
      .findElements('expense-sheet', namespace: '*')
      .map(_parseExpenseSheet)
      .toList();
}

// ── Internal helpers ───────────────────────────────────────────────────────

/// Parse XML defensief, met limieten. Retourneert null bij ongeldig XML of
/// overschrijding van de limieten — de aanroeper degradeert naar een lege
/// lijst (fail-closed).
XmlDocument? _parseSafely(String xml) {
  if (xml.length > libreplanXmlMaxBytes) {
    throw const LibreplanXmlException(
      'XML overschrijdt de maximale grootte (${libreplanXmlMaxBytes} bytes)',
    );
  }
  try {
    final doc = XmlDocument.parse(xml);
    if (_maxDepth(doc) > libreplanXmlMaxDepth) {
      throw const LibreplanXmlException(
        'XML overschrijdt de maximale diepte ($libreplanXmlMaxDepth)',
      );
    }
    return doc;
  } on XmlException {
    return null;
  } on LibreplanXmlException {
    rethrow;
  }
}

/// Vind het root-element met de gegeven lokale naam, ongeacht namespace.
XmlElement? _findRoot(XmlDocument doc, String localName) {
  for (final node in doc.children) {
    if (node is XmlElement && node.name.local == localName) return node;
  }
  return null;
}

/// Bereken de maximale diepte van de XML-structuur.
int _maxDepth(XmlNode node, [int current = 0]) {
  if (current > libreplanXmlMaxDepth) return current;
  if (node.children.isEmpty) return current;
  return node.children.fold(current, (max, child) {
    final depth = _maxDepth(child, current + 1);
    return depth > max ? depth : max;
  });
}

LibreplanOrder _parseOrder(XmlElement el) {
  return LibreplanOrder(
    code: _attr(el, 'code') ?? '',
    name: _attr(el, 'name') ?? '',
    initDate: _parseDate(_attr(el, 'init-date')),
    children: _parseOrderChildren(el),
  );
}

List<LibreplanOrderElement> _parseOrderChildren(XmlElement parent) {
  final childrenEl = _child(parent, 'children');
  if (childrenEl == null) return [];
  final result = <LibreplanOrderElement>[];
  for (final el in childrenEl.children) {
    if (el is! XmlElement) continue;
    final local = el.name.local;
    if (local == 'order-line-group' ||
        local == 'order-line' ||
        local == 'order-element') {
      result.add(_parseOrderElement(el));
    }
  }
  return result;
}

LibreplanOrderElement _parseOrderElement(XmlElement el) {
  final children = _parseOrderChildren(el);
  final hoursGroups = el.findElements('hours-groups', namespace: '*');
  var workingHours = 0;
  for (final hg in hoursGroups) {
    for (final group in hg.findElements('hours-group', namespace: '*')) {
      workingHours += _parseInt(_attr(group, 'working-hours')) ?? 0;
    }
  }
  // Dependencies: LibrePlan gebruikt verschillende representaties; we zoeken
  // zowel naar <dependencies><dependency origin="..."/> als naar attributen.
  final deps = <String>[];
  final depsEl = _child(el, 'dependencies');
  if (depsEl != null) {
    for (final dep
        in depsEl.findElements('dependency', namespace: '*')) {
      final origin = _attr(dep, 'origin') ?? _attr(dep, 'name') ?? '';
      if (origin.isNotEmpty) deps.add(origin);
    }
  }
  return LibreplanOrderElement(
    code: _attr(el, 'code') ?? '',
    name: _attr(el, 'name') ?? '',
    startDate: _parseDate(_attr(el, 'start-date') ?? _attr(el, 'init-date')),
    deadline: _parseDate(_attr(el, 'deadline') ?? _attr(el, 'end-date')),
    progress: _parseProgress(el),
    milestone: _parseBool(_attr(el, 'milestone')),
    dependencies: deps,
    children: children,
    workingHours: workingHours,
  );
}

double _parseProgress(XmlElement el) {
  // Progress kan een attribuut zijn of in een schedulingState-element zitten.
  final attr = _attr(el, 'progress');
  if (attr != null) return _parseDouble(attr);
  final sched = _child(el, 'scheduling-state') ??
      _child(el, 'schedulingState');
  if (sched != null) {
    final p = _attr(sched, 'progress');
    if (p != null) return _parseDouble(p);
  }
  return 0.0;
}

LibreplanResource _parseResource(XmlElement el, {required bool isMachine}) {
  final name = _attr(el, 'name') ?? '';
  final firstName = _attr(el, 'first-name') ?? '';
  final surname = _attr(el, 'surname') ?? '';
  // Voor machines is `name` de weergavenaam; voor medewerkers is die soms leeg
  // en gebruiken we first-name + surname.
  return LibreplanResource(
    code: _attr(el, 'code') ?? '',
    name: name,
    isMachine: isMachine,
    firstName: firstName,
    surname: surname,
    nif: _attr(el, 'nif') ?? '',
  );
}

LibreplanWorkReport _parseWorkReport(XmlElement el) {
  final linesEl = _child(el, 'work-report-line-list');
  final lines = <LibreplanWorkReportLine>[];
  if (linesEl != null) {
    for (final line
        in linesEl.findElements('work-report-line', namespace: '*')) {
      lines.add(LibreplanWorkReportLine(
        code: _attr(line, 'code') ?? '',
        hours: _parseDouble(_attr(line, 'hours')),
        date: _parseDate(_attr(line, 'date')),
        resource: _attr(line, 'resource') ?? '',
        workOrder: _attr(line, 'work-order') ?? '',
      ));
    }
  }
  return LibreplanWorkReport(
    code: _attr(el, 'code') ?? '',
    date: _parseDate(_attr(el, 'date')),
    resource: _attr(el, 'resource') ?? '',
    workOrder: _attr(el, 'work-order') ?? '',
    lines: lines,
  );
}

LibreplanExpenseSheet _parseExpenseSheet(XmlElement el) {
  return LibreplanExpenseSheet(
    code: _attr(el, 'code') ?? '',
    date: _parseDate(_attr(el, 'date')),
    resource: _attr(el, 'resource') ?? '',
    total: _parseDouble(_attr(el, 'total')),
  );
}

/// Attribuut-waarde zonder namespace-gezeur. `package:xml`'s
/// `getAttribute` kan een namespace-prefix vereisen; wij willen alleen de
/// lokale naam matchen.
String? _attr(XmlElement el, String name) {
  for (final attr in el.attributes) {
    if (attr.name.local == name) return attr.value;
  }
  return null;
}

/// Vind een kind-element op lokale naam, ongeacht namespace.
XmlElement? _child(XmlElement parent, String localName) {
  for (final node in parent.children) {
    if (node is XmlElement && node.name.local == localName) return node;
  }
  return null;
}

/// Parse een ISO-datum defensief. LibrePlan gebruikt `2026-09-01` (date-only)
/// of `2010-03-18T00:00:00+01:00` (met tijd). We parsen date-only en negeren
/// de tijd-component (design-doc open vraag 3).
DateTime? _parseDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final s = value.trim();
  // Probeer date-only (10 tekens: YYYY-MM-DD).
  if (s.length >= 10) {
    final datePart = s.substring(0, 10);
    try {
      return DateTime.parse(datePart);
    } catch (_) {
      // Val door naar full-parse poging.
    }
  }
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

double _parseDouble(String? value) {
  if (value == null || value.trim().isEmpty) return 0.0;
  return double.tryParse(value.trim()) ?? 0.0;
}

int? _parseInt(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return int.tryParse(value.trim());
}

bool _parseBool(String? value) {
  if (value == null) return false;
  final s = value.trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}
