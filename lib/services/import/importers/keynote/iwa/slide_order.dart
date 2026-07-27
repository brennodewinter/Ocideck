import 'iwa_archive.dart';
import 'iwa_document.dart';

/// Recovers the slide objects of a Keynote document in their real presentation
/// order from an iWork object graph.
///
/// The order is discovered through four routes, tried in turn, because a
/// `.key` encodes it differently across versions and fixtures:
/// 1. `TSP.PackageMetadata` Slide components (newer Keynote files).
/// 2. A `TSP.ObjectContainer` (type id 10) whose objects list contains
///    SlideArchive objects.
/// 3. The SlideNode tree's depth-first traversal.
/// 4. Every slide-like object in parse order.
///
/// Apple's runtime `TSPRegistry` (typeId -> class) is not available, so slide
/// objects are detected **structurally** from their field shapes.
class SlideOrder {
  SlideOrder(this.doc);

  final IwaDocument doc;

  /// The slide objects in source order:
  /// 1. `TSP.PackageMetadata` Slide components (newer Keynote files).
  /// 2. A `TSP.ObjectContainer` (type id 10) whose objects list contains
  ///    SlideArchive objects.
  /// 3. The SlideNode tree's depth-first traversal.
  /// 4. Every slide-like object in parse order.
  List<IwaObject> orderedSlideObjects() {
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
}
