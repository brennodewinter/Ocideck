/// Het risicodossier als geheel: de getypte leeslaag bovenop
/// [scanOciMarkedTables] die de gemarkeerde tabellen van een bestand tot
/// risico-, maatregel-, schaal-, weergave- en bowtie-records maakt.
///
/// Eén dossier = één bestand (D4 uit het contract). Deze laag *leest*;
/// schrijven blijft de chirurgische [rewriteOciMarkedTable]-familie, zodat
/// elke mutatie exact één plek in de bron raakt en de rest byte-getrouw
/// meereist.
library;

import '../models/risk_dossier.dart';
import 'ocideck_marked_table.dart';
import 'ocideck_markers.dart';

/// Eén gemarkeerde tabel plus zijn ontlede contractrijen.
class RiskDossier {
  final String source;
  final OciMarkedTableScan scan;

  const RiskDossier._(this.source, this.scan);

  /// Leest het dossier uit de volledige bestandsbron — het is bewust een
  /// momentopname: bewerk, her-scan.
  factory RiskDossier.read(String source) =>
      RiskDossier._(source, scanOciMarkedTables(source));

  /// Alle `risks`-tabellen (meestal één; meerdere registers in één bestand
  /// mogen, elk met eigen `id=` en `next=`).
  List<OciMarkedTable> get riskTables => _ofKind(OciMarkerKinds.risks);
  List<OciMarkedTable> get measureTables => _ofKind(OciMarkerKinds.measures);
  List<OciMarkedTable> get scaleTables => _ofKind(OciMarkerKinds.scale);
  List<OciMarkedTable> get viewTables => _ofKind(OciMarkerKinds.view);
  List<OciMarkedTable> get bowtieTables => _ofKind(OciMarkerKinds.bowtie);

  List<OciMarkedTable> _ofKind(String kind) => [
    for (final t in scan.tables)
      if (t.kind == kind && (t.marker?.versionSupported ?? false)) t,
  ];

  /// Alle risico-records over alle registers heen.
  List<RiskRecord> get risks => [
    for (final t in riskTables)
      for (final row in t.contractRows) RiskRecord(row),
  ];

  List<MeasureRecord> get measures => [
    for (final t in measureTables)
      for (final row in t.contractRows) MeasureRecord(row),
  ];

  List<BowtieElement> get bowtieElements => [
    for (final t in bowtieTables)
      for (final row in t.contractRows) BowtieElement(row),
  ];

  /// De `risks`-tabel met `id=` [tableId] — de `source=` van een `view` of
  /// de `scale=` van een register verwijst hiernaar (binnen dit bestand).
  OciMarkedTable? tableById(String tableId) {
    for (final t in scan.tables) {
      if (t.id == tableId) return t;
    }
    return null;
  }

  /// Het risico-record met contract-ID [riskId] (bijv. `R-001`), over alle
  /// registers heen. `null` = kwaliteitsbevinding voor de aanroeper.
  RiskRecord? riskById(String riskId) {
    for (final r in risks) {
      if (r.id == riskId) return r;
    }
    return null;
  }

  MeasureRecord? measureById(String measureId) {
    for (final m in measures) {
      if (m.id == measureId) return m;
    }
    return null;
  }

  /// De schaal die een `risks`-tabel gebruikt: de naam uit `scale=`, eerst
  /// als aangepaste `scale`-tabel in dit bestand, dan als ingebouwde naam.
  /// `null` als geen van beide matcht.
  RiskScale? scaleFor(OciMarkedTable riskTable) {
    final name = riskTable.marker?.attr('scale');
    if (name == null || name.isEmpty) return RiskScale.sod110;
    final custom = scaleTables.where((t) => t.id == name).firstOrNull;
    if (custom != null) {
      final labels = <int, String>{};
      for (final row in custom.contractRows) {
        final v = int.tryParse(row['value']?.trim() ?? '');
        if (v != null) labels[v] = row['label']?.trim() ?? '';
      }
      return RiskScale(name, custom.marker?.intAttr('version') ?? 0, labels);
    }
    return RiskScale.builtin(name);
  }
}

/// Het prefix dat een contract-ID draagt per tabelsoort (§3.1).
String ociContractIdPrefix(OciMarkedTable table) => switch (table.kind) {
  OciMarkerKinds.measures => 'M',
  OciMarkerKinds.bowtie => 'P',
  _ => 'R',
};

/// Formatteert een contract-ID (`R-004`, `M-012`); drie cijfers is de
/// contractvorm, grotere tellers groeien er gewoon overheen.
String formatOciContractId(String prefix, int n) =>
    '$prefix-${n.toString().padLeft(3, '0')}';

/// Kent het volgende contract-ID uit op [table]: `R-###`/`M-###` uit de
/// `next=`-teller van de marker, die meteen wordt opgehoogd — een ID wordt
/// per bestand nooit hergebruikt, óók niet na verwijderen (§3.1).
///
/// Geeft `(id, source)` terug: de nieuwe bron waarin alleen de markerregel
/// van deze tabel anders is. Zonder `next=` valt er niets te verdelen en
/// komt `null` terug — de tabel is dan geen ID-bron.
(String id, String source)? allocateOciContractId(
  String source,
  OciMarkedTable table,
) {
  final next = table.next;
  if (next == null) return null;
  final id = formatOciContractId(ociContractIdPrefix(table), next);
  return (id, rewriteOciMarkedTableAttr(source, table, 'next', '${next + 1}'));
}
