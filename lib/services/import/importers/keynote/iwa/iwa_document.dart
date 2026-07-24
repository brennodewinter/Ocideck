import 'iwa_archive.dart';
import 'proto_wire.dart';

/// An iWork object graph: every parsed object keyed by id, with helpers to
/// resolve `TSP.Reference` fields and `TSP.DataReference` values to files.
///
/// A `TSP.Reference` in an object's payload is stored as a varint **index** into
/// that object's `MessageInfo.object_references` list, whose entry is the
/// target object's id. [resolveReference] performs that two-step lookup so the
/// reconstructor can traverse the graph (slide -> drawables -> shape ->
/// storage) without knowing Apple's runtime typeId map.
class IwaDocument {
  IwaDocument(this._objects);

  final Map<int, IwaObject> _objects;

  /// Lazily found `TSP.PackageMetadata` object (or `null` if missing).
  ProtoMessage? _metadata;

  /// All objects, keyed by id.
  Map<int, IwaObject> get all => _objects;

  /// The object with [id], or `null`.
  IwaObject? operator [](int id) => _objects[id];

  /// Resolve a `TSP.Reference` read from [from]'s payload.
  ///
  /// Modern iWork stores the referenced object id directly in the payload.
  /// Older files store a zero-based index into [from.objectReferences].
  /// Returns the referenced object or `null` when it cannot be resolved.
  IwaObject? resolveReference(IwaObject from, int refIndex) {
    if (refIndex < 0) return null;
    // Older iWork files store a zero-based index into [from.objectReferences].
    if (refIndex < from.objectReferences.length) {
      return _objects[from.objectReferences[refIndex]];
    }
    // Newer iWork files store the actual object id directly in the payload.
    return _objects[refIndex];
  }

  /// Resolve every `TSP.Reference` field [field] on [from] (repeated or
  /// single) into objects, skipping unresolvable entries.
  ///
  /// Handles the real iWork `TSP.Reference` message encoding, the varint-only
  /// encoding used by test fixtures, and the `TSP.FieldInfo` declared
  /// `ObjectReference` encoding used by newer Keynote files.
  List<IwaObject> resolveReferences(IwaObject from, int field) {
    final out = <IwaObject>[];
    // Real iWork stores `TSP.Reference` as length-delimited messages.
    for (final sub in from.message.messages(field)) {
      final refId = sub.varint(1);
      if (refId == null) continue;
      final target = resolveReference(from, refId);
      if (target != null) out.add(target);
    }
    // Test fixtures and some iWork files store raw reference indices. Newer
    // files use FieldInfo object references per field.
    for (final idx in from.message.varints(field)) {
      final target = resolveReferenceAtField(from, field, idx);
      if (target != null) out.add(target);
    }
    return out;
  }

  /// Resolve a reference encoded as a raw varint in [field] of [from].
  ///
  /// First tries the `FieldInfo` object references list for that field
  /// (used by newer iWork for `ObjectReference` typed fields), then falls back
  /// to the object's global `objectReferences` list or a direct object id.
  IwaObject? resolveReferenceAtField(IwaObject from, int field, int refIndex) {
    if (refIndex < 0) return null;
    final fieldRefs = from.fieldObjectReferences[field];
    if (fieldRefs != null && refIndex < fieldRefs.length) {
      return _objects[fieldRefs[refIndex]];
    }
    return resolveReference(from, refIndex);
  }

  /// Resolve a `TSP.DataReference` identifier to an actual data id.
  ///
  /// Like [resolveReference], newer files store the data id directly, while
  /// older files store an index into [from.dataReferences].
  int resolveDataReference(IwaObject from, int refId) {
    if (refId < 0) return refId;
    final refs = from.dataReferences;
    if (refs.isNotEmpty && refId < refs.length && !refs.contains(refId)) {
      return refs[refId];
    }
    return refId;
  }

  /// Resolve a `TSP.DataReference` identifier to a file name inside the
  /// `.key` bundle's `Data/` directory. Returns `null` when the metadata is
  /// missing or the identifier is not listed.
  String? dataFileName(int dataId) {
    final meta = _packageMetadata;
    if (meta == null) return null;
    for (final dataInfo in meta.messages(4)) {
      if (dataInfo.varint(1) == dataId) {
        final fileName = dataInfo.string(4);
        if (fileName != null && fileName.isNotEmpty) return fileName;
        return dataInfo.string(3);
      }
    }
    return null;
  }

  /// The top-level `TSP.PackageMetadata` message, if one was found.
  ProtoMessage? get packageMetadata => _packageMetadata;

  ProtoMessage? get _packageMetadata {
    if (_metadata != null) return _metadata;
    // Common object id for the top-level TSP.PackageMetadata.
    if (_objects[2] case final obj? when _looksLikePackageMetadata(obj)) {
      _metadata = obj.message;
      return _metadata;
    }
    for (final obj in _objects.values) {
      if (_looksLikePackageMetadata(obj)) {
        _metadata = obj.message;
        return _metadata;
      }
    }
    return null;
  }

  bool _looksLikePackageMetadata(IwaObject obj) {
    final datas = obj.message.messages(4);
    if (datas.isEmpty) return false;
    return datas.first.string(3) != null;
  }
}
