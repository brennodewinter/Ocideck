import 'dart:convert';

/// Maximum nesting-diepte die [jsonDecodeGuarded] accepteert.
///
/// Dart's `jsonDecode` is recursief geïmplementeerd: een input vol
/// `[[[[[[...]]]]]]` laat de call-stack overlopen met een
/// `StackOverflowError` — een `Error`, geen `Exception`, dus een gewone
/// `try/catch` vangt hem niet. De byte-caps die er wél zijn vangen grootte,
/// niet diepte.
///
/// De grens staat er niet voor echte JSON (die zelden dieper dan een
/// handvol niveaus zit) maar voor een kwaadwillend of corrupt bestand dat
/// de stack laat overlopen. 256 is ruim boven elke realistische nesting en
/// ver onder de Dart-stack-limiet.
const int kMaxJsonNestingDepth = 256;

/// Decodeert [source] als JSON, maar weigert input die dieper nest dan
/// [kMaxJsonNestingDepth].
///
/// De pre-scan telt ongebalanceerde `[` en `{` in de raw string — een
/// lineaire scan die het pathologische geval (diep geneste brackets) vangt
/// vóór `jsonDecode` de stack op loopt. Strings die `[` of `{` bevatten
/// worden niet meegeteld omdat de scan string-literalen herkent en
/// overslaat.
///
/// Gooit een [FormatException] wanneer de nesting te diep is, of laat de
/// oorspronkelijke [FormatException] van [jsonDecode] door bij een
/// syntax-fout.
Object? jsonDecodeGuarded(
  String source, {
  int maxDepth = kMaxJsonNestingDepth,
}) {
  if (_maxNestingDepth(source) > maxDepth) {
    throw FormatException(
      'JSON-nesting overschrijdt de maximale diepte ($maxDepth)',
    );
  }
  return jsonDecode(source);
}

/// Telt de maximale nesting-diepte van `[` en `{` in [source], waarbij
/// string-literalen (tussen dubbele aanhalingstekens, met `\"`-escapes)
/// worden overgeslagen. Een simpele tekentelling zonder string-awareness
/// zou een `[` in een stringwaarde meetellen en een vals alarm geven op
/// legitieme JSON.
int _maxNestingDepth(String source) {
  var depth = 0;
  var max = 0;
  var inString = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (inString) {
      if (ch == r'\') {
        i++; // skip escaped char
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    switch (ch) {
      case '"':
        inString = true;
      case '[':
      case '{':
        depth++;
        if (depth > max) max = depth;
      case ']':
      case '}':
        if (depth > 0) depth--;
    }
  }
  return max;
}
