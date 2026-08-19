import 'inline_markdown.dart' show stripInlineMarkdown;

/// Vertaalt een cursorpositie heen en weer tussen de Markdown-bron en de platte
/// tekst van de visuele (rijke-tekst) editor.
///
/// Wisselen van stand is precies de handeling die je doet omdat je op één plek
/// iets in de bron wilt zien of zetten. Zonder deze vertaling begon je aan de
/// andere kant weer bovenaan en moest je je plek opnieuw zoeken (#1566).
///
/// De kaart werkt per regel, want zo staat de tekst er aan beide kanten in: de
/// visuele editor zet elk blok op een eigen regel, laat lege bronregels weg, en
/// vervangt een tabel, een scheidingslijn of een afbeelding door één
/// objectteken. Binnen een regel wordt geteld met dezelfde inline-ontleder die
/// de weergave gebruikt ([stripInlineMarkdown]), zodat `**vet**` aan de ene kant
/// vier tekens langer is dan aan de andere en de kolom toch klopt.
///
/// Precisie tot op het teken is niet het doel en niet altijd haalbaar — sta je
/// middenin een opmaakteken, dan landt de cursor aan het begin daarvan. De
/// regel en het woord kloppen, en dat is wat "dezelfde plek" betekent.
class MarkdownCaretMap {
  MarkdownCaretMap._(this._rows, this.visualLength);

  final List<_Row> _rows;

  /// De lengte van de platte tekst waar deze kaart naartoe vertaalt.
  final int visualLength;

  /// Bouwt de kaart voor [source] — de body van het document, zonder
  /// frontmatter, precies zoals de editor hem in handen heeft.
  factory MarkdownCaretMap.of(String source) {
    final lines = source.split('\n');
    final rows = <_Row>[];
    var sourceAt = 0;
    var visualAt = 0;
    var fenced = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final start = sourceAt;
      sourceAt += line.length + 1; // +1 voor het regeleinde

      if (_fencePattern.hasMatch(line)) {
        fenced = !fenced;
        rows.add(_Row.hidden(start, line.length, visualAt));
        continue;
      }
      if (fenced) {
        // In een codeblok staat er letterlijk wat er staat.
        rows.add(_Row.text(start, line.length, 0, line, visualAt));
        visualAt += line.length + 1;
        continue;
      }
      if (line.trim().isEmpty) {
        rows.add(_Row.hidden(start, line.length, visualAt));
        continue;
      }
      if (_rulePattern.hasMatch(line)) {
        rows.add(_Row.object(start, line.length, visualAt));
        visualAt += 2; // het objectteken plus zijn regeleinde
        continue;
      }
      if (_tableRowPattern.hasMatch(line)) {
        // Een tabel is aan de visuele kant één blok: alleen de eerste regel
        // ervan draagt het objectteken, de rest telt niet mee.
        final firstOfTable = i == 0 || !_tableRowPattern.hasMatch(lines[i - 1]);
        if (firstOfTable) {
          rows.add(_Row.object(start, line.length, visualAt));
          visualAt += 2;
        } else {
          rows.add(_Row.hidden(start, line.length, visualAt));
        }
        continue;
      }

      final skip = _blockMarkerLength(line);
      final body = line.substring(skip);
      final visible = stripInlineMarkdown(body);
      rows.add(_Row.text(start, line.length, skip, body, visualAt));
      visualAt += visible.length + 1;
    }
    return MarkdownCaretMap._(rows, visualAt);
  }

  /// De positie in de platte tekst die hoort bij [sourceOffset].
  int visualOffsetOf(int sourceOffset) {
    if (_rows.isEmpty) return 0;
    final row = _rowForSource(sourceOffset);
    return row.visualStart + row.visualColumnOf(sourceOffset);
  }

  /// De positie in de bron die hoort bij [visualOffset].
  int sourceOffsetOf(int visualOffset) {
    if (_rows.isEmpty) return 0;
    final row = _rowForVisual(visualOffset);
    return row.sourceStart + row.sourceColumnOf(visualOffset - row.visualStart);
  }

  _Row _rowForSource(int offset) {
    for (final row in _rows) {
      if (offset <= row.sourceStart + row.sourceLength) return row;
    }
    return _rows.last;
  }

  /// De regel waarin [offset] in de platte tekst valt.
  ///
  /// Lege bronregels leveren niets op en beginnen dus op dezelfde plek als de
  /// regel erna; van die twee wint de regel die er echt tekst zet.
  _Row _rowForVisual(int offset) {
    var best = _rows.first;
    var gevonden = false;
    for (final row in _rows) {
      if (row.visualStart > offset) break;
      if (row.visualLength > 0) {
        best = row;
        gevonden = true;
      } else if (!gevonden) {
        best = row;
      }
    }
    return best;
  }

  static final _fencePattern = RegExp(r'^\s*```');
  static final _rulePattern = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');
  static final _tableRowPattern = RegExp(r'^\s*\|');

  /// De lengte van het blokteken vooraan [line] — hekjes, aanhaalteken,
  /// opsommingsstreepje of nummer. Dat teken staat niet in de platte tekst.
  static int _blockMarkerLength(String line) {
    var at = 0;
    var moved = true;
    while (moved) {
      moved = false;
      final rest = line.substring(at);
      final match = _markerPattern.matchAsPrefix(rest);
      if (match != null) {
        at += match.end;
        moved = true;
      }
    }
    return at;
  }

  static final _markerPattern = RegExp(
    r'^(\s*(#{1,6}\s+|>\s?|[-*+]\s+|\d+[.)]\s+|\[[ xX]\]\s+))',
  );
}

/// Eén bronregel en zijn plek in de platte tekst.
class _Row {
  _Row.hidden(this.sourceStart, this.sourceLength, this.visualStart)
    : sourceSkip = 0,
      body = '',
      visible = '',
      object = false;

  _Row.object(this.sourceStart, this.sourceLength, this.visualStart)
    : sourceSkip = 0,
      body = '',
      visible = '',
      object = true;

  _Row.text(
    this.sourceStart,
    this.sourceLength,
    this.sourceSkip,
    this.body,
    this.visualStart,
  ) : visible = stripInlineMarkdown(body),
      object = false;

  final int sourceStart;
  final int sourceLength;

  /// Hoeveel tekens vooraan de regel niet in de platte tekst staan.
  final int sourceSkip;

  /// De regel zonder dat blokteken.
  final String body;

  /// Diezelfde regel zonder opmaaktekens: wat de visuele editor toont.
  final String visible;

  final int visualStart;

  /// Of deze regel aan de visuele kant één objectteken is (tabel, lijn).
  final bool object;

  int get visualLength => object ? 1 : visible.length;

  /// Voor elke positie in [body]: hoeveel zichtbare tekens eraan voorafgaan.
  ///
  /// De zichtbare tekst is altijd een *deelrij* van de bronregel — opmaak haalt
  /// tekens weg (`**`, backticks, de doelen van een link) maar voegt er nooit
  /// een toe. Eén keer samen doorlopen levert daarom een exacte kaart op, ook
  /// midden in `**vet**`, waar tellen-met-een-voorvoegsel de losse sterretjes
  /// nog voor tekst aanzag.
  late final List<int> _steps = () {
    final steps = List<int>.filled(body.length + 1, 0);
    var seen = 0;
    for (var i = 0; i < body.length; i++) {
      steps[i] = seen;
      if (seen < visible.length && body[i] == visible[seen]) seen++;
    }
    steps[body.length] = seen;
    return steps;
  }();

  /// De kolom in de platte tekst voor een positie in deze bronregel.
  int visualColumnOf(int sourceOffset) {
    if (object || body.isEmpty) return 0;
    final column = (sourceOffset - sourceStart - sourceSkip).clamp(
      0,
      body.length,
    );
    return _steps[column];
  }

  /// De positie in deze bronregel voor een kolom in de platte tekst.
  ///
  /// Gezocht wordt de plek *vlak vóór het zichtbare teken*, niet de eerste plek
  /// met het juiste aantal tekens ervoor: die eerste plek ligt bij `**vet**` nog
  /// vóór de sterretjes, en dan begon je met typen middenin het opmaakteken.
  int sourceColumnOf(int visualColumn) {
    if (object || body.isEmpty) return sourceSkip;
    for (var column = 0; column <= body.length; column++) {
      if (_steps[column] < visualColumn) continue;
      if (column == body.length || _steps[column + 1] > _steps[column]) {
        return sourceSkip + column;
      }
    }
    return sourceSkip + body.length;
  }
}
