/// XML parsing helpers with hardening against entity-bom and oversized inputs.
library;

import 'package:xml/xml.dart';

/// Maximum XML string length we are willing to parse in one go.
///
/// This guards against XML "billion laughs" style payload that is a huge
/// document even without entity expansion. 50 MiB is far beyond any normal
/// presentation part.
const _maxXmlLength = 50 * 1024 * 1024;

/// Parse [src] as XML after stripping any `<!DOCTYPE ...>` block and length
/// checking.
///
/// Removing the DOCTYPE prevents internal/external entity declarations from
/// being processed at all, which blocks the `billion laughs` class of
/// denial-of-service attacks.
XmlDocument? parseXmlSafe(String src) {
  if (src.length > _maxXmlLength) return null;
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
