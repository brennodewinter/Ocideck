/// Het Bowtie-bronmodel uit §3.8 en #2495: paden van dreiging via
/// preventieve barrières en het topgebeurtenis naar mitigerende
/// barrières en gevolg — als gewone, inspecteerbare tabel.
///
/// Deze module beantwoordt de bronvalidatie-vragen: welke paden zijn er,
/// waar ontbreekt de topgebeurtenis, welke barrière staat op de verkeerde
/// zijde, en welke paden liggen open. Een onvolledige Bowtie is een
/// concept — waarneembaar, nooit als complete dekking gepresenteerd.
library;

import '../models/risk_dossier.dart';
import 'ocideck_marked_table.dart';

/// De rol-tokens uit §3.8 — Engels is de schrijfvorm, de Nederlandse set
/// leest mee zodat handgeschreven dossiers niet breken.
const ociBowtieRoles = {
  'threat': 'threat',
  'dreiging': 'threat',
  'barrier-preventive': 'barrier-preventive',
  'barriere-preventief': 'barrier-preventive',
  'top-event': 'top-event',
  'topgebeurtenis': 'top-event',
  'barrier-mitigating': 'barrier-mitigating',
  'barriere-mitigerend': 'barrier-mitigating',
  'consequence': 'consequence',
  'gevolg': 'consequence',
  'escalation': 'escalation',
  'escalatiefactor': 'escalation',
  'barrier-escalation': 'barrier-escalation',
  'barriere-escalatie': 'barrier-escalation',
};

/// Welke rol op welke `side` thuishoort. `escalation` en
/// `barrier-escalation` ontbreken hier bewust: een escalatiefactor tast
/// de werking van een barrière aan en mag beide zijden staan.
const ociBowtieRoleSides = {
  'threat': {'links', 'left', ''},
  'barrier-preventive': {'links', 'left', ''},
  'top-event': {'top', ''},
  'barrier-mitigating': {'rechts', 'right', ''},
  'consequence': {'rechts', 'right', ''},
};

/// De status-tokens die een barrière/maatregel op een pad kan dragen.
/// 'voorgesteld' en 'werkt' zijn bewust ver uiteen: alleen de getoetste
/// staat mag dekking suggereren.
const ociBowtieStatuses = {
  'voorgesteld',
  'proposed',
  'gepland',
  'planned',
  'geïmplementeerd',
  'implemented',
  'getest',
  'tested',
  'werkt',
  'working',
  'werkt-niet',
  'ineffective',
};

/// Of een status-token dekking mag claimen — spiegel aan
/// [MeasureStatus.justifiesNetto].
bool ociBowtieStatusCovers(String status) => switch (status.trim()) {
  'werkt' || 'working' || 'getest' || 'tested' => true,
  _ => false,
};

/// Eén pad van de Bowtie: de rijen met dezelfde `path`-waarde.
class BowtiePath {
  final String id;
  final List<BowtieElement> elements;
  const BowtiePath(this.id, this.elements);

  /// Telt alleen mee als de rol óók op zijn zijde staat — een preventieve
  /// barrière rechts dekt niets af.
  bool _has(String role) => elements.any(
    (e) =>
        ociBowtieRoles[e.role.trim()] == role &&
        (ociBowtieRoleSides[role]?.contains(e.side.trim()) ?? true),
  );

  BowtieElement? get topEvent => _has('top-event')
      ? elements.firstWhere((e) => ociBowtieRoles[e.role.trim()] == 'top-event')
      : null;

  /// De preventieve zijde is compleet als er een dreiging én minstens één
  /// preventieve barrière is.
  bool get hasLeft => _has('threat');
  bool get hasPreventiveBarrier => _has('barrier-preventive');

  /// De mitigerende zijde is compleet als er een gevolg én minstens één
  /// mitigerende barrière is.
  bool get hasRight => _has('consequence');
  bool get hasMitigatingBarrier => _has('barrier-mitigating');

  /// Een open pad is een concept: mist de top, of één van beide zijden.
  /// Waarneembaar als waarschuwing, nooit als complete dekking.
  bool get isComplete =>
      topEvent != null &&
      hasLeft &&
      hasPreventiveBarrier &&
      hasRight &&
      hasMitigatingBarrier;

  /// Wat ontbreekt, in mensentaal voor de bevinding.
  List<String> get gaps => [
    if (topEvent == null) 'topgebeurtenis',
    if (!hasLeft) 'dreiging',
    if (hasLeft && !hasPreventiveBarrier) 'preventieve barrière',
    if (!hasRight) 'gevolg',
    if (hasRight && !hasMitigatingBarrier) 'mitigerende barrière',
  ];
}

/// Groepeert de rijen van [table] per `path`-waarde, in bronvolgorde.
List<BowtiePath> ociBowtiePaths(OciMarkedTable table) {
  final paths = <String, List<BowtieElement>>{};
  final order = <String>[];
  for (final row in table.contractRows) {
    final e = BowtieElement(row);
    final p = e.path.trim().isEmpty ? '(zonder pad)' : e.path.trim();
    if (!paths.containsKey(p)) order.add(p);
    paths.putIfAbsent(p, () => []).add(e);
  }
  return [for (final p in order) BowtiePath(p, paths[p]!)];
}

/// Het eerste vrije padnummer (`P-###`) — handgeschreven `P-1`-vormen
/// tellen mee, zodat een nieuw pad nooit een bestaand ID hergebruikt.
int ociNextBowtiePathNumber(OciMarkedTable table) {
  var max = 0;
  final pattern = RegExp(r'P-?(\d+)', caseSensitive: false);
  for (final e in ociBowtiePaths(table).expand((p) => p.elements)) {
    final m = pattern.firstMatch(e.path.trim());
    if (m != null) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > max) max = n;
    }
  }
  return max + 1;
}

/// De skelet-rijen van een nieuw pad (§3.8): dreiging → preventieve
/// barrière → topgebeurtenis → mitigerende barrière → gevolg. Alles leeg
/// tot de mens invult — geen verzonnen inhoud.
List<List<String>> ociBowtiePathSkeleton(OciMarkedTable table, String pathId) {
  List<String> row(String side, String role) => [
    for (final key in table.cols)
      switch (key) {
        'path' => pathId,
        'side' => side,
        'role' => role,
        _ => '',
      },
  ];
  return [
    row('links', 'threat'),
    row('links', 'barrier-preventive'),
    row('top', 'top-event'),
    row('rechts', 'barrier-mitigating'),
    row('rechts', 'consequence'),
  ];
}

/// Voegt [rows] onderaan de body van [table] toe in [source] — de
/// chirurgische route voor "Pad toevoegen".
String appendOciTableRows(
  String source,
  OciMarkedTable table,
  List<List<String>> rows,
) => rewriteOciMarkedTable(
  source,
  table,
  bodyRows: [...table.bodyRows, ...rows],
);
