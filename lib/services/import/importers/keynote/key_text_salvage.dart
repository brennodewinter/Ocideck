import 'dart:convert';

import 'iwa/iwa_archive.dart';
import 'iwa/proto_wire.dart';
import 'iwa/snappy.dart';
import 'key_context.dart';

/// Best-effort text salvage from Keynote IWA protobufs.
///
/// Without Apple's `TSPRegistry` (the numeric typeId → schema-class mapping,
/// extracted at runtime from the iWork apps) we cannot know which object is a
/// Slide, Shape, or Text storage. But iWork stores all character content as
/// UTF-8 inside protobuf length-delimited fields, so we walk every object's
/// payload recursively and collect fields that decode to valid, text-like
/// UTF-8. The result is the deck's readable words/phrases in first-seen order
/// — noisy but genuinely useful, and clearly labelled as best-effort.
class KeyTextSalvage {
  KeyTextSalvage();

  final _snappy = SnappyDecompressor();
  final _wire = ProtoWire();
  final _archive = IwaArchive(ProtoWire());

  /// Walk every `Index/*.iwa` part in [ctx] and return the ordered, de-duped
  /// text strings salvaged from the IWA protobufs. Returns `[]` when no IWA
  /// parts parse.
  List<String> salvage(KeyContext ctx) {
    final seen = <String>{};
    final out = <String>[];
    for (final name in ctx.entryNames) {
      if (!name.startsWith('Index/') || !name.endsWith('.iwa')) continue;
      final bytes = ctx.readPartBytes(name);
      if (bytes == null) continue;
      try {
        final decompressed = _snappy.decompressIwaStream(bytes);
        final objects = _archive.parse(decompressed);
        for (final obj in objects.values) {
          for (final s in _collectStrings(obj.message, 0)) {
            if (seen.add(s)) out.add(s);
          }
        }
      } on Object {
        // A single malformed .iwa (which may raise an Error, not just an
        // Exception) must never abort the whole best-effort salvage.
        continue;
      }
    }
    return out;
  }

  /// Recursively collect text-like UTF-8 strings from [msg], guarding against
  /// unbounded recursion. A length-delimited field is treated as a string when
  /// it is valid strict UTF-8 and [isTextLike]; otherwise it is decoded as a
  /// nested message and walked.
  List<String> _collectStrings(ProtoMessage msg, int depth) {
    if (depth > 16) return const [];
    final out = <String>[];
    for (final entry in msg.fields.entries) {
      for (final v in entry.value) {
        if (v is! BytesValue) continue;
        final asString = _tryUtf8(v.bytes);
        if (asString != null && isTextLike(asString)) {
          out.add(asString);
          continue;
        }
        try {
          out.addAll(_collectStrings(_wire.decode(v.bytes), depth + 1));
        } on Exception {
          // Not a submessage and not a usable string — skip.
        }
      }
    }
    return out;
  }

  String? _tryUtf8(List<int> b) {
    if (b.length < 2) return null;
    try {
      final s = utf8.decode(b);
      // Some iWork strings are percent-encoded UTF-8 (e.g. "H%C3%A9llo").
      // Decode them so salvaged text is readable.
      try {
        return Uri.decodeComponent(s);
      } on FormatException {
        return s;
      }
    } on FormatException {
      return null;
    }
  }

  /// Heuristic: keep printable strings that contain a letter and do not look
  /// like file paths, font names, locale codes, UUIDs, or SCREAMING_CONSTANTS.
  static bool isTextLike(String s) {
    final t = s.trim();
    if (t.length < 2 || t.length > 200) return false;
    if (t.codeUnits.any(
      (c) => c < 0x20 && c != 0x09 && c != 0x0a && c != 0x0d,
    )) {
      return false;
    }
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(t)) return false;
    if (t.contains('/') || t.contains('\\')) return false;
    if (RegExp(r'\.(ttf|otf|woff|woff2)$', caseSensitive: false).hasMatch(t)) {
      return false;
    }
    if (RegExp(r'^[a-z]{2}[-_][A-Z]{2}$').hasMatch(t)) return false; // locale
    if (RegExp(
      r'^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$',
    ).hasMatch(t)) {
      return false; // UUID
    }
    if (RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(t) && t.length < 24) {
      return false; // enum/constant
    }
    return true;
  }
}
