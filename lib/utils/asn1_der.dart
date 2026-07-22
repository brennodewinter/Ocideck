import 'dart:typed_data';

/// A tiny, dependency-free ASN.1 **DER** codec — only the slice needed for
/// RFC 3161 timestamping (PENTEST_MIAUW §8-A2): building a TimeStampReq (`.tsq`)
/// and walking a TimeStampResp (`.tsr`) to read the message imprint and time.
/// It is deliberately minimal (no schema, no OID registry) — encode helpers plus
/// a recursive tag/length/value reader — so it stays small and fully testable
/// without a crypto dependency.

// ── Encoding ────────────────────────────────────────────────────────────────

/// DER length octets for a content of [n] bytes (short form < 128, else long).
List<int> derLength(int n) {
  if (n < 0x80) return [n];
  final out = <int>[];
  var v = n;
  while (v > 0) {
    out.insert(0, v & 0xff);
    v >>= 8;
  }
  return [0x80 | out.length, ...out];
}

/// A DER tag-length-value: [tag] byte, the length of [content], then [content].
List<int> derTlv(int tag, List<int> content) => [
  tag,
  ...derLength(content.length),
  ...content,
];

/// A `SEQUENCE` (tag `0x30`) wrapping the concatenation of [parts].
List<int> derSequence(List<List<int>> parts) =>
    derTlv(0x30, [for (final p in parts) ...p]);

/// A non-negative `INTEGER` (tag `0x02`) in minimal two's-complement form.
List<int> derInteger(int value) {
  assert(value >= 0, 'only non-negative integers are needed here');
  final bytes = <int>[];
  var v = value;
  do {
    bytes.insert(0, v & 0xff);
    v >>= 8;
  } while (v > 0);
  // Prepend a zero byte when the high bit is set, so it stays positive.
  if (bytes.first & 0x80 != 0) bytes.insert(0, 0);
  return derTlv(0x02, bytes);
}

/// An `INTEGER` (tag `0x02`) from an already-generated magnitude [bytes],
/// most-significant byte first.
///
/// Bestaat naast [derInteger] omdat een Dart-`int` maar 64 bits draagt én
/// getekend is: een willekeurige 64-bits nonce past er niet veilig in. Leidende
/// nulbytes gaan eruit (DER eist de kortste vorm) en er komt er één bij zodra
/// de hoogste bit staat, anders leest de waarde als negatief.
List<int> derPositiveInteger(List<int> bytes) {
  var start = 0;
  while (start < bytes.length - 1 && bytes[start] == 0) {
    start++;
  }
  final magnitude = bytes.sublist(start);
  return derTlv(0x02, [if (magnitude.first & 0x80 != 0) 0, ...magnitude]);
}

/// An `OCTET STRING` (tag `0x04`) carrying [bytes] verbatim.
List<int> derOctetString(List<int> bytes) => derTlv(0x04, bytes);

/// A `BOOLEAN` (tag `0x01`); DER encodes true as `0xFF`.
List<int> derBoolean(bool value) => derTlv(0x01, [value ? 0xff : 0x00]);

/// An `OBJECT IDENTIFIER` (tag `0x06`) from its already-encoded [body] octets.
List<int> derOid(List<int> body) => derTlv(0x06, body);

/// The `NULL` value (tag `0x05`, empty).
List<int> derNull() => [0x05, 0x00];

// ── Parsing ─────────────────────────────────────────────────────────────────

/// One parsed DER node: its [tag], its raw [content] bytes (value only), and —
/// for a constructed node — its [children].
class Asn1Node {
  Asn1Node(this.tag, this.content, this.children);

  final int tag;
  final Uint8List content;
  final List<Asn1Node> children;

  /// Whether the constructed bit (0x20) is set.
  bool get isConstructed => tag & 0x20 != 0;

  /// Every node in this subtree, in depth-first (pre-order) order.
  Iterable<Asn1Node> get descendantsAndSelf sync* {
    yield this;
    for (final child in children) {
      yield* child.descendantsAndSelf;
    }
  }
}

/// Parse the single top-level DER value in [data]. Constructed nodes are parsed
/// recursively; primitive nodes keep their raw [Asn1Node.content]. Returns null
/// when [data] is not well-formed DER.
/// Hoeveel niveaus diep een DER-boom mag zijn.
///
/// Een RFC 3161-token heeft er een handvol. De grens staat er niet voor die,
/// maar voor een token dat expres duizenden niveaus diep is: `_readNode` daalt
/// recursief af, en dan loopt de Dart-stack over met een [StackOverflowError].
/// Dat is een `Error`, geen `Exception`, dus de `on RangeError` hieronder ving
/// hem niet — en de aanroeper evenmin. Het token zit in de front matter van het
/// deck en wordt gelezen tijdens het bouwen van het zegelvenster, dus een deck
/// dat iemand je stuurt liet de app elke keer opnieuw omvallen.
const int _maxDerDepth = 64;

Asn1Node? parseDer(Uint8List data) {
  try {
    final (node, _) = _readNode(data, 0, 0);
    return node;
  } on RangeError {
    // Truncated/malformed DER indexes past the end — not valid, return null.
    return null;
  } on FormatException {
    // Te diep genest of een onbepaalde lengte: geen geldige DER.
    return null;
  }
}

(Asn1Node, int) _readNode(Uint8List data, int offset, int depth) {
  if (depth > _maxDerDepth) {
    throw const FormatException('DER-nesting te diep');
  }
  var i = offset;
  final tag = data[i++];
  var len = data[i++];
  if (len & 0x80 != 0) {
    final n = len & 0x7f;
    // `0x80` is de onbepaalde lengte uit BER. In DER bestaat die niet, en hij
    // werd hier als lengte nul gelezen: de inhoud van zo'n knoop viel dan
    // stilzwijgend buiten de boom en werd op het niveau erboven opnieuw
    // uitgelegd. In een verificatiepad hoort dat een weigering te zijn.
    if (n == 0) throw const FormatException('DER kent geen onbepaalde lengte');
    len = 0;
    for (var k = 0; k < n; k++) {
      len = (len << 8) | data[i++];
    }
    if (len < 0) throw const FormatException('DER-lengte loopt over');
  }
  final content = Uint8List.sublistView(data, i, i + len);
  final end = i + len;
  final children = <Asn1Node>[];
  if (tag & 0x20 != 0) {
    var c = i;
    while (c < end) {
      final (child, next) = _readNode(data, c, depth + 1);
      children.add(child);
      c = next;
    }
  }
  return (Asn1Node(tag, content, children), end);
}
