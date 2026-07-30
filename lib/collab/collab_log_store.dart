// The append-only log the async collaboration transport reads and writes
// (`docs/design/COLLABORATION.md` §10, Fase 0.5). A store is a numbered sequence
// of opaque records: participants append at the next free sequence number and
// poll for records others appended. The *ordering* the collab layer needs
// (§5.6) is the sequence order; the store guarantees only that a taken sequence
// number cannot be silently overwritten.
//
// [WebdavAsyncTransport] is written against this interface, not against WebDAV,
// so it can be driven end-to-end in tests by [InMemoryCollabLogStore] with no
// server — the same "seam for testability" reasoning that lets [CollabSession]
// take a [CollabTransport]. [WebdavCollabLogStore] is the production binding
// over the Nextcloud/WebDAV a user already configured (no new dependency).

import 'dart:convert';

import '../services/webdav_service.dart';

/// A numbered append-only log of opaque JSON records.
abstract interface class CollabLogStore {
  /// The sequence numbers currently in the log. Order is unspecified; the
  /// caller sorts. Never throws for an empty/not-yet-created log — it returns
  /// an empty list, so "no session yet" and "session with no ops" look alike.
  Future<List<int>> listSequences();

  /// The record stored at [seq]. Throws if nothing is there.
  Future<String> read(int seq);

  /// Append [record] at [seq] **iff** [seq] is still free. Returns `true` when
  /// this writer took the slot, `false` when someone else already holds it —
  /// the caller then retries at a higher number. This is the whole concurrency
  /// contract: it makes the log an ordered sequence no write can clobber.
  Future<bool> append(int seq, String record);

  /// The session baseline written by [writeSnapshot], or `null` if none has been
  /// written yet (a joiner arriving before the owner posted one). The snapshot
  /// is a single record beside the numbered log, not part of it (§5.2).
  Future<String?> readSnapshot();

  /// Write (or overwrite) the session baseline. Unlike an op append this is
  /// unconditional: the authority owns the snapshot and re-bases it as it likes;
  /// there is no racing writer to guard against (only the authority writes it).
  Future<void> writeSnapshot(String snapshot);

  /// The advisory authority beacon (§5.3), or `null` if none has been written
  /// (a session predating owner-drop handover). Like the snapshot it is a single
  /// named record beside the numbered log, not part of it. It names who currently
  /// assigns versions and carries a liveness tick the authority bumps each poll;
  /// a frozen tick is how a successor infers the authority dropped. It is
  /// *advisory* — WebDAV write access is the only real gate on the sidecar, so a
  /// reader treats the beacon as input, never as authorisation.
  Future<String?> readBeacon();

  /// Write (or overwrite) the authority beacon. Unconditional, like the snapshot:
  /// the beacon is last-write-wins and holds no state the numbered log does not
  /// already carry authoritatively, so a lost race just means the next poll reads
  /// a fresher beacon. Convergence rests on the coordinator's read→decide→write
  /// cycle, not on a conditional write here.
  Future<void> writeBeacon(String beacon);
}

/// An in-process log shared by several transports — the store equivalent of
/// `LoopbackHub`. This is the whole store layer for tests: append is a
/// first-writer-wins map insert, exactly as a conditional `PUT` behaves.
class InMemoryCollabLogStore implements CollabLogStore {
  final Map<int, String> _records = {};

  @override
  Future<List<int>> listSequences() async => _records.keys.toList()..sort();

  @override
  Future<String> read(int seq) async {
    final record = _records[seq];
    if (record == null) throw StateError('no collab log record at $seq');
    return record;
  }

  @override
  Future<bool> append(int seq, String record) async {
    if (_records.containsKey(seq)) return false;
    _records[seq] = record;
    return true;
  }

  String? _snapshot;

  @override
  Future<String?> readSnapshot() async => _snapshot;

  @override
  Future<void> writeSnapshot(String snapshot) async => _snapshot = snapshot;

  String? _beacon;

  @override
  Future<String?> readBeacon() async => _beacon;

  @override
  Future<void> writeBeacon(String beacon) async => _beacon = beacon;
}

/// The production store: one small file per record in a sidecar directory on
/// the user's WebDAV, appended with a conditional `PUT` (`If-None-Match: *`) so
/// two writers racing for the same sequence number cannot both win. The deck
/// `.md` is never touched (P2): the log lives beside it, transient.
class WebdavCollabLogStore implements CollabLogStore {
  WebdavCollabLogStore({required this.service, required this.opsDir});

  final WebdavService service;

  /// The sidecar directory that holds the record files, relative to the WebDAV
  /// root (e.g. `decks/talk.ocideck-collab/ops`). No trailing slash.
  final String opsDir;

  static const _suffix = '.json';

  String _pathFor(int seq) =>
      '$opsDir/${seq.toString().padLeft(12, '0')}$_suffix';

  /// The baseline sits inside the ops directory under a non-numeric name, so
  /// [listSequences] ignores it (it only accepts padded-integer records) while
  /// it still travels with the log in the one sidecar.
  String get _snapshotPath => '$opsDir/snapshot$_suffix';

  /// The beacon sits beside the snapshot under its own non-numeric name, so
  /// [listSequences] ignores it too.
  String get _beaconPath => '$opsDir/beacon$_suffix';

  @override
  Future<List<int>> listSequences() async {
    final List<WebdavEntry> entries;
    try {
      entries = await service.list(opsDir);
    } on WebdavException catch (e) {
      // A not-yet-created ops directory is "no records", not an error: the
      // first appender creates it. Anything else is a real failure.
      if (e.kind == WebdavError.notFound) return const [];
      rethrow;
    }
    final seqs = <int>[];
    for (final entry in entries) {
      if (entry.isCollection) continue;
      // Skip non-record siblings (a snapshot, a stray file): forward-compat.
      final seq = _seqOf(entry.name);
      if (seq != null) seqs.add(seq);
    }
    seqs.sort();
    return seqs;
  }

  /// Parse the sequence number out of a record filename, or null if the name is
  /// not one of ours (a snapshot, a stray file) so it is quietly ignored.
  static int? _seqOf(String name) {
    if (!name.endsWith(_suffix)) return null;
    return int.tryParse(name.substring(0, name.length - _suffix.length));
  }

  @override
  Future<String> read(int seq) async {
    final file = await service.download(_pathFor(seq));
    return utf8.decode(file.bytes);
  }

  @override
  Future<bool> append(int seq, String record) async {
    try {
      await service.upload(
        _pathFor(seq),
        utf8.encode(record),
        onlyIfAbsent: true,
      );
      return true;
    } on WebdavConflictException {
      // The slot is taken — another participant appended here first. Not an
      // error: the caller retries at the next free number.
      return false;
    }
  }

  @override
  Future<String?> readSnapshot() async {
    try {
      final file = await service.download(_snapshotPath);
      return utf8.decode(file.bytes);
    } on WebdavException catch (e) {
      if (e.kind == WebdavError.notFound) return null; // none posted yet
      rethrow;
    }
  }

  @override
  Future<void> writeSnapshot(String snapshot) async {
    // Unconditional overwrite: only the authority writes the baseline, so there
    // is no If-Match/If-None-Match race to guard (unlike the op records).
    await service.upload(_snapshotPath, utf8.encode(snapshot));
  }

  @override
  Future<String?> readBeacon() async {
    try {
      final file = await service.download(_beaconPath);
      return utf8.decode(file.bytes);
    } on WebdavException catch (e) {
      if (e.kind == WebdavError.notFound) return null; // pre-handover session
      rethrow;
    }
  }

  @override
  Future<void> writeBeacon(String beacon) async {
    // Unconditional overwrite: the beacon is last-write-wins advisory state
    // (§5.3). See the interface doc for why no conditional write is needed here.
    await service.upload(_beaconPath, utf8.encode(beacon));
  }
}
