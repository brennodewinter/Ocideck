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
}
