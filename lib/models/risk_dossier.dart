/// De getypeerde leeslaag over het risicodossier-contract
/// (docs/design/RISK_FORMAT.md §3): risico's, maatregelen en schalen zoals
/// ze in de `cols=`-contracten van de gemarkeerde tabellen liggen.
///
/// Alles hier is *data*: een record is een venster op één contractrij en
/// leent de cellen — bewerken gebeurt altijd in de tabel, nooit in het
/// record. Scores zijn `int?`: een lege of onleesbare cel is "niet
/// beoordeeld" en mag nooit als `0` of "laag risico" doorrekenen (§9).
library;

/// De zes levensfase-tokens van een maatregel (§3.4). De bestandstokens
/// zijn Engels; de UI lokaliseert.
enum MeasureStatus {
  proposed,
  planned,
  implemented,
  tested,
  working,
  ineffective;

  /// Het token zoals het in het bestand staat.
  String get token => name;

  /// `null` bij een leeg of onbekend token — een status die wij niet
  /// kennen is "geen status", nooit stilletjes `proposed`.
  static MeasureStatus? parse(String raw) {
    switch (raw.trim()) {
      case 'proposed':
        return proposed;
      case 'planned':
        return planned;
      case 'implemented':
        return implemented;
      case 'tested':
        return tested;
      case 'working':
        return working;
      case 'ineffective':
        return ineffective;
    }
    return null;
  }

  /// Of deze status een netto-score mag dragen: alleen een getoetste of
  /// werkende maatregel rechtvaardigt residu-risico (§3.4).
  bool get justifiesNetto => this == tested || this == working;
}

/// De beoordelingsmethoden die `method=` op een `risks`-tabel kan dragen.
enum RiskMethod {
  fmea('fmea'),
  likelihoodImpact('likelihood-impact'),
  bowtie('bowtie');

  final String token;
  const RiskMethod(this.token);

  static RiskMethod? parse(String raw) {
    for (final m in values) {
      if (m.token == raw.trim()) return m;
    }
    return null;
  }
}

/// Eén contractrij uit een `risks`-tabel. Alle accessors lezen op sleutel —
/// kopteksten zijn vrij (§3.2) en zeggen niets over de kolom.
class RiskRecord {
  final Map<String, String> cells;
  const RiskRecord(this.cells);

  String _v(String key) => cells[key]?.trim() ?? '';
  int? _score(String key) => int.tryParse(_v(key));

  String get id => _v('id');
  String get title => _v('title').isEmpty ? _v('failure') : _v('title');
  String get status => _v('status');

  /// De maatregel-ID's die deze rij noemt (`M-001, M-002`); ruwe invoer,
  /// niet gevalideerd — de kwaliteitscontrole toetst of ze bestaan.
  List<String> get measureIds => _idList(_v('measures'));

  // FMEA-velden (§3.3): bruto en netto S-O-D.
  String get step => _v('step');
  String get failure => _v('failure');
  String get effect => _v('effect');
  String get cause => _v('cause');
  String get control => _v('control');
  int? get sB => _score('s_b');
  int? get oB => _score('o_b');
  int? get dB => _score('d_b');
  int? get sN => _score('s_n');
  int? get oN => _score('o_n');
  int? get dN => _score('d_n');

  // Kans × impact-velden (§3.3).
  String get event => _v('event');
  String get consequence => _v('consequence');
  int? get lB => _score('l_b');
  int? get iB => _score('i_b');
  int? get lN => _score('l_n');
  int? get iN => _score('i_n');

  /// De expliciete menselijke grondslag van de netto-score: welke getoetste/
  /// werkende maatregelen, door wie en wanneer herijkt (§3.4). Netto zonder
  /// dit drietal is een kwaliteitsbevinding, geen laag risico.
  String get nettoBasis => _v('netto_basis');
  String get nettoDate => _v('netto_date');
  String get nettoBy => _v('netto_by');
  String get uncertainty => _v('uncertainty');
  String get notes => _v('notes');

  /// Bruto-RPN (S×O×D), afgeleid en dus nooit een contractveld. `null` bij
  /// een incomplete score — "niet berekenbaar", niet `0` (§3.3, #2493).
  int? get rpnBruto {
    final s = sB, o = oB, d = dB;
    return (s == null || o == null || d == null) ? null : s * o * d;
  }

  int? get rpnNetto {
    final s = sN, o = oN, d = dN;
    return (s == null || o == null || d == null) ? null : s * o * d;
  }

  /// Kans × impact, zelfde regel als RPN: compleet of niet berekenbaar.
  int? get scoreBruto {
    final l = lB, i = iB;
    return (l == null || i == null) ? null : l * i;
  }

  int? get scoreNetto {
    final l = lN, i = iN;
    return (l == null || i == null) ? null : l * i;
  }

  /// Of alle bruto-scorevelden die de methode kent gevuld en geldig zijn.
  /// Dekt "onbeoordeeld staat nooit stil op laag" (#2494).
  bool get brutoAssessed => rpnBruto != null || scoreBruto != null;
}

/// Eén contractrij uit een `measures`-tabel (§3.4).
class MeasureRecord {
  final Map<String, String> cells;
  const MeasureRecord(this.cells);

  String _v(String key) => cells[key]?.trim() ?? '';

  String get id => _v('id');
  String get type => _v('type');
  String get description => _v('description');
  String get owner => _v('owner');
  MeasureStatus? get status => MeasureStatus.parse(_v('status'));
  String get evidence => _v('evidence');
  String get testDate => _v('test_date');
  String get expires => _v('expires');
  List<String> get riskIds => _idList(_v('risks'));
  String get notes => _v('notes');
}

/// De ingebouwde schalen die `scale=` op een `risks`-marker kan noemen
/// (§3.5). Een `scale`-tabel in het bestand definieert er een eigen; beide
/// leveren "waarde → label".
class RiskScale {
  final String id;
  final int version;
  final Map<int, String> labels;

  const RiskScale(this.id, this.version, this.labels);

  /// De FMEA-schaal 1–10; labels zijn generiek, de specifieke betekenis
  /// hoort bij S, O of D afzonderlijk en staat in de template-tekst.
  static const sod110 = RiskScale('sod-1-10', 1, {});

  /// De kans × impact-schaal 1–5.
  static const li15 = RiskScale('li-1-5', 1, {});

  /// `null` bij een naam die noch ingebouwd is noch een getal-schaal
  /// impliceert — aangepaste schalen reizen via een `scale`-tabel.
  static RiskScale? builtin(String name) => switch (name) {
    'sod-1-10' => sod110,
    'li-1-5' => li15,
    _ => null,
  };

  /// De schaalbreedte voor validatie: 10 bij `sod-1-10`, 5 bij `li-1-5`,
  /// anders de hoogste `value` in [labels] (0 = onbekend, niet toetsbaar).
  int get max => switch (id) {
    'sod-1-10' => 10,
    'li-1-5' => 5,
    _ => labels.keys.fold(0, (m, v) => v > m ? v : m),
  };
}

/// Eén contractrij uit een `bowtie`-tabel (§3.8): een element op een pad.
class BowtieElement {
  final Map<String, String> cells;
  const BowtieElement(this.cells);

  String _v(String key) => cells[key]?.trim() ?? '';

  String get path => _v('path');
  String get side => _v('side');
  String get role => _v('role');
  String get element => _v('element');
  String get measure => _v('measure');
  String get status => _v('status');
  String get owner => _v('owner');
}

/// `R-001, R-003`-lijsten: komma-gescheiden contract-ID's. Lege en
/// misvormde delen vallen weg — een lijst is een verwijzing, geen proza.
List<String> _idList(String raw) => [
  for (final part in raw.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];
