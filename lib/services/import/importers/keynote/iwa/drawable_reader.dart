import 'dart:convert';
import 'dart:typed_data';

import '../../../../../utils/image_resize.dart'
    show ImportCrop, ImportImageGeometry, bakeImportGeometry, importCrop;
import '../../../models/source_chart.dart';
import '../../../models/source_image.dart';
import '../../../models/source_table.dart';
import '../../../models/source_video.dart';
import '../key_context.dart';
import '../key_text_salvage.dart';
import 'iwa_archive.dart';
import 'iwa_document.dart';
import 'proto_wire.dart';

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

  /// Like [placeholderText] but preserves bullet levels via leading tabs.
  String? placeholderTextWithLevels(IwaObject o, int field) {
    for (final shape in doc.resolveReferences(o, field)) {
      final t = shapeTextWithLevels(shape);
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

  /// The bullet indent level per paragraph in [storage]'s text, derived from
  /// the ParagraphStyleArchive (typeId 2022) `listLevel` field (field 10)
  /// referenced by the StorageArchive's paragraph-style map (field 5).
  ///
  /// Returns an empty list when no level info is available — callers fall back
  /// to level 0. Levels are normalised so the shallowest paragraph is level 0.
  List<int> _storageParagraphLevels(IwaObject storage) {
    // Field 5 is a single submessage whose field 1 is a repeated list of
    // paragraph entries: each has field 1 = char offset and optional field 2
    // = a style-reference submessage (field 1 = object id/index).
    final f5 = storage.message.bytesList(5);
    if (f5.isEmpty) return const [];
    final ProtoMessage paraMap;
    try {
      paraMap = ProtoWire().decode(f5.first);
    } on Object {
      return const [];
    }
    final entries = paraMap.bytesList(1);
    if (entries.isEmpty) return const [];

    // Walk the paragraph entries, resolving each style reference to a
    // ParagraphStyleArchive and reading its field 10 (listLevel). Entries
    // without an explicit style inherit the previous one.
    final rawLevels = <int>[];
    var currentLevel = 0;
    for (final entry in entries) {
      final ProtoMessage em;
      try {
        em = ProtoWire().decode(entry);
      } on Object {
        rawLevels.add(currentLevel);
        continue;
      }
      final styleBytes = em.bytesList(2);
      if (styleBytes.isNotEmpty) {
        try {
          final styleMsg = ProtoWire().decode(styleBytes.first);
          final refId = styleMsg.varint(1);
          if (refId != null) {
            final style = doc.resolveReference(storage, refId);
            if (style != null) {
              final lvl = style.message.varint(10);
              if (lvl != null) currentLevel = lvl;
            }
          }
        } on Object {
          // Keep the inherited level.
        }
      }
      rawLevels.add(currentLevel);
    }

    // Normalise: map distinct listLevel values to sequential 0-based levels.
    // iWork listLevel values are not always sequential (e.g. 1, 3, 5), so we
    // sort the distinct values and map them to 0, 1, 2, …
    if (rawLevels.isEmpty) return const [];
    final distinct = rawLevels.toSet().toList()..sort();
    final levelMap = {for (var i = 0; i < distinct.length; i++) distinct[i]: i};
    return [for (final l in rawLevels) levelMap[l] ?? 0];
  }

  /// Like [shapeText] but encodes each paragraph's bullet level as leading
  /// tabs, so the caller can recover the nesting by counting `\t` prefixes.
  /// Used by the slide reconstructor to preserve bullet hierarchy (#1468).
  String? shapeTextWithLevels(IwaObject o, {Set<int>? visited}) {
    final seen = visited ?? <int>{};
    if (!seen.add(o.id)) return null;

    for (final target in doc.resolveReferences(o, 2)) {
      if (_isStorage(target)) {
        final t = _storageTextWithLevels(target);
        if (t != null && t.isNotEmpty) return t;
      }
    }

    final superMsg = o.message.message(1);
    if (superMsg != null) {
      for (final refField in const [2, 4]) {
        for (final sub in superMsg.messages(refField)) {
          final refId = sub.varint(1);
          if (refId == null) continue;
          final target = doc.resolveReference(o, refId);
          if (target != null && _isStorage(target)) {
            final t = _storageTextWithLevels(target);
            if (t != null && t.isNotEmpty) return t;
          }
        }
      }
    }
    return null;
  }

  /// Like [_storageText] but prepends `\t` per paragraph level, using
  /// [_storageParagraphLevels] to determine the depth of each line.
  String? _storageTextWithLevels(IwaObject o) {
    final text = _storageText(o);
    if (text == null || text.isEmpty) return null;
    final levels = _storageParagraphLevels(o);
    if (levels.isEmpty) return text;
    final lines = text.split(RegExp(r'\r\n|\r|\n'));
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final lvl = i < levels.length ? levels[i] : 0;
      out.add('${'\t' * lvl}${lines[i]}');
    }
    return out.join('\n');
  }

  /// Flattens group drawables (`TSD.GroupArchive`) and tree structures
  /// (`TSD.TreeArchive`, typeId 3008) into their leaf children.
  ///
  /// Trees carry their content in a recursive field-2 reference structure:
  /// t3008 nodes → t2011 text-content leaves → t2001 StorageArchive. Without
  /// flattening, the text in these leaves is invisible to `shapeText` (#1471).
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
      } else if (d.typeId == 3008) {
        hadGroup = true;
        out.addAll(_flattenTree(d, seen));
      } else {
        out.add(d);
      }
    }
    return (out, hadGroup);
  }

  /// Walks a `TSD.TreeArchive` (typeId 3008) depth-first, collecting its
  /// text-content leaves (typeId 2011) as drawables. Tree nodes (t3008) are
  /// traversed but not emitted; non-tree, non-text children are emitted as-is
  /// so images or other content inside a tree are not lost.
  List<IwaObject> _flattenTree(IwaObject node, Set<int> seen) {
    final out = <IwaObject>[];
    for (final child in doc.resolveReferences(node, 2)) {
      if (!seen.add(child.id)) continue;
      if (child.typeId == 3008) {
        out.addAll(_flattenTree(child, seen));
      } else {
        out.add(child);
      }
    }
    return out;
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
    // Keynote bewaart draaien, spiegelen en bijsnijden in de IWA-structuur en
    // niet in de afbeelding zelf; bak ze in de pixels, want OciDeck zet een
    // afbeelding zonder eigen geometrie op de dia.
    final geometry = _drawableGeometry(o);
    for (final dataId in dataIds) {
      final fileName = doc.dataFileName(dataId);
      if (fileName == null) continue;
      final bytes = ctx!.readPartBytes('Data/$fileName');
      if (bytes != null && bytes.isNotEmpty) {
        final raw = Uint8List.fromList(bytes);
        images.add(
          SourceImage(
            bytes: geometry.isIdentity
                ? raw
                : bakeImportGeometry(raw, geometry, fileName),
            ext: _ext(fileName),
            name: fileName,
          ),
        );
      }
    }
    return images;
  }

  /// De geometrie die Keynote op de afbeelding(en) van [o] legt.
  ///
  /// Alles op één na zit in de IWA-transform: drawable super (field 1) →
  /// geometry (field 1), met de hoek op field 4 (float32, graden tégen de klok
  /// in) en het spiegelen in de vlaggen op field 3 — bit 4 horizontaal, bit 8
  /// verticaal, naast de bits 1 en 2 die alleen zeggen dat positie en maat
  /// gevuld zijn. De uitsnede staat apart, zie [_maskCrop].
  ///
  /// Keynote honoreert de EXIF-orientatietag, dus al deze maten tellen vanaf de
  /// rechtgezette foto — precies wat `img.decodeImage` al oplevert.
  ImportImageGeometry _drawableGeometry(IwaObject o) {
    final holder = _geometryHolder(o);
    final geometry = holder == null ? null : _readGeometry(holder);
    if (holder == null || geometry == null) {
      return const ImportImageGeometry(sourceHonoursExif: true);
    }
    final flags = geometry.varint(3) ?? 0;
    return ImportImageGeometry(
      crop: _maskCrop(holder, geometry),
      flipHorizontal: flags & _flipHorizontalFlag != 0,
      flipVertical: flags & _flipVerticalFlag != 0,
      // Keynote telt tégen de klok in, `bakeImportGeometry` met de klok mee.
      clockwiseDegrees: -(geometry.float32(4) ?? 0),
      sourceHonoursExif: true,
    );
  }

  /// De uitsnede uit het masker van [image], als fractie van de bron.
  ///
  /// `TSD.ImageArchive` field 5 wijst naar een `TSD.MaskArchive` (type 3006)
  /// waarvan de geometrie het zichtbare venster is — positie en maat gemeten
  /// binnen het kader van de afbeelding zelf, vóór spiegelen en draaien. De
  /// afbeelding staat dus groter op de dia dan wat je ziet: het masker is het
  /// gat waar ze doorheen kijkt.
  ///
  /// Een masker in een andere vorm dan een rechthoek (Keynote kan door een
  /// figuur maskeren) levert hier zijn omhullende rechthoek op; die vorm valt
  /// in een dia-afbeelding van OciDeck niet weer te geven.
  ImportCrop? _maskCrop(IwaObject image, ProtoMessage geometry) {
    final refId = image.message.message(_maskField)?.varint(1);
    if (refId == null) return null;
    final mask = doc.resolveReference(image, refId);
    if (mask == null || mask.typeId != _maskTypeId) return null;
    final window = _readGeometry(mask);
    if (window == null) return null;

    final width = geometry.message(2)?.float32(1) ?? 0;
    final height = geometry.message(2)?.float32(2) ?? 0;
    final visibleWidth = window.message(2)?.float32(1) ?? 0;
    final visibleHeight = window.message(2)?.float32(2) ?? 0;
    if (width <= 0 || height <= 0) return null;
    if (visibleWidth <= 0 || visibleHeight <= 0) return null;

    final left = window.message(1)?.float32(1) ?? 0;
    final top = window.message(1)?.float32(2) ?? 0;
    return importCrop(
      left: left / width,
      top: top / height,
      right: (width - left - visibleWidth) / width,
      bottom: (height - top - visibleHeight) / height,
    );
  }

  /// Het object waarvan de geometrie geldt voor de afbeelding(en) van [o]:
  /// [o] zelf wanneer die er een draagt, anders het eerste geneste
  /// image-achtige object dat er wel een heeft.
  IwaObject? _geometryHolder(IwaObject o) {
    if (_readGeometry(o) != null) return o;
    for (final f in o.message.fields.keys) {
      final refId = o.message.message(f)?.varint(1);
      if (refId == null) continue;
      final target = doc.resolveReference(o, refId);
      if (target == null || !_imageLikeTypeIds.contains(target.typeId)) {
        continue;
      }
      if (_readGeometry(target) != null) return target;
    }
    return null;
  }

  /// De `TSD.GeometryArchive` van [o]: drawable super (field 1) → geometry
  /// (field 1), of `null` wanneer die ontbreekt.
  ProtoMessage? _readGeometry(IwaObject o) => o.message.message(1)?.message(1);

  /// `TSD.ImageArchive` field 5 → het masker; `TSD.MaskArchive` is type 3006.
  static const _maskField = 5;
  static const _maskTypeId = 3006;

  /// Vlaggen in `TSD.GeometryArchive` field 3.
  static const _flipHorizontalFlag = 4;
  static const _flipVerticalFlag = 8;

  /// Object types that may contain image `DataReference` data.
  static const _imageLikeTypeIds = {2022, 2023, 3005, 6003, 6004, 6005, 6247};

  /// Recursively collect `DataReference` data ids from [o] and its referenced
  /// image-like objects. Treats a nested message as a `TSP.DataReference` when
  /// its first field (field 1) resolves to a `Data/` file, and as a
  /// `TSP.Reference` to be followed when the first field resolves to an object.
  Set<int> _collectImageDataIds(IwaObject o, Set<int> seen) {
    if (!seen.add(o.id)) return const {};
    final ids = <int>{};

    // Try the canonical image data fields first. Keynote stores a small
    // thumbnail preview naast elke volledige afbeelding: field 12
    // (`thumbnailData`, naast de volle `data` op field 11) en field 16
    // (`thumbnailAdjustedImageData`, naast de volle `adjustedImageData` op
    // field 15). Beide thumbnails importeren geeft elke aangepaste
    // afbeelding dubbel in de bibliotheek: één normaal, één small (#1468).
    for (final field in const [11, 15, 17]) {
      final dataId = _dataReferenceId(o, field);
      if (dataId != null) {
        ids.add(doc.resolveDataReference(o, dataId));
      }
    }

    // Fall back to following references to image-like objects. Skip the
    // thumbnail fields (12 en 16) here too — they're DataReferences die hier
    // anders als geldige data werden herkend en tóch meegenomen.
    for (final field in o.message.fields.keys) {
      if (field == 12 || field == 16) continue;
      final sub = o.message.message(field);
      if (sub == null) continue;
      final refId = sub.varint(1);
      if (refId == null) continue;
      // Volg alleen referenties naar image-like objecten — behandel
      // non-canonical fields NIET als DataReference. Object-IDs en data-IDs
      // delen een namespace, dus een style-referentie (field 3 → obj 111,
      // type 3016) kan colliden met een data-ID (111 → image51-111.png) en
      // zo een template-afbeelding op elke dia injecteren (#1478).
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
