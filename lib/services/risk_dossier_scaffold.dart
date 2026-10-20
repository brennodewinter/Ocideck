/// De schrijfkant van het gedeelde risicodossier (#2492): het lege startblok
/// dat "nieuw risicodossier" in een bestand zet, en de import van een bestaande
/// tabel als risicoregister met expliciete kolommapping.
///
/// Beide schrijven alleen contract- en kopteksten — nooit scores. "Nog niet
/// beoordeeld" is de beginstand: elke scorecel blijft leeg tot een mens hem
/// invult, want een leeg veld is eerlijk en een verzonnen `laag` niet (§9).
library;

import '../models/risk_dossier.dart';
import 'markdown_table_codec.dart';
import 'ocideck_markers.dart';

/// De standaard kopteksten per contract-sleutel — gewone leesbare koppen zoals
/// in `docs/design/examples/risk-dossier.md`. Ze zijn *vrij* (§3.2): wie ze
/// aanpast of vertaalt, raakt het contract niet.
const ociContractHeaderLabels = <String, String>{
  'id': 'ID',
  'step': 'Processtap',
  'failure': 'Faalwijze',
  'effect': 'Effect',
  'cause': 'Oorzaak',
  'control': 'Beheersing',
  'measures': 'Maatregelen',
  's_b': 'S b',
  'o_b': 'O b',
  'd_b': 'D b',
  's_n': 'S n',
  'o_n': 'O n',
  'd_n': 'D n',
  'netto_basis': 'Netto-basis',
  'netto_date': 'Netto-datum',
  'netto_by': 'Netto-door',
  'event': 'Gebeurtenis',
  'consequence': 'Gevolg',
  'existing_measures': 'Bestaande maatregelen',
  'l_b': 'K b',
  'i_b': 'I b',
  'l_n': 'K n',
  'i_n': 'I n',
  'uncertainty': 'Onzekerheid',
  'title': 'Titel',
  'status': 'Status',
  'notes': 'Notities',
  'type': 'Type',
  'description': 'Beschrijving',
  'owner': 'Eigenaar',
  'evidence': 'Bewijs',
  'test_date': 'Toetsdatum',
  'expires': 'Vervalt',
  'risks': "Risico's",
  'value': 'Waarde',
  'label': 'Label',
  'meaning': 'Betekenis',
  'path': 'Pad',
  'side': 'Zijde',
  'role': 'Rol',
  'element': 'Element',
  'measure': 'Maatregel',
  // Afgeleide sleutels voor weergaven en calc — nooit contractkolommen.
  'rpn': 'RPN',
  'rpn_b': 'RPN b',
  'rpn_n': 'RPN n',
  'score': 'Score',
  'score_b': 'Score b',
  'score_n': 'Score n',
};

/// De contractkolommen van een `risks`-tabel per methode (§3.3).
List<String> ociRiskContractCols(RiskMethod method) => switch (method) {
  RiskMethod.fmea => const [
    'id',
    'step',
    'failure',
    'effect',
    's_b',
    'cause',
    'o_b',
    'control',
    'd_b',
    'measures',
    's_n',
    'o_n',
    'd_n',
    'netto_basis',
    'netto_date',
    'netto_by',
  ],
  RiskMethod.likelihoodImpact => const [
    'id',
    'event',
    'cause',
    'consequence',
    'existing_measures',
    'l_b',
    'i_b',
    'measures',
    'l_n',
    'i_n',
    'netto_basis',
    'netto_date',
    'netto_by',
    'uncertainty',
  ],
  // Bowtie is geen risks-tabel maar een eigen contract (§3.8); de aanroeper
  // gebruikt [ociBowtieContractCols]. Deze tak bestaat om de enum exhaustief
  // te houden.
  RiskMethod.bowtie => const [],
};

/// De contractkolommen van een `measures`-tabel (§3.4).
const ociMeasureContractCols = [
  'id',
  'type',
  'description',
  'owner',
  'status',
  'evidence',
  'test_date',
  'expires',
  'risks',
];

/// De contractkolommen van een `scale`-tabel (§3.5).
const ociScaleContractCols = ['value', 'label', 'meaning'];

/// De contractkolommen van een `bowtie`-tabel (§3.8).
const ociBowtieContractCols = [
  'path',
  'side',
  'role',
  'element',
  'measure',
  'status',
  'owner',
];

/// De standaard-schaalnaam per methode.
String ociDefaultScaleId(RiskMethod method) => switch (method) {
  RiskMethod.fmea => 'sod-1-10',
  RiskMethod.likelihoodImpact => 'li-1-5',
  RiskMethod.bowtie => '',
};

/// De markerregel voor een contracttabel, in de canonieke volgorde die elke
/// geschreven marker deelt: soort, versie, id, methode/schaal, rev, next, cols.
OciTableMarker _marker(
  String kind,
  String id, {
  String? method,
  String? scale,
  int rev = 1,
  int? next,
  List<String>? cols,
  Map<String, String> extra = const {},
}) {
  final attrs = <String, String>{
    'id': id,
    'method': ?method,
    if (scale != null && scale.isNotEmpty) 'scale': scale,
    'rev': '$rev',
    if (next != null) 'next': '$next',
    if (cols != null) 'cols': cols.join(','),
    ...extra,
  };
  return OciTableMarker(kind: kind, version: 1, attrs: attrs);
}

String _table(List<String> cols, [List<List<String>> body = const []]) =>
    encodeMarkdownTable([
      [for (final key in cols) ociContractHeaderLabels[key] ?? key],
      ...body,
    ]);

/// De context die de startdialoog vraagt (#2492): doel, beoordelaar en datum
/// als gewone proza — het contract kent bewust geen dossier-metadatamarker,
/// dus dit is leesbare tekst die elke schrijver en lezer begrijpt.
class RiskDossierContext {
  final String purpose;
  final String assessor;
  final String date;
  const RiskDossierContext({
    this.purpose = '',
    this.assessor = '',
    this.date = '',
  });

  bool get isEmpty => purpose.isEmpty && assessor.isEmpty && date.isEmpty;
}

/// Het invoegblok voor een nieuw risicodossier: de gemarkeerde `risks`- (of
/// `bowtie`-) tabel met lege body — geen verzonnen voorbeeldscores — plus, als
/// [withMeasures], een leeg maatregelenregister eronder.
///
/// Bowtie kent geen `risks`-tabel (§3.8): de bron is het bowtie-model zelf en
/// [RiskMethod.bowtie] levert dáárvoor het scaffold.
String riskDossierScaffold(
  RiskMethod method, {
  String tableId = 'risico',
  String measuresId = 'maatregelen',
  bool withMeasures = true,
  RiskDossierContext context = const RiskDossierContext(),
}) {
  final buf = StringBuffer();
  if (!context.isEmpty) {
    // Doel, scope en beoordelaar zijn proza, geen marker: iemand die het
    // dossier overneemt moet dit zonder OciDeck kunnen lezen én aanvullen.
    if (context.purpose.isNotEmpty) {
      buf.writeln('Doel: ${context.purpose}');
    }
    if (context.assessor.isNotEmpty) {
      buf.writeln('Beoordelaar: ${context.assessor}');
    }
    if (context.date.isNotEmpty) {
      buf.writeln('Datum: ${context.date}');
    }
    buf.writeln();
  }
  if (method == RiskMethod.bowtie) {
    buf
      ..writeln(
        _marker(
          OciMarkerKinds.bowtie,
          'bt1',
          cols: ociBowtieContractCols,
        ).toComment(),
      )
      ..write(_table(ociBowtieContractCols));
  } else {
    buf
      ..writeln(
        _marker(
          OciMarkerKinds.risks,
          tableId,
          method: method.token,
          scale: ociDefaultScaleId(method),
          next: 1,
          cols: ociRiskContractCols(method),
        ).toComment(),
      )
      ..write(_table(ociRiskContractCols(method)));
  }
  if (withMeasures) {
    buf
      ..write('\n\n')
      ..writeln(
        _marker(
          OciMarkerKinds.measures,
          measuresId,
          next: 1,
          cols: ociMeasureContractCols,
        ).toComment(),
      )
      ..write(_table(ociMeasureContractCols));
  }
  return buf.toString();
}

/// Het resultaat van een import: het herschreven tabelblok (marker + tabel),
/// hoeveel `R-###`-ID's er zijn uitgedeeld, en welke bronkolommen ongemapt
/// als vrije `x-*`-kolom zijn meegereisd.
class RiskTableImport {
  /// De regels van marker + tabel, klaar om het brontblok te vervangen.
  final String markdown;
  final int allocatedIds;
  final List<String> freeColumns;
  const RiskTableImport(this.markdown, this.allocatedIds, this.freeColumns);
}

/// Bouwt uit een gewone GFM-tabel een `risks`-register volgens [mapping]
/// (bronkolomindex → contract-sleutel; `null`/afwezig = vrije kolom).
///
/// De expliciete mapping is het contract van §7: de gebruiker zegt welke
/// kolom welke betekenis draagt, OciDeck raadt nooit — ook niet dat "Kans"
/// `l_b` is. Kolommen zonder mapping reizen als `x-N` mee, byte-identiek
/// in inhoud (wel verplaatst naar achter de contractkolommen, zodat `cols=`
/// positioneel blijft kloppen). Rijen zonder `id`-waarde krijgen een nieuw
/// `R-###` vanaf [startNext]; bestaande ID's blijven staan en tellen de
/// teller niet op — dubbele ID's zijn een zaak voor de kwaliteitscontrole.
RiskTableImport importTableAsRiskRegister(
  List<String> tableLines,
  RiskMethod method, {
  required Map<int, String?> mapping,
  required int startNext,
  String tableId = 'risico',
}) {
  final decoded = decodeMarkdownTableRows(tableLines);
  if (decoded.isEmpty) {
    return const RiskTableImport('', 0, []);
  }
  final header = decoded.first;
  final body = decoded.skip(1).toList();
  final contract = ociRiskContractCols(method);
  final byKey = <String, int>{};
  final free = <int>[];
  for (var c = 0; c < header.length; c++) {
    final key = mapping[c];
    if (key == null || key.isEmpty) {
      free.add(c);
    } else {
      byKey[key] = c;
    }
  }
  // 'id' is verplicht in elk register; zonder mapping komt er een ID-kolom
  // vooraan die de allocatie vult.
  final needsIdColumn = !byKey.containsKey('id');
  final outCols = <String>[
    ...contract,
    for (var i = 0; i < free.length; i++) 'x-$i',
  ];
  final outHeader = <String>[
    for (final key in contract)
      key == 'id' && needsIdColumn
          ? 'ID'
          : byKey.containsKey(key)
          ? header[byKey[key]!]
          : (ociContractHeaderLabels[key] ?? key),
    for (final c in free) header[c],
  ];
  var next = startNext;
  final outBody = <List<String>>[];
  final idCol = byKey['id'];
  for (final row in body) {
    String at(int c) => c < row.length ? row[c] : '';
    final needsId = idCol == null || at(idCol).isEmpty;
    outBody.add([
      for (final key in contract)
        key == 'id' && needsId
            ? formatImportId(next)
            : byKey.containsKey(key)
            ? at(byKey[key]!)
            : '',
      for (final c in free) at(c),
    ]);
    if (needsId) next++;
  }
  final marker = _marker(
    OciMarkerKinds.risks,
    tableId,
    method: method.token,
    scale: ociDefaultScaleId(method),
    next: next,
    cols: outCols,
  );
  return RiskTableImport(
    '${marker.toComment()}\n${encodeMarkdownTable([outHeader, ...outBody])}',
    next - startNext,
    [for (final c in free) header[c]],
  );
}

/// `R-###` voor importrijen; de teller staat los van een bestaand register
/// en start op [startNext] van de aanroeper.
String formatImportId(int n) => 'R-${n.toString().padLeft(3, '0')}';
