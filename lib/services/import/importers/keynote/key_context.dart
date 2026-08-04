import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../utils/xml_utils.dart';

/// A typed view over an unzipped Apple Keynote (`.key`) package.
///
/// A `.key` is a ZIP whose slide content lives in Snappy-compressed IWA
/// protobuf messages under `Index/` (parsed in a later milestone), with raw
/// media under `Data/` and a rendered `preview.jpg` at the root. Metadata
/// plists sit under `Metadata/`. This context only exposes the non-IWA parts.
class KeyContext {
  KeyContext(this.archive);

  final Archive archive;

  String? readPart(String path) {
    final bytes = readPartBytes(path);
    // Keynote-plists en -XML onder Metadata/ zijn UTF-8; byte-voor-byte lezen
    // zou een meerbyte-teken tot mojibake uiteentrekken (zie #1194 voor .odp).
    return bytes == null ? null : utf8.decode(bytes);
  }

  List<int>? readPartBytes(String path) {
    for (final f in archive) {
      if (f.name == path) return f.content as List<int>;
    }
    return null;
  }

  XmlDocument? readXml(String path) {
    final src = readPart(path);
    if (src == null) return null;
    return parseXmlSafe(src);
  }

  /// All archive entry names (useful for locating `preview.jpg` / `Data/...`).
  Set<String> get entryNames => archive.map((f) => f.name).toSet();
}
