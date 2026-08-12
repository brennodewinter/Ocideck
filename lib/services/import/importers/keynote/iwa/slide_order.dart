import 'iwa_archive.dart';
import 'iwa_document.dart';

/// Recovers the slide objects of a Keynote document in their real presentation
/// order from an iWork object graph.
///
/// The order is discovered through five routes, tried in turn, because a
/// `.key` encodes it differently across versions and fixtures:
/// 1. `KN.ShowArchive.slideTree` — the authoritative slide order, walked
///    depth-first through the SlideNode list (newer Keynote files).
/// 2. `TSP.PackageMetadata` Slide components (fallback for files without a
///    ShowArchive, but the component order is storage order, not presentation
///    order — see #1471).
/// 3. A `TSP.ObjectContainer` (type id 10) whose objects list contains
///    SlideArchive objects.
/// 4. The SlideNode tree's depth-first traversal.
/// 5. Every slide-like object in parse order.
///
/// Apple's runtime `TSPRegistry` (typeId -> class) is not available, so slide
/// objects are detected **structurally** from their field shapes.
class SlideOrder {
  SlideOrder(this.doc);

  final IwaDocument doc;

  /// The slide objects in source order:
  /// 1. `KN.ShowArchive.slideTree` (authoritative, newer Keynote files).
  /// 2. `TSP.PackageMetadata` Slide components (storage order, not presentation
  ///    order — only used when no ShowArchive is available).
  /// 3. A `TSP.ObjectContainer` (type id 10) whose objects list contains
  ///    SlideArchive objects.
  /// 4. The SlideNode tree's depth-first traversal.
  /// 5. Every slide-like object in parse order.
  List<IwaObject> orderedSlideObjects() {
    final show = _slidesFromShowArchive();
    if (show != null) return show;
    final comps = _slidesFromPackageMetadata();
    if (comps != null) return comps;
    final container = _slidesFromObjectContainer();
    if (container != null) return container;
    final tree = _slidesFromTree();
    if (tree != null) return tree;
    return doc.all.values.where(_looksLikeSlide).toList();
  }

  /// Follow `KN.DocumentArchive.show` (field 2) → `KN.ShowArchive.slideTree`
  /// (field 3) → `KN.SlideTreeArchive` → repeated field 2 (SlideNode refs) →
  /// each SlideNode's `slide` (field 2) → `KN.SlideArchive`.
  ///
  /// This is the authoritative slide order — the SlideTree encodes the exact
  /// sequence the presenter sees. The PackageMetadata component list is storage
  /// order and may differ (#1471).
  List<IwaObject>? _slidesFromShowArchive() {
    // Find the ShowArchive via the DocumentArchive (typeId 1, field 2).
    for (final doc1 in doc.all.values.where((o) => o.typeId == 1)) {
      final show = doc.resolveReferences(doc1, 2).firstOrNull;
      if (show == null) continue;

      // ShowArchive.slideTree = field 3. This is a nested submessage
      // (SlideTreeArchive), not a direct TSP.Reference — decode it.
      final treeMsg = show.message.message(3);
      if (treeMsg == null) continue;

      // SlideTreeArchive stores SlideNode refs in repeated field 2 (newer
      // files) or field 1 (rootSlideNode, older schema). Try both.
      final out = <IwaObject>[];
      for (final refField in const [2, 1]) {
        for (final ref in treeMsg.messages(refField)) {
          final refId = ref.varint(1);
          if (refId == null) continue;
          final node = doc.resolveReference(show, refId);
          if (node == null) continue;
          // Walk this SlideNode: it may be a leaf (slide ref on field 2)
          // or a subtree (children on field 1).
          _walkSlideNode(node, out);
        }
        if (out.isNotEmpty) break;
      }
      if (out.isNotEmpty) return out;
    }
    return null;
  }

  /// Walk a SlideNode depth-first: emit its slide (field 2) if it resolves to
  /// a slide-like object, then recurse into children (field 1).
  void _walkSlideNode(IwaObject node, List<IwaObject> out) {
    final slide = doc.resolveReferences(node, 2).firstOrNull;
    if (slide != null && _looksLikeSlide(slide)) {
      out.add(slide);
    }
    for (final child in doc.resolveReferences(node, 1)) {
      _walkSlideNode(child, out);
    }
  }

  /// Use the `TSP.PackageMetadata` `components` list to find the actual slide
  /// components. Each `Slide` component's first object is the root drawable for
  /// that slide and contains the real title/body text.
  ///
  /// The component's object reference (field 1) is a `TSP.Reference` submessage
  /// in real iWork files (wire type 2), but some fixtures encode it as a raw
  /// varint. Both are handled.
  List<IwaObject>? _slidesFromPackageMetadata() {
    final meta = doc.packageMetadata;
    if (meta == null) return null;
    final slides = <IwaObject>[];
    for (final comp in meta.messages(3)) {
      final locator = comp.string(3);
      if (locator == null || !locator.startsWith('Slide-')) continue;
      // Field 1 is TSP.Reference: een submessage met object_id op veld 1,
      // óf een raw varint in testfixtures.
      final id = comp.varint(1) ?? comp.message(1)?.varint(1);
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
    // SlideNode-achtige objecten: hebben een slide-ref (veld 2) en/of
    // children (repeated ref veld 1). Nieuwere bestanden encoderen deze
    // als ObjectReference raw varints, dus we gebruiken field-aware
    // resolutie.
    //
    // In echte Keynote-bestanden is typeId 5 de Slide zelf, geen SlideNode:
    // hij heeft drawables als children (veld 1) maar geen slide-ref (veld 2).
    // Testfixtures gebruiken typeId 5 wél voor leaf-SlideNodes (met slide-ref).
    // Een echte SlideNode heeft of een slide-ref, of children die zelf weer
    // SlideNodes zijn. Een Slide met drawable-children voldoet niet — zijn
    // children zijn geen SlideNodes.
    final nodes = <IwaObject>[];
    final childIds = <int>{};
    for (final o in doc.all.values) {
      if (!_slideNodeTypeIds.contains(o.typeId)) continue;
      final children = doc.resolveReferences(o, 1);
      final slide = doc.resolveReferences(o, 2).firstOrNull;
      if (children.isEmpty && slide == null) continue;
      // Geen slide-ref en children zijn geen SlideNodes: dit is een Slide,
      // geen SlideNode. Sla hem over.
      if (slide == null && children.isNotEmpty) {
        final hasNodeChildren = children.any(
          (c) => _slideNodeTypeIds.contains(c.typeId),
        );
        if (!hasNodeChildren) continue;
      }
      if (slide != null && !_looksLikeSlide(slide)) continue;
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
}
