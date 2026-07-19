// Reis- en identiteitsdocumenten: de machine-readable zone.
//
// Dit is de gelukkigste regel uit de hele catalogus. Een MRZ is twee of drie
// regels van een vaste lengte uit een alfabet van 37 tekens, met vier
// controlecijfers erin verweven — waaronder één die over de andere heen ligt.
// De kans dat gewone tekst daar per ongeluk doorheen komt is verwaarloosbaar, en
// dat betekent dat deze regel meteen `certain` mag zijn zonder contextwoord,
// zonder nabijheidseis en zonder enige verdere poort.
//
// En de betekenis is navenant: een MRZ op een slide is geen persoonsgegeven dat
// er toevallig in geslopen is. Het is een gescand paspoort of identiteitsbewijs.
// Er staat een documentnummer in, een nationaliteit, een geboortedatum, een
// geslacht en een vervaldatum — de complete set waarmee identiteitsfraude begint.
//
// Drie formaten, alle drie uit ICAO 9303:
//
//   * **TD1** — identiteitskaart: drie regels van 30;
//   * **TD2** — het oudere kaartformaat: twee regels van 36;
//   * **TD3** — paspoort: twee regels van 44.
//
// De naamregel valideren we niet: die bevat geen controlecijfer en bestaat
// volledig uit letters en vulteken. Wat we wél eisen is dat élk controlecijfer
// klopt, inclusief het samengestelde. Eén cijfer mis en de treffer vervalt —
// liever een gemiste scan dan een scanner die op elke tabel met hoofdletters
// "paspoort!" roept.

/// De positie van een gevonden MRZ binnen een tekstfragment.
typedef MrzZone = ({int start, int end});

/// De gewichten van de ICAO-controlecijferformule, cyclisch: 7, 3, 1, 7, 3, 1, …
const List<int> _mrzWeights = [7, 3, 1];

/// De waarde van één MRZ-teken: cijfers zichzelf, letters 10 tot 35, het
/// vulteken `<` nul. Alles daarbuiten hoort niet in een MRZ en levert `null`.
int? _mrzValue(int unit) {
  if (unit == 0x3C) return 0; // '<'
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  if (unit >= 0x41 && unit <= 0x5A) return unit - 0x41 + 10;
  return null;
}

/// Het ICAO-controlecijfer over [field], of `null` bij een ongeldig teken.
int? mrzCheckDigit(String field) {
  var sum = 0;
  for (var i = 0; i < field.length; i++) {
    final value = _mrzValue(field.codeUnitAt(i));
    if (value == null) return null;
    sum += value * _mrzWeights[i % 3];
  }
  return sum % 10;
}

/// Klopt het controlecijfer [check] bij [field]?
///
/// Een `<` op de plek van het controlecijfer is toegestaan wanneer het veld zelf
/// helemaal uit vultekens bestaat — zo vullen sommige uitgevers een ongebruikt
/// veld. Verder moet er een echt cijfer staan dat exact uitkomt.
bool _checkOk(String field, String check) {
  if (check == '<') return field.split('').every((c) => c == '<');
  final expected = mrzCheckDigit(field);
  if (expected == null) return false;
  return check == '$expected';
}

/// Een MRZ-datum: `JJMMDD`, met een maand 01-12 en een dag 01-31.
///
/// Geen kalenderprecisie (schrikkeljaren, maandlengtes) — het doel is niet de
/// datum te valideren maar zes willekeurige cijfers uit te sluiten, en daarvoor
/// is dit genoeg.
bool _validMrzDate(String value) {
  if (value.length != 6) return false;
  final month = int.tryParse(value.substring(2, 4));
  final day = int.tryParse(value.substring(4, 6));
  if (month == null || day == null) return false;
  if (int.tryParse(value.substring(0, 2)) == null) return false;
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

/// Alleen MRZ-tekens, en precies [length] ervan.
bool _isMrzLine(String line, int length) {
  if (line.length != length) return false;
  for (var i = 0; i < length; i++) {
    if (_mrzValue(line.codeUnitAt(i)) == null) return false;
  }
  return true;
}

/// TD3 — het paspoort. Twee regels van 44; de gegevens staan op de tweede.
///
/// Indeling van regel 2: documentnummer (0-8) + controle (9), nationaliteit
/// (10-12), geboortedatum (13-18) + controle (19), geslacht (20), vervaldatum
/// (21-26) + controle (27), persoonsnummer (28-41) + controle (42), en tot slot
/// het samengestelde controlecijfer (43) dat over al die velden tegelijk ligt.
bool _validTd3(String line1, String line2) {
  if (!line1.startsWith('P')) return false;
  if (!_checkOk(line2.substring(0, 9), line2[9])) return false;
  if (!_validMrzDate(line2.substring(13, 19))) return false;
  if (!_checkOk(line2.substring(13, 19), line2[19])) return false;
  if (!_validMrzDate(line2.substring(21, 27))) return false;
  if (!_checkOk(line2.substring(21, 27), line2[27])) return false;
  final composite =
      line2.substring(0, 10) +
      line2.substring(13, 20) +
      line2.substring(21, 43);
  return _checkOk(composite, line2[43]);
}

/// TD2 — het oudere kaartformaat. Twee regels van 36, gegevens op de tweede.
bool _validTd2(String line2) {
  if (!_checkOk(line2.substring(0, 9), line2[9])) return false;
  if (!_validMrzDate(line2.substring(13, 19))) return false;
  if (!_checkOk(line2.substring(13, 19), line2[19])) return false;
  if (!_validMrzDate(line2.substring(21, 27))) return false;
  if (!_checkOk(line2.substring(21, 27), line2[27])) return false;
  final composite =
      line2.substring(0, 10) +
      line2.substring(13, 20) +
      line2.substring(21, 35);
  return _checkOk(composite, line2[35]);
}

/// TD1 — de identiteitskaart. Drie regels van 30, verdeeld over de eerste twee.
///
/// Anders dan bij TD2 en TD3 staat het documentnummer op regel 1, en beslaat het
/// samengestelde controlecijfer daarom stukken uit beide regels.
bool _validTd1(String line1, String line2) {
  if (!_checkOk(line1.substring(5, 14), line1[14])) return false;
  if (!_validMrzDate(line2.substring(0, 6))) return false;
  if (!_checkOk(line2.substring(0, 6), line2[6])) return false;
  if (!_validMrzDate(line2.substring(8, 14))) return false;
  if (!_checkOk(line2.substring(8, 14), line2[14])) return false;
  final composite =
      line1.substring(5, 30) +
      line2.substring(0, 7) +
      line2.substring(8, 15) +
      line2.substring(18, 29);
  return _checkOk(composite, line2[29]);
}

/// Zoekt machine-readable zones in [text].
///
/// Werkt regelgewijs in plaats van met één grote regex: een MRZ is per definitie
/// een blok opeenvolgende regels, en de posities die we teruggeven moeten in het
/// oorspronkelijke fragment kloppen omdat de redactie ze gebruikt.
Iterable<MrzZone> findMrzZones(String text) sync* {
  if (!text.contains('<')) return;

  final lines = <({int start, int end, String value})>[];
  var offset = 0;
  for (final line in text.split('\n')) {
    lines.add((start: offset, end: offset + line.length, value: line.trim()));
    offset += line.length + 1;
  }

  var i = 0;
  while (i < lines.length) {
    final matched = _matchAt(lines, i);
    if (matched == null) {
      i++;
      continue;
    }
    yield (start: lines[i].start, end: lines[i + matched - 1].end);
    i += matched;
  }
}

/// Hoeveel regels de MRZ beslaat die op [i] begint, of `null` als er geen staat.
int? _matchAt(List<({int start, int end, String value})> lines, int i) {
  final first = lines[i].value;

  if (i + 1 < lines.length) {
    final second = lines[i + 1].value;
    if (_isMrzLine(first, 44) &&
        _isMrzLine(second, 44) &&
        _validTd3(first, second)) {
      return 2;
    }
    if (_isMrzLine(first, 36) && _isMrzLine(second, 36) && _validTd2(second)) {
      return 2;
    }
    if (i + 2 < lines.length &&
        _isMrzLine(first, 30) &&
        _isMrzLine(second, 30) &&
        _isMrzLine(lines[i + 2].value, 30) &&
        _validTd1(first, second)) {
      return 3;
    }
  }
  return null;
}
