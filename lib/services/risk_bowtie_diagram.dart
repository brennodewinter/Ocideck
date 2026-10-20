/// De grafische projectie van het Bowtie-bronmodel (#2496): één
/// deterministische Mermaid `flowchart LR` uit dezelfde tabel die de
/// mens schrijft. Het diagram is afleiding, nooit bron — bewerken
/// gebeurt op de tabel, en elke vertoning (editor-schakelaar,
/// voorvertoning, export) tekent uit die ene bron opnieuw.
///
/// Vorm: dreigingen links, preventieve barrières in serie, het
/// topgebeurtenis centraal, mitigerende barrières en gevolgen rechts.
/// Barrières delen één knoop zodra ze naar dezelfde maatregel verwijzen;
/// dreiging, top en gevolg delen op naam. De status staat als tekst in de
/// knoop én als lijnstijl — een voorgestelde barrière ziet er nooit uit
/// als bewezen bescherming, óók niet in grijswaarden.
library;

import '../models/risk_dossier.dart';
import 'ocideck_marked_table.dart';
import 'ocideck_markers.dart';
import 'risk_bowtie.dart';

/// De Mermaid-bron van [table] — deterministisch: zelfde tabel, zelfde
/// diagram. `null` wanneer er helemaal geen elementen zijn; een leeg
/// diagram tekenen zou "geen risico" suggereren.
String? ociBowtieMermaid(OciMarkedTable table) {
  final elements = [
    for (var i = 0; i < table.contractRows.length; i++)
      (i, BowtieElement(table.contractRows[i])),
  ];
  if (elements.isEmpty) return null;

  // Knoop-id per element: maatregel-id deelt over paden, rol+naam deelt
  // dreiging/top/gevolg; wat niets deelt krijgt pad+rijnummer.
  String nodeId(int i, BowtieElement e) {
    final role = ociBowtieRoles[e.role.trim()] ?? 'x';
    final m = e.measure.trim();
    if (m.isNotEmpty) return 'm_${_norm(m)}';
    final name = _norm(e.element);
    return switch (role) {
      'threat' => 't_${name.isEmpty ? _norm(e.path) : name}',
      'top-event' => 'top_${name.isEmpty ? _norm(e.path) : name}',
      'consequence' => 'c_${name.isEmpty ? _norm(e.path) : name}',
      _ => '${_norm(role)}_${_norm(e.path.isEmpty ? 'pad' : e.path)}_$i',
    };
  }

  String cls(BowtieElement e) => switch (ociBowtieRoles[e.role.trim()]) {
    'threat' => 'threat',
    'top-event' => 'top',
    'consequence' => 'cons',
    'escalation' || 'barrier-escalation' => 'esc',
    _ => ociBowtieStatusCovers(e.status) ? 'barrierOk' : 'barrierDraft',
  };

  final nodes = <String, String>{}; // id → declaratie, in volgorde
  final idOf = <String, String>{}; // rij-sleutel → knoop-id
  String key(BowtieElement e) =>
      '${e.path}|${e.role}|${e.element}|${e.measure}|${e.status}';
  for (final (i, e) in elements) {
    final id = nodeId(i, e);
    if (!idOf.containsKey(key(e))) idOf[key(e)] = id;
    if (nodes.containsKey(id)) continue;
    final label = StringBuffer(_mmdLabel(e.element, e.role));
    if (e.status.trim().isNotEmpty) {
      // Tekst naast stijl: kleur alleen mag nooit het verschil tussen
      // "werkt" en "voorgesteld" dragen.
      label.write(
        '<br/>${ociBowtieStatusCovers(e.status) ? '✓' : '○'} '
        '${_mmdText(e.status)}',
      );
    }
    nodes[id] = '$id["$label"]:::${cls(e)}';
  }

  // Paden in bronvolgorde; per pad de keten in rijvolgorde (dreiging →
  // preventief → top → mitigerend → gevolg), met escalaties gestippeld
  // op de barrière die ze aantasten — de laatste op dat pad, of het
  // topgebeurtenis als er nog geen barrière staat.
  final edges = <String>{};
  void edge(String a, String op, String b) {
    if (a != b) edges.add('$a $op $b');
  }

  for (final path in ociBowtiePaths(table)) {
    var prev = '';
    var lastBarrier = '';
    var lastNode = '';
    final esc = <String, String>{}; // escalatie → barrière op dát moment
    for (final e in path.elements) {
      final id = idOf[key(e)]!;
      final role = ociBowtieRoles[e.role.trim()];
      if (role == 'escalation' || role == 'barrier-escalation') {
        esc[id] = lastBarrier;
        continue;
      }
      if (prev.isNotEmpty) edge(prev, '-->', id);
      prev = id;
      lastNode = id;
      if (role == 'barrier-preventive' || role == 'barrier-mitigating') {
        lastBarrier = id;
      }
    }
    // Een escalatie vóór de eerste barrière valt terug op de laatste
    // barrière van het pad; zonder barrière op het topgebeurtenis.
    for (final MapEntry(key: e, value: anchor) in esc.entries) {
      edge(
        e,
        '-.->',
        anchor.isNotEmpty
            ? anchor
            : lastBarrier.isNotEmpty
            ? lastBarrier
            : lastNode,
      );
    }
  }

  return [
    'flowchart LR',
    ...nodes.values.map((d) => '  $d'),
    ...edges.map((e) => '  $e'),
    '  classDef threat fill:#eceff1,stroke:#546e7a,color:#263238',
    '  classDef top fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#4e0000',
    '  classDef barrierOk fill:#e8f5e9,stroke:#2e7d32,color:#1b5e20',
    '  classDef barrierDraft fill:#fff8e1,stroke:#f9a825,'
        'stroke-dasharray:5 4,color:#5d4037',
    '  classDef cons fill:#e3f2fd,stroke:#1565c0,color:#0d47a1',
    '  classDef esc fill:#ffffff,stroke:#9e9e9e,'
        'stroke-dasharray:2 3,color:#616161',
  ].join('\n');
}

/// Voegt vóór elke Bowtie-tabel in [source] het afgeleide ` ```mermaid `
/// diagram in — de tabel zelf blijft staan als inspecteerbare bron én
/// leesbare terugval. Alleen voor het render-pad (preview/export);
/// de bron op schijf verandert nooit.
String markdownWithBowtieDiagrams(String source) {
  final bowties = [
    for (final t in scanOciMarkedTables(source).tables)
      if (t.kind == OciMarkerKinds.bowtie) t,
  ];
  if (bowties.isEmpty) return source;
  final lines = source.split('\n');
  // Achteruit invoegen zodat eerdere blokken hun regelnummers houden.
  for (final table in bowties.reversed) {
    final mmd = ociBowtieMermaid(table);
    if (mmd == null) continue;
    lines.insertAll(table.tableStart, ['```mermaid', mmd, '```', '']);
  }
  return lines.join('\n');
}

/// Wat een schermlezer bij het diagram hoort: per pad de keten in één
/// zin, zodat het plaatje een tekstalternatief heeft (#2496).
String ociBowtieSemanticsLabel(OciMarkedTable table) {
  String name(BowtieElement e) =>
      e.element.trim().isEmpty ? e.role.trim() : e.element.trim();
  final parts = <String>[
    for (final path in ociBowtiePaths(table))
      'Pad ${path.id}: ${path.elements.map(name).join(' → ')}',
  ];
  return 'Bowtie-diagram. ${parts.join('. ')}';
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');

/// Label-tekst voor in een `["…"]`-knoop: Mermaid-entiteiten voor de
/// tekens die de grammatica breken. Één doorloop per teken — zou je per
/// patroon vervangen, dan ontsnapte de `;` van een zojuist geplaatste
/// entiteit nog een keer (`#quot;` → `#quot#59;`).
String _mmdText(String s) {
  const entities = {
    '&': '#38;',
    '"': '#quot;',
    "'": '#39;',
    '<': '#60;',
    '>': '#62;',
    '[': '#91;',
    ']': '#93;',
    '(': '#40;',
    ')': '#41;',
    '{': '#123;',
    '}': '#125;',
    ';': '#59;',
  };
  final buf = StringBuffer();
  for (final ch in s.trim().split('')) {
    buf.write(entities[ch] ?? (ch == '\n' ? ' ' : ch));
  }
  return buf.toString();
}

/// De knooptekst: de naam, of als die leeg is de rol zelf — een
/// naamloze knoop zou als "af" lezen terwijl hij leeg is.
String _mmdLabel(String element, String role) {
  final name = element.trim();
  return _mmdText(name.isEmpty ? role : name);
}
