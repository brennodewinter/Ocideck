import 'dart:convert';
import 'dart:typed_data';

import '../../../models/source_chart.dart';
import '../../../models/source_image.dart';
import '../../../models/source_table.dart';
import '../../../models/source_video.dart';
import '../key_context.dart';
import '../key_text_salvage.dart';
import 'iwa_archive.dart';
import 'iwa_document.dart';

/// Reconstructs the text and drawable structure of a Keynote slide from an
/// iWork object graph: placeholder and note text, the text of an arbitrary
/// drawable, the flattening of group drawables into their leaf children, and
/// the images a drawable carries.
///
/// Message types are recognised **structurally** from their field shapes and
/// reference targets, because Apple's runtime `TSPRegistry` (typeId -> class)
/// is not shipped in the file.
class DrawableReader {
  DrawableReader(this.doc, {this.ctx});

  final IwaDocument doc;
  final KeyContext? ctx;

  /// Speaker-note text for a slide, via `SlideArchive.note` (field 27) ->
  /// `NoteArchive.containedStorage` (field 1) -> `StorageArchive.text` (field 3).
  /// `null` when the slide has no note or the chain does not resolve.
  String? notesText(IwaObject slide) {
    final noteRef = slide.message.varint(27);
    if (noteRef == null) return null;
    final note = doc.resolveReference(slide, noteRef);
    if (note == null) return null;
    final storageRef = note.message.varint(1);
    if (storageRef == null) return null;
    final storage = doc.resolveReference(note, storageRef);
    if (storage == null) return null;
    return _storageText(storage);
  }

  /// Resolve a single placeholder reference (field [field]) on [o] to its
  /// ShapeInfoArchive and return the StorageArchive text, or `null`.
  String? placeholderText(IwaObject o, int field) {
    for (final shape in doc.resolveReferences(o, field)) {
      final t = shapeText(shape);
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  /// Text of a drawable. A ShapeInfoArchive points (field 2) at a StorageArchive;
  /// a GroupArchive lists children (repeated field 2). Real iWork files encode
  /// references as `TSP.Reference` submessages, and newer files wrap the actual
  /// ShapeInfoArchive / StorageArchive in extra drawable objects, so we walk the
  /// reachable object graph (avoiding cycles) to find any StorageArchive text.
  ///
  /// We follow only the direct containedStorage path (field 2) and the
  /// ShapeArchive super-message (field 1, subfields 2 and 4). Following
  /// every reference field recursively reaches shared/template storages and
  /// pulls their text into every slide — see #1468.
  String? shapeText(IwaObject o, {Set<int>? visited}) {
    final seen = visited ?? <int>{};
    if (!seen.add(o.id)) return null;

    // First try the classic containedStorage field (field 2).
    for (final target in doc.resolveReferences(o, 2)) {
      if (_isStorage(target)) {
        final t = _storageText(target);
        if (t != null && t.isNotEmpty) return t;
      }
    }

    // Newer Keynote files store the text storage reference inside the nested
    // ShapeArchive super-message (field 1), typically on the `style` field (2)
    // or the `head_line_end` field (4). Resolve those TSP.Reference subfields.
    final superMsg = o.message.message(1);
    if (superMsg != null) {
      for (final refField in const [2, 4]) {
        for (final sub in superMsg.messages(refField)) {
          final refId = sub.varint(1);
          if (refId == null) continue;
          final target = doc.resolveReference(o, refId);
          if (target != null && _isStorage(target)) {
            final t = _storageText(target);
            if (t != null && t.isNotEmpty) return t;
          }
        }
      }
    }

    return null;
  }

  /// True when [o] is a text-bearing StorageArchive. We require the first
  /// field-3 chunk to decode as text-like UTF-8, so UUID objects and other
  /// binary blobs are not misclassified as slide text.
  bool _isStorage(IwaObject o) {
    final chunks = o.message.bytesList(3);
    if (chunks.isEmpty) return false;
    // UUID objects and locale bundles are not text storage.
    if (o.typeId == 10 || o.typeId == 1) return false;
    try {
      final first = utf8.decode(chunks.first);
      if (first.contains('\x00')) return false;
      if (first.contains('\uFFFC') || first.contains('\uFFFD')) return false;
      if (_isPlaceholderText(first)) return false;
      final trimmed = first.trim();
      if (trimmed.isEmpty) return false;
      // Single-character bullets are valid slide text.
      if (trimmed.length == 1) return true;
      if (KeyTextSalvage.isTextLike(first)) return true;
      // Long paragraphs (> 200 chars) are text too, as long as they contain
      // a letter and no NUL bytes.
      if (first.length > 200 &&
          RegExp(r'\p{L}', unicode: true).hasMatch(first) &&
          !first.contains('\x00')) {
        return true;
      }
    } on FormatException {
      // Not valid UTF-8 — not a text storage.
    }
    return false;
  }

  /// True when [text] is a Keynote placeholder string rather than real content.
  /// These are stored in otherwise-empty text boxes on master/layout slides.
  bool _isPlaceholderText(String text) {
    final first = text.trim().split(RegExp(r'\r\n|\r|\n')).first.trim();
    // Known placeholder strings in Dutch (and a few generic variants).
    final placeholders = {
      'Titeltekst',
      'Ondertitel',
      'Hoofdtekst',
      'Plaats tekst in dit vak',
      'Voettekst',
      'Paginanummer',
      'Titel',
      'Dia nummer',
      'Slide nummer',
    };
    if (placeholders.contains(first)) return true;
    if (first.startsWith('Hoofdtekst - niveau')) return true;
    if (first.startsWith('Tekst - niveau')) return true;
    if (first.startsWith('Body - Level')) return true;
    if (first.startsWith('Title Text')) return true;
    return false;
  }

  /// A StorageArchive's text is the concatenation of its repeated `text`
  /// string field (field 3). Some iWork files percent-encode UTF-8, so we
  /// decode percent escapes after strict UTF-8 decoding.
  String? _storageText(IwaObject o) {
    final chunks = <String>[];
    for (final b in o.message.bytesList(3)) {
      try {
        var s = utf8.decode(b);
        try {
          s = Uri.decodeComponent(s);
        } on FormatException {
          // Not percent-encoded; use the UTF-8 string as-is.
        } on ArgumentError {
          // Malformed percent escapes; keep the UTF-8 string as-is.
        }
        chunks.add(s);
      } on FormatException {
        // Skip non-UTF-8 fragments.
      }
    }
    if (chunks.isEmpty) return null;
    return chunks.join();
  }

  /// Flattens group drawables (`TSD.GroupArchive`) into their leaf children.
  /// Returns the flattened list plus a flag that is true when a group was
  /// expanded.
  (List<IwaObject>, bool) flattenDrawables(
    List<IwaObject> drawables, {
    Set<int>? visited,
  }) {
    final out = <IwaObject>[];
    var hadGroup = false;
    final seen = visited ?? <int>{};
    for (final d in drawables) {
      if (!seen.add(d.id)) continue;
      if (_isGroup(d)) {
        hadGroup = true;
        final children = doc.resolveReferences(d, 2);
        final (flattened, nestedGroup) = flattenDrawables(
          children,
          visited: seen,
        );
        out.addAll(flattened);
        if (nestedGroup) hadGroup = true;
      } else {
        out.add(d);
      }
    }
    return (out, hadGroup);
  }

  /// True when [o] is a `TSD.GroupArchive` rather than a shape, table, chart,
  /// image or movie. Groups carry repeated child references in field 2.
  bool _isGroup(IwaObject o) {
    final refs = o.message.varints(2);
    if (refs.length > 1) return true;
    if (refs.length == 1) {
      final first = doc.resolveReference(o, refs.first);
      if (first == null) return false;
      if (_isStorage(first)) return false;
      if (first.typeId == 6001) return false; // TST.TableModelArchive
      if (_isStyleOrTableModel(first)) return false;
      return true;
    }
    return false;
  }

  /// True when [o] is a `TST.TableModelArchive` or a `TSS.StyleArchive`.
  /// These are the single field-2 references carried by `TableInfoArchive`
  /// and `ShapeArchive` respectively, which should not be treated as group
  /// children.
  bool _isStyleOrTableModel(IwaObject o) {
    final hasNameOrIdentifier =
        o.message.string(1) != null || o.message.string(2) != null;
    if (hasNameOrIdentifier &&
        o.message.varint(6) == null &&
        o.message.varint(7) == null) {
      return true;
    }
    if (o.message.varint(6) != null || o.message.varint(7) != null) {
      return true;
    }
    return false;
  }

  /// True when [drawable] has a drawable super but yielded no table, chart,
  /// media, image or text. Such objects are usually decorative shapes or lines
  /// that OciDeck cannot represent.
  bool isUnhandledDrawable(
    IwaObject drawable,
    String? text,
    List<SourceImage> drawableImages,
    SourceTable? tableResult,
    SourceChart? chartResult,
    ({SourceVideo? video, String? audioFileName}) media,
  ) {
    if (drawable.message.message(1) == null) return false;
    if (tableResult != null ||
        chartResult != null ||
        media.video != null ||
        media.audioFileName != null ||
        drawableImages.isNotEmpty ||
        text != null) {
      return false;
    }
    return true;
  }

  /// Images contained by a drawable. `TSD.ImageArchive` fields vary across
  /// iWork versions: newer archives use `TSP.Reference` fields (e.g. 2, 9)
  /// that point at nested `TSP.Image` / `TSD.ImageArchive` objects, while
  /// older archives store `TSP.DataReference` values directly. We therefore
  /// traverse references and collect any `TSP.DataReference` that resolves to
  /// a file in `Data/`.
  List<SourceImage> imagesForDrawable(IwaObject o, {Set<int>? visited}) {
    final images = <SourceImage>[];
    if (ctx == null) return images;

    final seen = visited ?? <int>{};
    final dataIds = _collectImageDataIds(o, seen);
    for (final dataId in dataIds) {
      final fileName = doc.dataFileName(dataId);
      if (fileName == null) continue;
      final bytes = ctx!.readPartBytes('Data/$fileName');
      if (bytes != null && bytes.isNotEmpty) {
        images.add(
          SourceImage(
            bytes: Uint8List.fromList(bytes),
            ext: _ext(fileName),
            name: fileName,
          ),
        );
      }
    }
    return images;
  }

  /// Object types that may contain image `DataReference` data.
  static const _imageLikeTypeIds = {2022, 2023, 3005, 6003, 6004, 6005, 6247};

  /// Recursively collect `DataReference` data ids from [o] and its referenced
  /// image-like objects. Treats a nested message as a `TSP.DataReference` when
  /// its first field (field 1) resolves to a `Data/` file, and as a
  /// `TSP.Reference` to be followed when the first field resolves to an object.
  Set<int> _collectImageDataIds(IwaObject o, Set<int> seen) {
    if (!seen.add(o.id)) return const {};
    final ids = <int>{};

    // Try the canonical image data fields first. Field 12 is the thumbnail
    // preview that Keynote stores alongside the full image (field 11);
    // importing both creates duplicate entries in the image library (#1468).
    for (final field in const [11, 15, 16, 17]) {
      final dataId = _dataReferenceId(o, field);
      if (dataId != null) {
        ids.add(doc.resolveDataReference(o, dataId));
      }
    }

    // Fall back to following references to image-like objects. Skip field 12
    // (thumbnail) here too — it's handled above as a canonical field and
    // would otherwise be re-collected through this fallback path.
    for (final field in o.message.fields.keys) {
      if (field == 12) continue;
      final sub = o.message.message(field);
      if (sub == null) continue;
      final refId = sub.varint(1);
      if (refId == null) continue;
      // If the first field is itself a valid DataReference, use it.
      final resolvedDataId = doc.resolveDataReference(o, refId);
      if (doc.dataFileName(resolvedDataId) != null) {
        ids.add(resolvedDataId);
        continue;
      }
      // Otherwise treat it as a reference when it points at an image object.
      final target = doc.resolveReference(o, refId);
      if (target != null && _imageLikeTypeIds.contains(target.typeId)) {
        ids.addAll(_collectImageDataIds(target, seen));
      }
    }
    return ids;
  }

  /// If [field] on [o] is a `TSP.DataReference` message, returns its payload
  /// identifier (after resolving data-reference index indirection). Returns
  /// `null` when the field is missing or the resolved identifier does not map
  /// to a `Data/` file.
  int? _dataReferenceId(IwaObject o, int field) {
    final sub = o.message.message(field);
    if (sub == null) return null;
    final rawId = sub.varint(1);
    if (rawId == null) return null;
    final dataId = doc.resolveDataReference(o, rawId);
    if (doc.dataFileName(dataId) != null) return dataId;
    return null;
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return 'jpg';
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }
}
