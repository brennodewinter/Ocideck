import 'dart:async';
import 'dart:convert';

import '../../models/ociserve_exam.dart';
import '../secret_store.dart';

/// Serialises read-modify-write cycles that share one encrypted outbox key.
class OciServeOutboxMutex {
  static final Map<String, Future<void>> _writes = {};

  static Future<T> serialized<T>(
    String baseUrl,
    Future<T> Function() operation,
  ) async {
    final prior = _writes[baseUrl] ?? Future<void>.value();
    final turn = Completer<void>();
    final queued = prior.whenComplete(() => turn.future);
    _writes[baseUrl] = queued;
    await prior;
    try {
      return await operation();
    } finally {
      turn.complete();
      if (identical(_writes[baseUrl], queued)) {
        unawaited(_writes.remove(baseUrl));
      }
    }
  }
}

/// Scope binding for the encrypted OciServe outbox.
class OciServeExamOutboxScope {
  const OciServeExamOutboxScope({
    required this.baseUrl,
    required this.accountId,
  });

  final String baseUrl;
  final String accountId;
}

/// Persists only the minimum request needed for an idempotent answer replay.
class OciServeExamOutbox {
  OciServeExamOutbox({
    required SecretStore secrets,
    required OciServeExamOutboxScope Function() scope,
  }) : this._(secrets, scope);

  OciServeExamOutbox._(this._secrets, this._scope);

  static const _maximumEntries = 100;
  static const _maximumEncodedBytes = 64 * 1024;
  final SecretStore _secrets;
  final OciServeExamOutboxScope Function() _scope;

  Future<OciServeExamAnswerMutation?> read(String organizationId) async {
    final scope = _scope();
    return OciServeOutboxMutex.serialized(scope.baseUrl, () async {
      final entries = await _read(scope.baseUrl);
      final matches = entries.where(
        (entry) =>
            entry['kind'] == 'exam_answer_v1' &&
            entry['account_id'] == scope.accountId &&
            entry['organization_id'] == organizationId,
      );
      if (matches.length > 1) throw const FormatException('duplicate answer');
      if (matches.isEmpty) return null;
      return OciServeExamAnswerMutation.fromJson(
        Map<String, Object?>.from(matches.single)..remove('account_id'),
      );
    });
  }

  Future<void> write(OciServeExamAnswerMutation mutation) async {
    OciServeExamAnswerMutation.fromJson(mutation.toJson());
    final scope = _scope();
    await OciServeOutboxMutex.serialized(scope.baseUrl, () async {
      final entries = await _read(scope.baseUrl)
        ..removeWhere(
          (entry) =>
              entry['kind'] == 'exam_answer_v1' &&
              entry['account_id'] == scope.accountId &&
              entry['organization_id'] == mutation.organizationId,
        );
      if (entries.length >= _maximumEntries) {
        throw const FormatException('OciServe outbox full');
      }
      entries.add({...mutation.toJson(), 'account_id': scope.accountId});
      await _write(scope.baseUrl, entries);
    });
  }

  Future<void> remove(OciServeExamAnswerMutation mutation) async {
    final scope = _scope();
    await OciServeOutboxMutex.serialized(scope.baseUrl, () async {
      final entries = await _read(scope.baseUrl)
        ..removeWhere(
          (entry) =>
              entry['kind'] == 'exam_answer_v1' &&
              entry['account_id'] == scope.accountId &&
              entry['organization_id'] == mutation.organizationId &&
              entry['attempt_id'] == mutation.attemptId &&
              entry['attempt_item_id'] == mutation.attemptItemId &&
              entry['idempotency_key'] == mutation.idempotencyKey,
        );
      await _write(scope.baseUrl, entries);
    });
  }

  Future<List<Map<String, Object?>>> _read(String baseUrl) async {
    final encoded = await _secrets.readOciServeOutbox(baseUrl);
    if (encoded == null || encoded.isEmpty) return [];
    if (utf8.encode(encoded).length > _maximumEncodedBytes) {
      throw const FormatException('OciServe outbox too large');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.length > _maximumEntries) {
      throw const FormatException('invalid OciServe outbox');
    }
    return decoded
        .map((entry) => Map<String, Object?>.from(entry as Map))
        .toList();
  }

  Future<void> _write(
    String baseUrl,
    List<Map<String, Object?>> entries,
  ) async {
    if (entries.isEmpty) return _secrets.deleteOciServeOutbox(baseUrl);
    final encoded = jsonEncode(entries);
    if (utf8.encode(encoded).length > _maximumEncodedBytes) {
      throw const FormatException('OciServe outbox too large');
    }
    await _secrets.writeOciServeOutbox(baseUrl, encoded);
  }
}
