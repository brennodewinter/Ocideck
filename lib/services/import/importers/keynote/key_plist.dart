import 'package:xml/xml.dart';

import '../../utils/xml_utils.dart';
import 'key_context.dart';

/// Read an XML property list's top-level `<dict>` into a flat `String` map.
///
/// Apple plists come in two encodings: XML (`<plist version="1.0">…`) and
/// binary (`bplist00…`). Only the XML form is parsed here; binary plists
/// return an empty map (graceful fallback — we just miss the metadata). Only
/// `<string>` values are captured; arrays/dicts keep their first string when
/// practical, otherwise the key is dropped.
Map<String, String> readXmlPlist(String xml) {
  final map = <String, String>{};
  // Via `parseXmlSafe`, niet `XmlDocument.parse`: dit is tekst uit een
  // meegeleverd archief, dus dezelfde poort als de rest van de import — lengte
  // begrensd en de DOCTYPE eruit, zodat een entiteitsdeclaratie in een plist
  // niets heeft om uit te vouwen.
  final doc = parseXmlSafe(xml);
  if (doc == null) return map;
  final dict = _firstLocal(doc.descendants, 'dict');
  if (dict == null) return map;
  String? pendingKey;
  for (final node in dict.children.whereType<XmlElement>()) {
    if (node.name.local == 'key') {
      pendingKey = _innerText(node).trim();
    } else if (pendingKey != null) {
      final value = _valueOf(node);
      if (value != null) map[pendingKey] = value;
      pendingKey = null;
    }
  }
  return map;
}

/// Het eerste element in [nodes] met lokale naam [local], of `null`.
XmlElement? _firstLocal(Iterable<XmlNode> nodes, String local) {
  for (final e in nodes.whereType<XmlElement>()) {
    if (e.name.local == local) return e;
  }
  return null;
}

/// Pull deck title/author out of `Metadata/Properties.plist` (XML), looking
/// at the keys Keynote/iWork are known to use. Returns `('','')` when the
/// plist is missing, binary, or lacks the keys.
({String title, String author}) deckMetadataFromPlist(KeyContext ctx) {
  final raw = ctx.readPart('Metadata/Properties.plist');
  if (raw == null) return (title: '', author: '');
  if (!raw.trimLeft().startsWith('<')) return (title: '', author: '');
  final map = readXmlPlist(raw);
  final title = _firstPresent(map, const [
    'title',
    'DocumentTitle',
    'kMDItemTitle',
    'CFBundleDisplayName',
  ]);
  final author = _firstPresent(map, const [
    'author',
    'authors',
    'kMDItemAuthors',
    'creator',
  ]);
  return (title: title, author: author);
}

String _firstPresent(Map<String, String> map, List<String> keys) {
  for (final k in keys) {
    final v = map[k];
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

String? _valueOf(XmlElement el) {
  switch (el.name.local) {
    case 'string':
      return _innerText(el).trim();
    case 'array':
      // Take the first string in the array, if any.
      final first = _firstLocal(el.descendants, 'string');
      if (first == null) return null;
      return _innerText(first).trim();
    default:
      return null;
  }
}

String _innerText(XmlElement el) {
  final buf = StringBuffer();
  for (final node in el.descendants) {
    if (node is XmlText) buf.write(node.value);
  }
  return buf.toString();
}
