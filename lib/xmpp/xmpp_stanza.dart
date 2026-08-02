// The XMPP wire unit: one stanza (`docs/design/NATIVE_CALLS.md` §3, F2). XMPP is
// a streaming XML protocol (RFC 6120/6121); over a client stream exactly three
// top-level stanzas flow — <iq>, <message>, <presence>. This models one of them
// as a thin, typed wrapper over the XML: the routing attributes (to/from/id/type)
// are first-class, and the payload stays as child [XmlElement]s so any XEP's
// element — MUC (XEP-0045), Jingle (Jitsi signalling), or OciDeck's own
// nl.ocideck.op — rides through unchanged without this layer knowing it.
//
// Parsing goes through `package:xml` (already a dependency; used by
// `webdav_service.dart` and `sanitize_svg.dart`), so this file hand-rolls no XML
// tokeniser. That is also the security posture: `package:xml` never fetches
// external entities, and [parse] rejects a DTD outright — XMPP forbids DTDs on
// the stream (RFC 6120 §11.1), so rejecting is both compliant and XXE defence in
// depth (the bewaker's stanza-parser condition, ketenkeuring-xmpp-spine.md).

import 'package:xml/xml.dart';

/// The client-stream stanza kind. Exactly these three exist (RFC 6120 §8).
enum StanzaKind { iq, message, presence }

/// One XMPP stanza. Routing attributes are typed; the payload stays as child
/// elements. Immutable — build a new one rather than mutating.
class Stanza {
  Stanza({
    required this.kind,
    this.to,
    this.from,
    this.id,
    this.type,
    List<XmlElement> children = const [],
  }) : children = List.unmodifiable(children);

  final StanzaKind kind;

  /// The recipient JID, or null (a stanza to the user's own server carries none).
  final String? to;

  /// The sender JID, set by the server on inbound stanzas; usually null outbound.
  final String? from;

  /// The stanza id — required on an `iq` (RFC 6120 §8.2.3), optional otherwise.
  final String? id;

  /// The type attribute (e.g. `get`/`set`/`result`/`error` on iq;
  /// `groupchat`/`chat` on message; `available`/`unavailable`/… on presence).
  final String? type;

  /// The payload: the stanza's child elements, in document order.
  final List<XmlElement> children;

  /// The first child element whose local name is [name] (namespace ignored), or
  /// null. Convenience for pulling a known payload (e.g. `body` on a message).
  XmlElement? child(String name) {
    for (final e in children) {
      if (e.name.local == name) return e;
    }
    return null;
  }

  /// Serialise to an [XmlElement] named for the [kind]. The `jabber:client`
  /// default namespace belongs to the stream, not the stanza, so it is not
  /// repeated here; the connection layer writes it once on stream open.
  XmlElement toXml() {
    final attributes = <XmlAttribute>[
      if (to != null) XmlAttribute(XmlName.parts('to'), to!),
      if (from != null) XmlAttribute(XmlName.parts('from'), from!),
      if (id != null) XmlAttribute(XmlName.parts('id'), id!),
      if (type != null) XmlAttribute(XmlName.parts('type'), type!),
    ];
    return XmlElement(
      XmlName.parts(kind.name),
      attributes,
      children.map((e) => e.copy()).toList(),
    );
  }

  /// The stanza as an XML string (no stream wrapper).
  String toXmlString() => toXml().toXmlString();

  @override
  String toString() => toXmlString();

  /// Wrap an already-parsed stanza [element] (a child of the stream root). Throws
  /// [FormatException] if it is not one of the three stanza kinds.
  static Stanza fromElement(XmlElement element) {
    final kind = _kindOf(element.name.local);
    if (kind == null) {
      throw FormatException('not an XMPP stanza: <${element.name.local}>');
    }
    return Stanza(
      kind: kind,
      to: element.getAttribute('to'),
      from: element.getAttribute('from'),
      id: element.getAttribute('id'),
      type: element.getAttribute('type'),
      children: element.childElements.map((e) => e.copy()).toList(),
    );
  }

  /// Parse a single stanza from its XML [source]. Rejects a DTD/doctype (XMPP
  /// forbids it; XXE defence in depth) and anything that is not exactly one
  /// iq/message/presence element. Throws [FormatException] on any of those.
  static Stanza parse(String source) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlException catch (e) {
      throw FormatException('malformed stanza XML: $e');
    }
    if (document.doctypeElement != null) {
      throw const FormatException('a stanza may not carry a DTD');
    }
    return fromElement(document.rootElement);
  }

  static StanzaKind? _kindOf(String localName) => switch (localName) {
    'iq' => StanzaKind.iq,
    'message' => StanzaKind.message,
    'presence' => StanzaKind.presence,
    _ => null,
  };
}

/// Build an [XmlElement] for a stanza payload — the small helper the higher
/// layers (MUC, later Jingle) use so they need not touch `package:xml` directly.
/// [namespace] sets the child's `xmlns` (each XEP lives in its own namespace).
XmlElement xmppElement(
  String name, {
  String? namespace,
  Map<String, String> attributes = const {},
  List<XmlElement> children = const [],
  String? text,
}) {
  return XmlElement(
    XmlName.parts(name),
    [
      if (namespace != null) XmlAttribute(XmlName.parts('xmlns'), namespace),
      for (final e in attributes.entries)
        XmlAttribute(XmlName.parts(e.key), e.value),
    ],
    [if (text != null) XmlText(text), ...children.map((e) => e.copy())],
  );
}
