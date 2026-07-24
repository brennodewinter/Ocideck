import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../utils/xml_utils.dart';

/// Opc part namespaces used by PPTX.
class _Ns {
  static const String a =
      'http://schemas.openxmlformats.org/drawingml/2006/main';
  static const String r =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
}

/// A typed view over an unzipped PPTX package: part lookup, relationship
/// resolution, and namespace-agnostic XML helpers.
///
/// PPTX is an OPC package: every part (`ppt/slides/slide1.xml`) has a
/// `.rels` sidecar (`ppt/slides/_rels/slide1.xml.rels`) mapping relationship
/// ids to targets. Targets are relative to the part's own folder, so
/// `../media/image1.png` from `ppt/slides/` resolves to `ppt/media/image1.png`.
class PptxContext {
  PptxContext(this.archive);

  final Archive archive;

  /// Slide page size in EMUs from `ppt/presentation.xml`, or `null` when
  /// the presentation part is missing or malformed.
  ({int width, int height})? get slideSize {
    final pres = readXml('ppt/presentation.xml');
    if (pres == null) return null;
    final sldSz = descendantsLocal(pres, 'sldSz').firstOrNull;
    if (sldSz == null) return null;
    final width = int.tryParse(sldSz.getAttribute('cx') ?? '');
    final height = int.tryParse(sldSz.getAttribute('cy') ?? '');
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (width: width, height: height);
  }

  /// Decode a text part by path, or `null` when absent.
  String? readPart(String path) {
    final bytes = readPartBytes(path);
    return bytes == null ? null : utf8.decode(bytes);
  }

  List<int>? readPartBytes(String path) {
    for (final f in archive) {
      if (f.name == path) return f.content as List<int>;
    }
    return null;
  }

  /// Parse an XML part by path, or `null` when absent/invalid.
  XmlDocument? readXml(String path) {
    final src = readPart(path);
    if (src == null) return null;
    return parseXmlSafe(src);
  }

  /// Relationships for [partPath] as `{rId: target}`.
  Map<String, String> relsFor(String partPath) {
    final relsPath = _relsPath(partPath);
    final doc = readXml(relsPath);
    if (doc == null) return const {};
    final out = <String, String>{};
    for (final rel in descendantsLocal(doc, 'Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id != null && target != null) out[id] = target;
    }
    return out;
  }

  /// Resolve a relationship id from [rels] against [partPath]'s folder.
  ///
  /// External links (absolute URIs such as `http://...` or `data:...`) are
  /// returned unchanged so they are not mangled into package-relative paths.
  String? resolveRel(Map<String, String> rels, String? rId, String partPath) {
    if (rId == null) return null;
    final target = rels[rId];
    if (target == null) return null;
    if (_isAbsoluteUri(target)) return target;
    return _resolveTarget(target, partPath);
  }

  /// True when [target] is an absolute URI rather than a package-relative path.
  static bool _isAbsoluteUri(String target) {
    if (target.startsWith('//')) return true;
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*:').hasMatch(target);
  }

  /// Read a related binary part: look up [rId] in [rels], resolve it, and
  /// return its bytes (or `null`).
  List<int>? readRelBytes(
    Map<String, String> rels,
    String? rId,
    String partPath,
  ) {
    final resolved = resolveRel(rels, rId, partPath);
    if (resolved == null) return null;
    return readPartBytes(resolved);
  }

  /// The `.rels` sidecar path for [partPath].
  static String _relsPath(String partPath) {
    final slash = partPath.lastIndexOf('/');
    final dir = slash >= 0 ? partPath.substring(0, slash) : '';
    final name = slash >= 0 ? partPath.substring(slash + 1) : partPath;
    final relsDir = dir.isEmpty ? '_rels' : '$dir/_rels';
    return '$relsDir/$name.rels';
  }

  static String _resolveTarget(String target, String partPath) {
    if (target.startsWith('/')) return target.substring(1);
    final slash = partPath.lastIndexOf('/');
    final dir = slash >= 0 ? partPath.substring(0, slash) : '';
    final segments = <String>[...dir.split('/').where((s) => s.isNotEmpty)];
    for (final seg in target.split('/')) {
      if (seg == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else if (seg != '.' && seg.isNotEmpty) {
        segments.add(seg);
      }
    }
    return segments.join('/');
  }
}

// --- Namespace-agnostic XML helpers ------------------------------------------

/// All descendant elements whose local name matches [local].
Iterable<XmlElement> descendantsLocal(XmlNode root, String local) => root
    .descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

/// The first child element of [parent] with local name [local], or `null`.
XmlElement? childLocal(XmlElement parent, String local) {
  for (final node in parent.children.whereType<XmlElement>()) {
    if (node.name.local == local) return node;
  }
  return null;
}

/// All child elements of [parent] with local name [local].
Iterable<XmlElement> childrenLocal(XmlElement parent, String local) =>
    parent.children.whereType<XmlElement>().where((e) => e.name.local == local);

/// DrawingML `a:` namespace URI (exposed for attribute checks).
String get drawingmlNs => _Ns.a;

/// Relationships `r:` namespace URI.
String get relsNs => _Ns.r;
