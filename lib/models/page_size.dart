// ISO-216 paginamaties voor de documentmodus-export (feature 3).
//
// De A-, B- en C-reeksen volgen ISO 216: A(n) heeft een oppervlak van
// 1 m² × 2^(−n−1), B(n) is het geometrisch gemiddelde van A(n) en A(n−1),
// C(n) is het geometrisch gemiddelde van A(n) en B(n). De langste zijde is
// √2 × de kortste (de Lichtenberg-verhouding), en elke snede halveert de
// kortste zijde — vandaar de tabellen hieronder.
//
// De maten zijn in millimeters, afgerond op hele mm (de ISO-216 tolerantie
// is ±1.5 mm voor ≤150 mm, ±2 mm voor ≤600 mm). Een statische lookup-tabel
// volstaat: er zijn maar 11 maten per reeks (0–10), en de wiskunde bij
// export zou floating-point afrondingsverschillen geven die net fout kunnen
// zijn ten opzichte van wat een printer verwacht.

/// De ISO-216 reeks: A (documenten), B (posters/boeken), C (enveloppen).
enum PaperSeries { a, b, c }

/// Een paginamaat uit ISO-216: reeks + nummer + portret/landschap.
class PageSizeSpec {
  final PaperSeries series;
  final int number;
  final bool landscape;

  const PageSizeSpec({
    required this.series,
    required this.number,
    this.landscape = false,
  });

  /// Standaard A4 portret — de meest voorkomende documentmaat.
  static const a4 = PageSizeSpec(series: PaperSeries.a, number: 4);
  static const a4Landscape = PageSizeSpec(
    series: PaperSeries.a,
    number: 4,
    landscape: true,
  );

  /// (breedteMm, hoogteMm) in portret-oriëntatie — bij landscape geruild.
  (double widthMm, double heightMm) get dimensions {
    final (w, h) = _isoDimensions(series, number);
    return landscape ? (h, w) : (w, h);
  }

  /// CSS `@page size`-waarde, bijv. `"A4"` of `"A4 landscape"`.
  String get cssName {
    final base = '${series.name.toUpperCase()}$number';
    return landscape ? '$base landscape' : base;
  }

  /// De `@page size`-waarde inclusief drukkersafloop. Met afloop kan de naam
  /// (`A4`) niet meer: het vel is dan groter dan het snijformaat, dus wordt het
  /// een expliciete maat in millimeters.
  String cssSizeWith(PageMargins margins) {
    if (!margins.hasBleed) return cssName;
    final (w, h) = dimensions;
    final bleed = margins.bleedMm * 2;
    return '${_fmtMm(w + bleed)}mm ${_fmtMm(h + bleed)}mm';
  }

  /// De `geometry`-opties voor de papiermaat inclusief afloop, of `null`
  /// wanneer er geen afloop is — dan volstaat de papiernaam in
  /// `documentclass` ([latexName]).
  String? latexPaperWith(PageMargins margins) {
    if (!margins.hasBleed) return null;
    final (w, h) = dimensions;
    final bleed = margins.bleedMm * 2;
    return 'paperwidth=${_fmtMm(w + bleed)}mm,'
        'paperheight=${_fmtMm(h + bleed)}mm';
  }

  /// LaTeX `documentclass`-papieroptie, bijv. `"a4paper"` of
  /// `"a4paper,landscape"`.
  String get latexName {
    final base = '${series.name.toLowerCase()}${number}paper';
    return landscape ? '$base,landscape' : base;
  }

  /// De maatnaam zonder oriëntatie, bijv. `"A4"`. Taalneutraal met opzet: de
  /// oriëntatie is een wóórd ("liggend"), en dat hoort in de interface door
  /// `l10n.d(…)` te gaan. Een model mag geen BuildContext zien, dus stelt de
  /// aanroeper het label samen uit deze naam plus [landscape].
  String get sizeName => '${series.name.toUpperCase()}$number';

  /// JSON-serialisatie: `"A4"`, `"A4L"`, `"B5"`, etc.
  String get id {
    final base = '${series.name.toUpperCase()}$number';
    return landscape ? '${base}L' : base;
  }

  /// Parse een id terug naar een PageSizeSpec.
  static PageSizeSpec? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    final match = RegExp(r'^([ABC])(\d+)(L?)$').firstMatch(id);
    if (match == null) return null;
    final series = PaperSeries.values.firstWhere(
      (s) => s.name.toUpperCase() == match.group(1),
      orElse: () => PaperSeries.a,
    );
    final number = int.parse(match.group(2)!);
    if (number < 0 || number > 10) return null;
    return PageSizeSpec(
      series: series,
      number: number,
      landscape: match.group(3) == 'L',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PageSizeSpec &&
      series == other.series &&
      number == other.number &&
      landscape == other.landscape;

  @override
  int get hashCode => Object.hash(series, number, landscape);

  @override
  String toString() => 'PageSizeSpec($id)';
}

/// Paginamarges in millimeters. Standaard 25mm boven en onder, 20mm links en
/// rechts — een ruime, leesbare marge die ook bij afdrukken genoeg witruimte
/// laat.
///
/// [bleedMm] is de drukkersmarge: de afloop rondom het uiteindelijke formaat.
/// Een drukker snijdt op maat, en snijdt nooit exact — loopt er inkt tot aan de
/// rand, dan moet die inkt dóór de snijlijn heen lopen, anders staat er een
/// witte streep langs de rand. De pagina wordt daarom bij export
/// `bleedMm` groter aan elke zijde, terwijl de tekstspiegel op zijn plek blijft
/// ten opzichte van het *snijformaat*. 0 (de standaard) betekent gewoon
/// afdrukken op kantoorpapier: geen afloop.
///
/// Snijtekens horen hier op het eerste gezicht bij, maar zitten er bewust
/// niet in. De gedocumenteerde PDF-route van een document is het afdrukken van
/// de HTML-export, en geen browser kent `marks` uit CSS Paged Media; het
/// LaTeX-pad zou het `crop`-pakket nodig hebben, dat niet in elke TeX-opzet
/// zit. Een schakelaar die in geen van beide paden iets doet is erger dan geen
/// schakelaar: de drukker krijgt dan een vergroot vel zonder te weten waar het
/// snijformaat ligt. Komt er een uitvoerpad dat ze wél zet, dan horen ze
/// daarbij terug.
class PageMargins {
  final double topMm;
  final double bottomMm;
  final double leftMm;
  final double rightMm;
  final double bleedMm;

  const PageMargins({
    this.topMm = 25,
    this.bottomMm = 25,
    this.leftMm = 20,
    this.rightMm = 20,
    this.bleedMm = 0,
  });

  /// Uniforme marge in mm rondom, zonder afloop.
  const PageMargins.uniform(double mm)
    : topMm = mm,
      bottomMm = mm,
      leftMm = mm,
      rightMm = mm,
      bleedMm = 0;

  /// Of er een drukkersafloop is gevraagd.
  bool get hasBleed => bleedMm > 0;

  /// Of deze marges semantisch geldig zijn: elk veld eindig en niet-negatief.
  /// `double.tryParse` aanvaardt `'NaN'` en `'Infinity'` als geldige doubles,
  /// dus zonder deze check bereiken oneindige en NaN-waarden de layout.
  bool get isValid =>
      _isFiniteNonNegative(topMm) &&
      _isFiniteNonNegative(bottomMm) &&
      _isFiniteNonNegative(leftMm) &&
      _isFiniteNonNegative(rightMm) &&
      _isFiniteNonNegative(bleedMm);

  static bool _isFiniteNonNegative(double v) => v.isFinite && v >= 0;

  /// CSS `@page margin`-waarde, bijv. `"25mm 20mm 25mm 20mm"`.
  ///
  /// Met afloop telt die aan elke zijde bij de marge op: het vel is dan
  /// `bleedMm` groter rondom, dus de tekstspiegel moet net zoveel opschuiven om
  /// op dezelfde plek ten opzichte van het snijformaat te blijven staan.
  String get cssMargin =>
      '${_fmtMm(topMm + bleedMm)}mm ${_fmtMm(rightMm + bleedMm)}mm '
      '${_fmtMm(bottomMm + bleedMm)}mm ${_fmtMm(leftMm + bleedMm)}mm';

  /// LaTeX `geometry`-pakket opties, bijv.
  /// `"top=25mm,bottom=25mm,left=20mm,right=20mm"`. Met afloop schuift de
  /// tekstspiegel mee, net als in [cssMargin].
  String get latexMargin =>
      'top=${_fmtMm(topMm + bleedMm)}mm,bottom=${_fmtMm(bottomMm + bleedMm)}mm,'
      'left=${_fmtMm(leftMm + bleedMm)}mm,right=${_fmtMm(rightMm + bleedMm)}mm';

  /// JSON-serialisatie als `"25,25,20,20"` (boven,onder,links,rechts), met bij
  /// een gevraagde afloop een vijfde veld: `"25,25,20,20,3"`. De korte vorm
  /// blijft leesbaar voor wie geen afloop gebruikt, en oudere opgeslagen
  /// waarden blijven gewoon werken.
  String get id {
    final base =
        '${_fmtMm(topMm)},${_fmtMm(bottomMm)},'
        '${_fmtMm(leftMm)},${_fmtMm(rightMm)}';
    return hasBleed ? '$base,${_fmtMm(bleedMm)}' : base;
  }

  PageMargins copyWith({
    double? topMm,
    double? bottomMm,
    double? leftMm,
    double? rightMm,
    double? bleedMm,
  }) => PageMargins(
    topMm: topMm ?? this.topMm,
    bottomMm: bottomMm ?? this.bottomMm,
    leftMm: leftMm ?? this.leftMm,
    rightMm: rightMm ?? this.rightMm,
    bleedMm: bleedMm ?? this.bleedMm,
  );

  /// Parse een id terug naar PageMargins.
  static PageMargins? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    final parts = id.split(',');
    // Vier velden is de gewone vorm; vijf betekent dat er een afloop bij staat.
    // Zes komt uit een korte periode waarin er ook een snijtekens-vlag stond —
    // die lezen we nog wél, zodat een opgeslagen waarde niet stil terugvalt op
    // de standaardmarges, maar het zesde veld doet niets meer.
    if (parts.length < 4 || parts.length > 6) return null;
    final vals = parts.map((p) => double.tryParse(p)).toList();
    if (vals.any((v) => v == null)) return null;
    final m = PageMargins(
      topMm: vals[0]!,
      bottomMm: vals[1]!,
      leftMm: vals[2]!,
      rightMm: vals[3]!,
      bleedMm: vals.length > 4 ? vals[4]! : 0,
    );
    // Negatieve, NaN- of oneindige waarden horen niet in opgeslagen marges:
    // ze bereiken de layout als negatieve of oneindige maten en crashen de
    // paginering. Val terug op de standaardmarge in plaats van ze te erven.
    return m.isValid ? m : null;
  }

  @override
  bool operator ==(Object other) =>
      other is PageMargins &&
      topMm == other.topMm &&
      bottomMm == other.bottomMm &&
      leftMm == other.leftMm &&
      rightMm == other.rightMm &&
      bleedMm == other.bleedMm;

  @override
  int get hashCode => Object.hash(topMm, bottomMm, leftMm, rightMm, bleedMm);

  @override
  String toString() => 'PageMargins($id)';
}

/// ISO-216 afmetingen in mm (portret) voor reeks A, B, C, nummers 0–10.
/// Bron: ISO 216:2007. Afgerond op hele mm.
(double widthMm, double heightMm) _isoDimensions(PaperSeries series, int n) {
  const a = [
    (841.0, 1189.0),
    (594.0, 841.0),
    (420.0, 594.0),
    (297.0, 420.0),
    (210.0, 297.0),
    (148.0, 210.0),
    (105.0, 148.0),
    (74.0, 105.0),
    (52.0, 74.0),
    (37.0, 52.0),
    (26.0, 37.0),
  ];
  const b = [
    (1000.0, 1414.0),
    (707.0, 1000.0),
    (500.0, 707.0),
    (353.0, 500.0),
    (250.0, 353.0),
    (176.0, 250.0),
    (125.0, 176.0),
    (88.0, 125.0),
    (62.0, 88.0),
    (44.0, 62.0),
    (31.0, 44.0),
  ];
  const c = [
    (917.0, 1297.0),
    (648.0, 917.0),
    (458.0, 648.0),
    (324.0, 458.0),
    (229.0, 324.0),
    (162.0, 229.0),
    (114.0, 162.0),
    (81.0, 114.0),
    (57.0, 81.0),
    (40.0, 57.0),
    (28.0, 40.0),
  ];
  final table = switch (series) {
    PaperSeries.a => a,
    PaperSeries.b => b,
    PaperSeries.c => c,
  };
  if (n < 0 || n >= table.length) return a[4]; // val terug op A4
  return table[n];
}

/// Format een mm-waarde zonder onnodige `.0` — `25.0` → `"25"`, `25.5` → `"25.5"`.
String _fmtMm(double mm) =>
    mm == mm.roundToDouble() ? mm.round().toString() : mm.toString();

/// Of [margins] binnen het vel [size] passen met een veilige minimum-
/// tekstspiegel van [minContentMm] mm. Marges die samen breder of hoger
/// zijn dan het papier leveren een negatieve content-maat op, die
/// Flutter-layoutconstraints en pagineringsberekeningen laat crashen of
/// vastlopen. De drempel van 10 mm is royaal — een vel waar minder dan
/// een centimeter tekst op past is onbruikbaar, hoe dan ook.
bool marginsFitPaper(
  PageSizeSpec size,
  PageMargins margins, {
  double minContentMm = 10,
}) {
  final (w, h) = size.dimensions;
  return margins.leftMm + margins.rightMm <= w - minContentMm &&
      margins.topMm + margins.bottomMm <= h - minContentMm;
}
