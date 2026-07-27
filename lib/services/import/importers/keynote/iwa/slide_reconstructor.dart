import 'dart:convert';
import 'dart:typed_data';

import '../../../models/body_block.dart';
import '../../../models/conversion_issue.dart';
import '../../../models/source_chart.dart';
import '../../../models/source_image.dart';
import '../../../models/source_slide.dart';
import '../../../models/source_table.dart';
import '../../../models/source_video.dart';
import '../../../pipeline/parse_guard.dart';
import '../key_context.dart';
import '../key_text_salvage.dart';
import 'chart_reconstructor.dart';
import 'iwa_archive.dart';
import 'iwa_document.dart';
import 'media_reconstructor.dart';
import 'table_reconstructor.dart';

/// Schema-aware reconstruction of [SourceSlide]s from an iWork object graph,
/// using the public iWork proto field layouts (obriensp/iWorkFileFormat):
///
/// - `KN.DocumentArchive.show` (field 2) -> `KN.ShowArchive.slideTree` (field 3)
///   -> `KN.SlideTreeArchive.rootSlideNode` (field 1) -> `KN.SlideNodeArchive`
///   (`children` = field 1 repeated Reference, `slide` = field 2 Reference).
///   The SlideNode tree is walked depth-first to recover the **real slide
///   order**; each node's `slide` ref points at a `KN.SlideArchive`.
/// - `KN.SlideArchive`: `titlePlaceholder` (5), `bodyPlaceholder` (6),
///   `drawables` (7, repeated Reference), `name` (10).
/// - `TSWP.ShapeInfoArchive`: `super` = ShapeArchive (field 1, submessage),
///   `containedStorage` (field 2, Reference) -> a StorageArchive.
/// - `TSWP.StorageArchive`: `text` (field 3, repeated string).
/// - `TSD.GroupArchive`: `children` (field 2, repeated Reference).
///
/// Apple's runtime `TSPRegistry` (typeId -> class) is not available, so message
/// types are detected **structurally** from their field shapes and reference
/// targets. When the SlideNode tree cannot be found, slides are emitted in
/// parse (insertion) order as a best-effort fallback.
class SlideReconstructor {
  SlideReconstructor(this.doc, {this.ctx});

  final IwaDocument doc;
  final KeyContext? ctx;

  /// Conversion issues raised while reconstructing this deck.
  final List<ConversionIssue> issues = [];

  late final _tableReconstructor = TableReconstructor(doc);
  late final _chartReconstructor = ChartReconstructor(doc);
  late final _mediaReconstructor = MediaReconstructor(doc, ctx: ctx);

  /// Reconstruct slides in source order. Text-bearing slides are returned as
  /// bullet slides; image-only slides are also returned, carrying the `Data/`
  /// image when [ctx] is available. Table-, chart- and media-bearing slides are
  /// also returned.
  List<SourceSlide> reconstruct() {
    issues.clear();
    final ordered = _orderedSlideObjects();
    final slides = <SourceSlide>[];
    for (var pos = 0; pos < ordered.length; pos++) {
      final obj = ordered[pos];
      // Isoleer een onverwachte fout tot déze dia (#877): één beschadigd
      // slide-object mag de reconstructie van de rest niet afbreken. Het verlies
      // gaat naar de deckbrede notitie via `issues`.
      guardParseVoid(
        sink: issues,
        slideIndex: pos,
        component: IssueComponent.slide,
        feature: 'Dia-inhoud',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'KeyImporter: dia ${pos + 1}',
        body: () {
          final content = _slideContent(obj, pos);
          if (content.text == null &&
              content.images.isEmpty &&
              content.table == null &&
              content.chart == null &&
              content.video == null &&
              content.audioFileName == null) {
            return; // blank — nothing to salvage.
          }
          slides.add(_buildSlide(obj, pos, content));
        },
      );
    }
    return slides;
  }

  /// The slide objects in source order:
  /// 1. `TSP.PackageMetadata` Slide components (newer Keynote files).
  /// 2. A `TSP.ObjectContainer` (type id 10) whose objects list contains
  ///    SlideArchive objects.
  /// 3. The SlideNode tree's depth-first traversal.
  /// 4. Every slide-like object in parse order.
  List<IwaObject> _orderedSlideObjects() {
    final comps = _slidesFromPackageMetadata();
    if (comps != null) return comps;
    final container = _slidesFromObjectContainer();
    if (container != null) return container;
    final tree = _slidesFromTree();
    if (tree != null) return tree;
    return doc.all.values.where(_looksLikeSlide).toList();
  }

  /// Use the `TSP.PackageMetadata` `components` list to find the actual slide
  /// components. Each `Slide` component's first object is the root drawable for
  /// that slide and contains the real title/body text.
  List<IwaObject>? _slidesFromPackageMetadata() {
    final meta = doc.packageMetadata;
    if (meta == null) return null;
    final slides = <IwaObject>[];
    for (final comp in meta.messages(3)) {
      final locator = comp.string(3);
      if (locator == null || !locator.startsWith('Slide-')) continue;
      final id = comp.varint(1);
      if (id == null) continue;
      final obj = doc[id];
      if (obj == null || !_looksLikeSlide(obj)) continue;
      slides.add(obj);
    }
    return slides.isEmpty ? null : slides;
  }

  /// If the document contains a `TSP.ObjectContainer` (type id 10) listing
  /// SlideArchive objects, return them in the stored order.
  List<IwaObject>? _slidesFromObjectContainer() {
    IwaObject? bestContainer;
    var bestSlideCount = 0;
    for (final o in doc.all.values) {
      if (o.typeId != 10) continue;
      final refs = doc.resolveReferences(o, 2);
      final slides = refs.where(_looksLikeSlide).toList();
      if (slides.length > bestSlideCount) {
        bestSlideCount = slides.length;
        bestContainer = o;
      }
    }
    if (bestContainer == null) return null;
    final slides = doc
        .resolveReferences(bestContainer, 2)
        .where(_looksLikeSlide)
        .toList();
    return slides.isEmpty ? null : slides;
  }

  /// Walk the SlideNode tree depth-first, collecting each node's `slide`
  /// object. Returns `null` when no SlideNode graph could be recovered.
  /// Object type ids used for `SlideNode` entries in the IWA registry.
  /// Newer Keynote files use 6005/6006; older files and test fixtures use 4/5.
  static const _slideNodeTypeIds = {4, 5, 6005, 6006};

  List<IwaObject>? _slidesFromTree() {
    // SlideNode-like objects: carry a `slide` ref (field 2) and/or children
    // (repeated ref field 1). Newer files encode these as ObjectReference
    // raw varints, so we use field-aware resolution.
    final nodes = <IwaObject>[];
    final childIds = <int>{};
    for (final o in doc.all.values) {
      if (!_slideNodeTypeIds.contains(o.typeId)) continue;
      final children = doc.resolveReferences(o, 1);
      final slide = doc.resolveReferences(o, 2).firstOrNull;
      if (children.isEmpty && slide == null) continue;
      if (children.isEmpty && slide != null && !_looksLikeSlide(slide)) {
        continue;
      }
      nodes.add(o);
      for (final child in children) {
        childIds.add(child.id);
      }
    }
    if (nodes.isEmpty) return null;

    // The root is the node no other node points at as a child.
    final roots = nodes.where((n) => !childIds.contains(n.id)).toList();
    if (roots.isEmpty) return null;

    final out = <IwaObject>[];
    final visited = <int>{};
    void visit(IwaObject node) {
      if (!visited.add(node.id)) return;
      final slide = doc.resolveReferences(node, 2).firstOrNull;
      if (slide != null && _looksLikeSlide(slide)) out.add(slide);
      for (final child in doc.resolveReferences(node, 1)) {
        visit(child);
      }
    }

    for (final r in roots) {
      visit(r);
    }
    return out.isEmpty ? null : out;
  }

  /// An object is slide-like when it has a title/body placeholder or at least
  /// one drawable reference (regardless of whether those resolve to text).
  ///
  /// Table model objects (TST.TableModelArchive, type id 6001) also carry
  /// numeric `number_of_rows`/`number_of_columns` fields on 6 and 7, so they
  /// are excluded by their iWork type id.
  bool _looksLikeSlide(IwaObject o) {
    if (o.typeId == 6001) return false;
    final msg = o.message;
    // Real Keynote files encode title/body placeholders and drawables as
    // length-delimited TSP.Reference submessages; test fixtures use raw varints.
    return msg.messages(5).isNotEmpty ||
        msg.messages(6).isNotEmpty ||
        msg.messages(7).isNotEmpty ||
        msg.varint(5) != null ||
        msg.varint(6) != null ||
        msg.varints(7).isNotEmpty;
  }

  /// The text, images, table, chart and media recovered from a slide. [text]
  /// is `null` when the slide has no text; [images] is empty when it has no
  /// images.
  ({
    String? text,
    List<SourceImage> images,
    SourceTable? table,
    SourceChart? chart,
    SourceVideo? video,
    String? audioFileName,
    List<ConversionIssue> issues,
  })
  _slideContent(IwaObject o, int slideIndex) {
    final title = _placeholderText(o, 5) ?? o.message.string(10) ?? '';
    final body = <String>[];
    final images = <SourceImage>[];
    final localIssues = <ConversionIssue>[];
    SourceTable? table;
    SourceChart? chart;
    SourceVideo? video;
    String? audioFileName;
    final bodyPlaceholder = _placeholderText(o, 6);
    if (bodyPlaceholder != null) body.add(bodyPlaceholder);
    final (drawables, hadGroup) = _flattenDrawables(
      doc.resolveReferences(o, 7),
    );
    if (hadGroup) {
      localIssues.add(
        ConversionIssue(
          slideIndex: slideIndex,
          feature: 'Groepering',
          description:
              'Gegroepeerde objecten zijn uitgeklapt; groepering en '
              'volgorde binnen de groep gaan verloren.',
          salvagedAs: 'objecten apart overgenomen',
        ),
      );
    }
    for (final drawable in drawables) {
      final drawableImages = _imagesForDrawable(drawable);
      images.addAll(drawableImages);
      final tableResult = _tableForDrawable(drawable, slideIndex);
      if (tableResult != null) {
        if (table == null) {
          table = tableResult;
        } else {
          localIssues.add(
            ConversionIssue(
              slideIndex: slideIndex,
              feature: 'Meerdere tabellen',
              description:
                  'Dia bevat meerdere tabellen; OciDeck ondersteunt er '
                  'maar één per dia.',
              salvagedAs: 'eerste tabel overgenomen',
            ),
          );
        }
      }
      final chartResult = _chartForDrawable(drawable, slideIndex);
      if (chartResult != null) {
        if (chart == null) {
          chart = chartResult;
        } else {
          localIssues.add(
            ConversionIssue(
              slideIndex: slideIndex,
              feature: 'Meerdere grafieken',
              description:
                  'Dia bevat meerdere grafieken; OciDeck ondersteunt er '
                  'maar één per dia.',
              salvagedAs: 'eerste grafiek overgenomen',
            ),
          );
        }
      }
      final media = _mediaForDrawable(drawable, slideIndex);
      if (media.video != null) {
        if (video == null) {
          video = media.video;
        } else {
          localIssues.add(
            ConversionIssue(
              slideIndex: slideIndex,
              feature: 'Meerdere video\'s',
              description:
                  'Dia bevat meerdere video\'s; OciDeck ondersteunt er '
                  'maar één per dia.',
              salvagedAs: 'eerste video overgenomen',
            ),
          );
        }
      }
      if (media.audioFileName != null) {
        if (audioFileName == null) {
          audioFileName = media.audioFileName;
        } else {
          localIssues.add(
            ConversionIssue(
              slideIndex: slideIndex,
              feature: 'Meerdere audio',
              description:
                  'Dia bevat meerdere audiofragmenten; OciDeck ondersteunt '
                  'er maar één per dia.',
              salvagedAs: 'eerste audio overgenomen',
            ),
          );
        }
      }
      final t = _shapeText(drawable);
      if (t != null && t != title && t != bodyPlaceholder) body.add(t);
      if (_isUnhandledDrawable(
        drawable,
        t,
        drawableImages,
        tableResult,
        chartResult,
        media,
      )) {
        localIssues.add(
          ConversionIssue(
            slideIndex: slideIndex,
            feature: 'Vorm of object',
            description:
                'Een niet-tekstuele vorm, lijn of ander object kon niet '
                'worden omgezet.',
            salvagedAs: 'overgeslagen',
          ),
        );
      }
    }
    issues.addAll(localIssues);
    final String? text;
    if (title.trim().isEmpty && body.every((b) => b.trim().isEmpty)) {
      text = null;
    } else {
      text = body.isEmpty ? title : '$title\n${body.join('\n')}';
    }
    return (
      text: text,
      images: images,
      table: table,
      chart: chart,
      video: video,
      audioFileName: audioFileName,
      issues: localIssues,
    );
  }

  SourceSlide _buildSlide(
    IwaObject o,
    int index,
    ({
      String? text,
      List<SourceImage> images,
      SourceTable? table,
      SourceChart? chart,
      SourceVideo? video,
      String? audioFileName,
      List<ConversionIssue> issues,
    })
    content,
  ) {
    final notes = _notesText(o);
    final title = content.text == null
        ? (o.message.string(10)?.trim() ?? '')
        : content.text!.split(RegExp(r'\r\n|\r|\n')).first.trim();
    final blocks = <BodyBlock>[];
    if (content.text != null) {
      var order = 0;
      for (final line in content.text!.split(RegExp(r'\r\n|\r|\n')).skip(1)) {
        final t = line.trim();
        if (t.isEmpty) continue;
        blocks.add(
          BodyBlock(
            kind: BodyBlockKind.bullet,
            text: t,
            level: 0,
            order: order++,
          ),
        );
      }
    }
    return SourceSlide(
      index: index,
      title: title,
      bodyBlocks: blocks,
      images: content.images,
      table: content.table,
      chart: content.chart,
      video: content.video,
      audioFileName: content.audioFileName,
      notes: notes ?? '',
    );
  }

  /// Speaker-note text for a slide, via `SlideArchive.note` (field 27) ->
  /// `NoteArchive.containedStorage` (field 1) -> `StorageArchive.text` (field 3).
  /// `null` when the slide has no note or the chain does not resolve.
  String? _notesText(IwaObject slide) {
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
  String? _placeholderText(IwaObject o, int field) {
    for (final shape in doc.resolveReferences(o, field)) {
      final t = _shapeText(shape);
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  /// Text of a drawable. A ShapeInfoArchive points (field 2) at a StorageArchive;
  /// a GroupArchive lists children (repeated field 2). Real iWork files encode
  /// references as `TSP.Reference` submessages, and newer files wrap the actual
  /// ShapeInfoArchive / StorageArchive in extra drawable objects, so we walk the
  /// reachable object graph (avoiding cycles) to find any StorageArchive text.
  String? _shapeText(IwaObject o, {Set<int>? visited}) {
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

    // Otherwise, follow every reference field looking for a StorageArchive.
    for (final field in o.message.fields.keys.toList()..sort()) {
      for (final target in doc.resolveReferences(o, field)) {
        if (_isStorage(target)) {
          final t = _storageText(target);
          if (t != null && t.isNotEmpty) return t;
        }
        final t = _shapeText(target, visited: seen);
        if (t != null && t.isNotEmpty) return t;
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

  /// The table contained by a drawable, if this drawable is a `TableInfoArchive`.
  SourceTable? _tableForDrawable(IwaObject o, int slideIndex) {
    final table = _tableReconstructor.reconstruct(o, slideIndex);
    issues.addAll(_tableReconstructor.issues);
    return table;
  }

  /// The chart contained by a drawable, if this drawable is a `ChartDrawableArchive`.
  SourceChart? _chartForDrawable(IwaObject o, int slideIndex) {
    final chart = _chartReconstructor.reconstruct(o, slideIndex);
    issues.addAll(_chartReconstructor.issues);
    return chart;
  }

  /// The media (video or audio) contained by a drawable, if this drawable is a
  /// `TSD.MovieArchive`.
  ({SourceVideo? video, String? audioFileName}) _mediaForDrawable(
    IwaObject o,
    int slideIndex,
  ) {
    return _mediaReconstructor.extract(o, slideIndex);
  }

  /// Flattens group drawables (`TSD.GroupArchive`) into their leaf children.
  /// Returns the flattened list plus a flag that is true when a group was
  /// expanded.
  (List<IwaObject>, bool) _flattenDrawables(
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
        final (flattened, nestedGroup) = _flattenDrawables(
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
  bool _isUnhandledDrawable(
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
  List<SourceImage> _imagesForDrawable(IwaObject o, {Set<int>? visited}) {
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

    // Try the canonical image data fields first.
    for (final field in const [11, 12, 15, 16, 17]) {
      final dataId = _dataReferenceId(o, field);
      if (dataId != null) {
        ids.add(doc.resolveDataReference(o, dataId));
      }
    }

    // Fall back to following references to image-like objects.
    for (final field in o.message.fields.keys) {
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
