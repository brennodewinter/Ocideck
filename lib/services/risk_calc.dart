/// De begrensde formuletaal uit RISK_FORMAT §3.7 en #2491: een `calc`-
/// marker op een gemarkeerde tabel noemt een afgeleide kolom (`col=`) en
/// haar berekening (`expr=`); de cel bewaart de laatst berekende waarde
/// zodat elke lezer een getal ziet.
///
/// De hele taal: decimale literalen, `+ - * / ( )`, kolomsleutels (`s_n`),
/// rij-verwijzingen (`s_n@R-001`) en de aggregaten `sum avg min max count
/// wsum`. Geen code-evaluatie, geen netwerk, geen verborgen bestandslezing.
/// 'Onbekend' is nooit `0`: lege of onleesbare invoer, deling door nul,
/// overflow en cycli leveren een leeg resultaat op plus een bevinding voor
/// de kwaliteitscontrole — de cel toont dan `—`.
library;

import 'ocideck_marked_table.dart';
import 'ocideck_markers.dart';

/// De geldende aggregaat-functies (§3.7). Alles daarbuiten parseert al
/// niet — zo blijft "geen willekeurige code" een parsefout, geen
/// runtimedwing.
const _aggregateNames = {'sum', 'avg', 'min', 'max', 'count', 'wsum'};

/// Foutcodes zoals de kwaliteitscontrole (#2490) ze rapporteert.
class CalcErrors {
  static const divZero = 'calc-div-zero';
  static const cycle = 'calc-cycle';
  static const overflow = 'calc-overflow';
  static const invalid = 'calc-invalid';
}

/// De uitkomst van één berekende cel.
class OciCalcResult {
  /// `null` = onbekend (lege invoer, deling door nul, cyclus, overflow) —
  /// rendert als `—`, nooit als `0`.
  final double? value;

  /// De foutcode voor de kwaliteitscontrole; `null` bij een schone
  /// berekening én bij onbekend-door-lege-invoer (dat is data, geen fout).
  final String? error;

  const OciCalcResult(this.value, this.error);
}

/// Eén `calc`-marker als definitie.
class OciCalcDef {
  final String col;
  final String expr;
  final OciTableMarker marker;
  const OciCalcDef({
    required this.col,
    required this.expr,
    required this.marker,
  });
}

/// De `calc`-definities die op [table] gestapeld zijn, in marker-volgorde.
List<OciCalcDef> ociCalcDefs(OciMarkedTable table) => [
  for (final m in table.calcMarkers)
    OciCalcDef(col: m.attr('col') ?? '', expr: m.attr('expr') ?? '', marker: m),
];

// ---------------------------------------------------------------------------
// Parser — recursieve afdaling over de grammatica uit §3.7.
//   expr    := term (('+'|'-') term)*
//   term    := factor (('*'|'/') factor)*
//   factor  := '-' factor | primary
//   primary := num | ident | ident '@' rowid | func '(' arglist ')' | '(' expr ')'
//   arglist := ident (',' ident)*        (alleen kolomsleutels, §3.7)
// ---------------------------------------------------------------------------

sealed class _Expr {
  const _Expr();
}

class _Num extends _Expr {
  final double v;
  const _Num(this.v);
}

class _ColRef extends _Expr {
  final String key;
  final String? rowId; // null = huidige rij; anders `key@rowId`.
  const _ColRef(this.key, this.rowId);
}

class _Bin extends _Expr {
  final String op;
  final _Expr l, r;
  const _Bin(this.op, this.l, this.r);
}

class _Neg extends _Expr {
  final _Expr e;
  const _Neg(this.e);
}

class _Agg extends _Expr {
  final String fn;
  final List<String> keys;
  const _Agg(this.fn, this.keys);
}

/// `null` als [expr] geen geldige §3.7-expressie is — de marker blijft dan
/// bewaard commentaar met een `calc-invalid`-bevinding, nooit stil
/// genegeerd en nooit als `0` doorgeleverd.
_Expr? _parseCalc(String expr) {
  final tokens = _tokenizeCalc(expr);
  if (tokens == null) return null;
  final parser = _CalcParser(tokens);
  final node = parser.expr();
  if (node == null || !parser.atEnd) return null;
  return node;
}

sealed class _Tok {
  const _Tok();
}

class _TNum extends _Tok {
  final double v;
  const _TNum(this.v);
}

class _TIdent extends _Tok {
  final String s;
  const _TIdent(this.s);
}

class _TOp extends _Tok {
  final String s;
  const _TOp(this.s);
}

List<_Tok>? _tokenizeCalc(String s) {
  final out = <_Tok>[];
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == ' ' || c == '\t') {
      i++;
      continue;
    }
    final code = c.codeUnitAt(0);
    if (code >= 48 && code <= 57 || c == '.') {
      // Decimale literaal: cijfers met hoogstens één punt.
      var j = i;
      var dot = false;
      while (j < s.length) {
        final ch = s[j];
        if (ch == '.') {
          if (dot) break;
          dot = true;
          j++;
          continue;
        }
        final cc = ch.codeUnitAt(0);
        if (cc < 48 || cc > 57) break;
        j++;
      }
      final raw = s.substring(i, j);
      final v = double.tryParse(raw);
      if (v == null) return null;
      out.add(_TNum(v));
      i = j;
      continue;
    }
    if (RegExp(r'[A-Za-z_]').hasMatch(c)) {
      var j = i;
      while (j < s.length && RegExp(r'[A-Za-z0-9_-]').hasMatch(s[j])) {
        j++;
      }
      out.add(_TIdent(s.substring(i, j)));
      i = j;
      continue;
    }
    if ('+-*/(),@'.contains(c)) {
      out.add(_TOp(c));
      i++;
      continue;
    }
    return null; // geen ander teken hoort in de taal
  }
  return out;
}

class _CalcParser {
  final List<_Tok> tokens;
  var _i = 0;
  _CalcParser(this.tokens);

  bool get atEnd => _i >= tokens.length;
  _Tok? get _peek => atEnd ? null : tokens[_i];
  bool _eat(String op) {
    if (_peek is _TOp && (_peek as _TOp).s == op) {
      _i++;
      return true;
    }
    return false;
  }

  _Expr? expr() {
    var left = term();
    if (left == null) return null;
    while (true) {
      if (_eat('+')) {
        final r = term();
        if (r == null) return null;
        left = _Bin('+', left!, r);
      } else if (_eat('-')) {
        final r = term();
        if (r == null) return null;
        left = _Bin('-', left!, r);
      } else {
        return left;
      }
    }
  }

  _Expr? term() {
    var left = factor();
    if (left == null) return null;
    while (true) {
      if (_eat('*')) {
        final r = factor();
        if (r == null) return null;
        left = _Bin('*', left!, r);
      } else if (_eat('/')) {
        final r = factor();
        if (r == null) return null;
        left = _Bin('/', left!, r);
      } else {
        return left;
      }
    }
  }

  _Expr? factor() {
    if (_eat('-')) {
      final e = factor();
      return e == null ? null : _Neg(e);
    }
    return primary();
  }

  _Expr? primary() {
    final t = _peek;
    if (t is _TNum) {
      _i++;
      return _Num(t.v);
    }
    if (_eat('(')) {
      final e = expr();
      if (e == null || !_eat(')')) return null;
      return e;
    }
    if (t is _TIdent) {
      _i++;
      final name = t.s;
      if (_eat('@')) {
        final id = _peek;
        if (id is! _TIdent) return null;
        _i++;
        return _ColRef(name, id.s);
      }
      if (_eat('(')) {
        if (!_aggregateNames.contains(name)) return null;
        final keys = <String>[];
        while (true) {
          final k = _peek;
          if (k is! _TIdent) return null;
          _i++;
          keys.add(k.s);
          if (_eat(',')) continue;
          break;
        }
        // sum/avg/min/max/count: één sleutel; wsum: waarde + gewicht.
        final want = name == 'wsum' ? 2 : 1;
        if (keys.length != want || !_eat(')')) return null;
        return _Agg(name, keys);
      }
      return _ColRef(name, null);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Evaluator — met memo + bezoekverzameling voor de cyclusregel.
// ---------------------------------------------------------------------------

/// De context waarin één tabel rekent: contractrijen, `id`-lookup en de
/// calc-kolommen die zelf nog uitgerekend kunnen worden.
class _CalcContext {
  final List<Map<String, String>> rows;
  final Map<String, int> rowIndexById;
  final Map<String, OciCalcDef> calcByCol;

  /// Memo per `rij#kolom` + de bezoekverzameling — die samen maken de
  /// cyclus zichtbaar zonder oneindige recursie.
  final Map<String, OciCalcResult> _memo = {};
  final Set<String> _visiting = {};
  bool cycleSeen = false;

  _CalcContext(this.rows, this.rowIndexById, this.calcByCol);

  /// De waarde van contractkolom [key] op rij [rowIdx]: de opgeslagen cel
  /// tenzij het een calc-kolom is — die rekenen we (recursief) uit.
  OciCalcResult cellValue(int rowIdx, String key) {
    final calc = calcByCol[key];
    if (calc == null) {
      final raw = rows[rowIdx][key]?.trim() ?? '';
      if (raw.isEmpty) return const OciCalcResult(null, null);
      final v = double.tryParse(raw);
      return v == null
          ? const OciCalcResult(null, null)
          : OciCalcResult(v, null);
    }
    final memoKey = '$rowIdx#$key';
    final memo = _memo[memoKey];
    if (memo != null) return memo;
    if (!_visiting.add(memoKey)) {
      cycleSeen = true;
      return const OciCalcResult(null, CalcErrors.cycle);
    }
    final result = _evalCalc(rowIdx, calc);
    _visiting.remove(memoKey);
    _memo[memoKey] = result;
    return result;
  }

  OciCalcResult _evalCalc(int rowIdx, OciCalcDef def) {
    final tree = _parseCalc(def.expr);
    if (tree == null) {
      return const OciCalcResult(null, CalcErrors.invalid);
    }
    final out = _eval(tree, rowIdx);
    if (out.error != null || out.value == null) return out;
    final v = out.value!;
    if (!v.isFinite || v.abs() > 1e15) {
      return const OciCalcResult(null, CalcErrors.overflow);
    }
    return out;
  }

  OciCalcResult _eval(_Expr e, int rowIdx) {
    const unknown = OciCalcResult(null, null);
    switch (e) {
      case _Num(:final v):
        return OciCalcResult(v, null);
      case _Neg(:final e):
        final r = _eval(e, rowIdx);
        return r.value == null
            ? OciCalcResult(null, r.error)
            : OciCalcResult(-r.value!, r.error);
      case _ColRef(:final key, :final rowId):
        final target = rowId == null ? rowIdx : rowIndexById[rowId];
        if (target == null) return unknown;
        return cellValue(target, key);
      case _Bin(:final op, :final l, :final r):
        final lv = _eval(l, rowIdx);
        if (lv.error != null) return lv;
        final rv = _eval(r, rowIdx);
        if (rv.error != null) return rv;
        if (lv.value == null || rv.value == null) return unknown;
        if (op == '/' && rv.value == 0) {
          return const OciCalcResult(null, CalcErrors.divZero);
        }
        final v = switch (op) {
          '+' => lv.value! + rv.value!,
          '-' => lv.value! - rv.value!,
          '*' => lv.value! * rv.value!,
          '/' => lv.value! / rv.value!,
          _ => 0.0,
        };
        return OciCalcResult(v, null);
      case _Agg(:final fn, :final keys):
        // Een aggregaat over de kolom waar we zelf in rekenen is een
        // cyclus per definitie.
        if (keys.any(calcByCol.containsKey)) {
          cycleSeen = true;
          return const OciCalcResult(null, CalcErrors.cycle);
        }
        final values = <double>[];
        for (var i = 0; i < rows.length; i++) {
          final r = cellValue(i, keys.first);
          if (r.error != null) return r;
          if (r.value != null) values.add(r.value!);
        }
        if (fn == 'count') {
          return OciCalcResult(values.length.toDouble(), null);
        }
        if (values.isEmpty) return unknown;
        final v = switch (fn) {
          'sum' => values.fold(0.0, (a, b) => a + b),
          'avg' => values.fold(0.0, (a, b) => a + b) / values.length,
          'min' => values.fold(values.first, (a, b) => b < a ? b : a),
          'max' => values.fold(values.first, (a, b) => b > a ? b : a),
          'wsum' => _weightedSum(keys, rows, this),
          _ => 0.0,
        };
        if (v == null) return unknown;
        return OciCalcResult(v, null);
    }
  }
}

double? _weightedSum(
  List<String> keys,
  List<Map<String, String>> rows,
  _CalcContext ctx,
) {
  var acc = 0.0;
  var any = false;
  for (var i = 0; i < rows.length; i++) {
    final v = ctx.cellValue(i, keys[0]);
    final w = ctx.cellValue(i, keys[1]);
    if (v.error != null || w.error != null) return null;
    if (v.value == null || w.value == null) continue;
    acc += v.value! * w.value!;
    any = true;
  }
  return any ? acc : null;
}

/// De volledige tabel-evaluatie: per body-rij, per calc-definitie de
/// uitkomst. `cycleSeen` rapporteert óf er ergens een cyclus in het
/// afhankelijkheidsweb zat — ook waar de memo hem al opving.
class OciCalcTableResult {
  /// [results][rij][def-idx] — `null` waarde = onbekend, rendert `—`.
  final List<List<OciCalcResult>> results;
  final bool cycleSeen;
  const OciCalcTableResult(this.results, this.cycleSeen);
}

/// Rekent álle calc-definities van [table] uit over álle body-rijen.
/// Verwijzingen volgen contract-ID's en kolomsleutels — sorteren of een
/// rij invoegen her-richt nooit een formule (§3.7).
OciCalcTableResult evaluateOciTableCalc(OciMarkedTable table) {
  final defs = ociCalcDefs(table);
  final rows = table.contractRows;
  final byId = <String, int>{
    for (var i = 0; i < rows.length; i++)
      if ((rows[i]['id'] ?? '').trim().isNotEmpty) rows[i]['id']!.trim(): i,
  };
  final ctx = _CalcContext(rows, byId, {
    for (final d in defs)
      if (d.col.isNotEmpty) d.col: d,
  });
  final results = <List<OciCalcResult>>[
    for (var r = 0; r < rows.length; r++)
      [for (final d in defs) ctx._evalCalc(r, d)],
  ];
  return OciCalcTableResult(results, ctx.cycleSeen);
}

/// Of de expressie van [marker] überhaupt parseert — de snelle toets voor
/// de kwaliteitscontrole zonder evaluatie.
bool ociCalcExprParses(OciTableMarker marker) =>
    _parseCalc(marker.attr('expr') ?? '') != null;

/// Rendert [value] zoals de cel hem bewaart: geheel als `96`, anders op
/// vier decimalen afgerond zonder stil weglaten van significantie; `null`
/// (onbekend) als `—` — nooit `0`.
String formatCalcValue(double? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return '${value.round()}';
  }
  var s = value.toStringAsFixed(4);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

/// Herschrijft de afgeleide cellen van [table] in [source] naar de
/// herberekende waarden — de expliciete herstelactie bij `calc-drift`.
/// Invoercellen blijven byte-getrouw staan; de markers ook.
String recalculateOciTable(String source, OciMarkedTable table) {
  final defs = ociCalcDefs(table);
  if (defs.isEmpty) return source;
  final eval = evaluateOciTableCalc(table);
  final colIdx = [for (final d in defs) table.colIndexOf(d.col)];
  final body = table.bodyRows;
  final newBody = <List<String>>[
    for (var r = 0; r < body.length; r++)
      [
        for (var c = 0; c < table.headerCells.length; c++)
          colIdx.contains(c) && r < eval.results.length
              ? formatCalcValue(eval.results[r][colIdx.indexOf(c)].value)
              : (c < body[r].length ? body[r][c] : ''),
      ],
  ];
  return rewriteOciMarkedTable(source, table, bodyRows: newBody);
}

/// Voegt de `calc`-marker [col]/[expr] toe aan het markerblok van [table]
/// en materialiseert de kolom meteen — zodat ook de eerste afschrijving
/// al klopt voor elke lezer. De nieuwe marker landt als laatste van het
/// blok (gestapeld boven de tabel, §3.7).
String addOciCalcToTable(
  String source,
  OciMarkedTable table,
  String col,
  String expr,
) {
  final calc = OciTableMarker(
    kind: OciMarkerKinds.calc,
    attrs: {'col': col, 'expr': expr},
  );
  final withMarker = rewriteOciMarkedTable(
    source,
    table,
    markers: [...table.markers, calc],
  );
  // Opnieuw scannen: de blokgrens verschoof niet, de markerlijst wel —
  // blockStart wijst nog dezelfde tabel aan.
  final rescanned = scanOciMarkedTables(
    withMarker,
  ).tables.firstWhere((t) => t.blockStart == table.blockStart);
  return recalculateOciTable(withMarker, rescanned);
}

/// Verwijdert de `calc`-marker voor [col] van [table] — de expliciete,
/// bevestigde "vervangen"-keuze. De cellen houden hun laatst berekende
/// waarde als gewone tekst; de formule verdwijnt nooit stilletjes.
String removeOciCalcFromTable(String source, OciMarkedTable table, String col) {
  final markers = [
    for (final m in table.markers)
      if (!(m.kind == OciMarkerKinds.calc && m.attr('col') == col)) m,
  ];
  return rewriteOciMarkedTable(source, table, markers: markers);
}
