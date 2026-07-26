/// XML parsing helpers with hardening against entity-bom and oversized inputs.
library;

import 'package:xml/xml.dart';

import 'import_budget.dart';

/// Parse [src] as XML after stripping any `<!DOCTYPE ...>` block and length
/// checking.
///
/// Removing the DOCTYPE prevents internal/external entity declarations from
/// being processed at all, which blocks the `billion laughs` class of
/// denial-of-service attacks. The length check guards against a huge single
/// part (a `slideN.xml` of tens of MiB) — far beyond any normal presentation
/// part, and driven by the source, so it belongs in the [ImportBudget].
///
/// [budget] carries the per-part length limit; a test passes a tiny
/// [ImportBudget.forTest] to hit the guard without building a 32 MiB string.
/// The importers call this with the standard budget, which is exactly the
/// production limit. Returns `null` when the part is over the limit or not
/// well-formed — the caller treats a missing part as a recoverable loss, not a
/// crash.
XmlDocument? parseXmlSafe(
  String src, {
  ImportBudget budget = ImportBudget.standard,
}) {
  if (src.length > budget.maxXmlPartBytes) return null;
  final cleaned = _removeDoctype(src);
  try {
    return XmlDocument.parse(cleaned);
  } on Exception {
    return null;
  }
}

/// Remove `<!DOCTYPE ...>` blocks from [src] while respecting quotes and
/// internal subsets.
String _removeDoctype(String src) {
  final buffer = StringBuffer();
  var i = 0;
  final startRe = RegExp(r'<!DOCTYPE', caseSensitive: false);
  while (i < src.length) {
    final start = src.indexOf(startRe, i);
    if (start < 0) {
      buffer.write(src.substring(i));
      break;
    }
    buffer.write(src.substring(i, start));

    var j = start + 9; // length of "<!DOCTYPE"
    var inSingle = false;
    var inDouble = false;
    var bracketDepth = 0;
    while (j < src.length) {
      final c = src[j];
      if (inSingle) {
        if (c == "'") inSingle = false;
      } else if (inDouble) {
        if (c == '"') inDouble = false;
      } else {
        if (c == '"') {
          inDouble = true;
        } else if (c == "'") {
          inSingle = true;
        } else if (c == '[') {
          bracketDepth++;
        } else if (c == ']') {
          bracketDepth--;
        } else if (c == '>' && bracketDepth <= 0) {
          j++;
          break;
        }
      }
      j++;
    }
    i = j;
  }
  return buffer.toString();
}
