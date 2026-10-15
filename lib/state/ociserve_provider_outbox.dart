part of 'ociserve_provider.dart';

/// De versleutelde uitgaanswachtrij: voortgangsrapporten
/// (`playback_report_v1`) en auditgebeurtenissen (`lesson_opened_v1`) die
/// nog niet naar de server konden. Alles hierin gaat mee bij de volgende
/// geslaagde flush; de wachtrij woont in dezelfde keychain-namespace als de
/// refresh-token.
mixin _OciServeOutboxMethods on OciServeNotifierBase {
  Future<void> flushPendingReports() {
    final generation = _generation;
    final running = _flushInFlight;
    if (running != null && _flushGeneration == generation) return running;
    final future = _nonInteractive(_flushPendingReports);
    _flushInFlight = future;
    _flushGeneration = generation;
    return future.whenComplete(() {
      if (identical(_flushInFlight, future)) {
        _flushInFlight = null;
        _flushGeneration = null;
      }
    });
  }

  Future<void> _flushPendingReports() async {
    if (!state.authenticated || !_secrets.canStore) return;
    final generation = _generation;
    final settings = state.settings;
    final baseUrl = settings.normalizedBaseUrl;
    final accountId = state.account!.id;
    final pending = await _readOutbox(baseUrl: baseUrl);
    if (generation != _generation) return;
    state = state.copyWith(pendingReports: pending.length);
    final own = pending
        .where(
          (item) =>
              item['account_id'] == accountId &&
              (item['kind'] == null ||
                  item['kind'] == 'playback_report_v1' ||
                  item['kind'] == 'lesson_opened_v1'),
        )
        .take(5)
        .toList();
    if (own.isEmpty) return;
    final access = await _accessToken();
    if (generation != _generation) return;
    final gateway = _gatewayFactory(settings);
    final currentAccount = await gateway.me(access);
    if (generation != _generation || currentAccount.id != accountId) return;
    state = state.copyWith(account: currentAccount);
    final sent = <Map<String, Object?>>{};
    for (final item in own) {
      final organizationId = item['organization_id'] as String? ?? '';
      if (!currentAccount.activeMemberships.any(
        (membership) => membership.organizationId == organizationId,
      )) {
        continue;
      }
      try {
        if (item['kind'] == 'lesson_opened_v1') {
          await gateway.markLessonOpened(
            accessToken: access,
            organizationId: organizationId,
            versionId: item['version_id'] as String? ?? '',
            lessonId: item['lesson_id'] as String? ?? '',
            idempotencyKey: item['key'] as String? ?? '',
          );
        } else {
          final snapshot = OciServePlaybackSnapshot.fromJson(
            Map<String, Object?>.from(item['snapshot']! as Map),
          );
          await gateway.reportPlayback(
            accessToken: access,
            organizationId: organizationId,
            snapshot: snapshot,
          );
        }
        sent.add(item);
      } catch (error, stack) {
        logError(
          'OciServe: voortgang synchroniseren',
          error.runtimeType,
          stack,
        );
      }
    }
    if (generation != _generation) return;
    final sentEncoded = sent.map(jsonEncode).toSet();
    final remaining = await OciServeOutboxMutex.serialized(baseUrl, () async {
      final latest = await _readOutbox(baseUrl: baseUrl);
      final kept = latest
          .where((item) => !sentEncoded.contains(jsonEncode(item)))
          .toList();
      await _writeOutbox(kept, baseUrl: baseUrl);
      return kept;
    });
    if (generation != _generation) return;
    state = state.copyWith(pendingReports: remaining.length);
  }

  @override
  void _flushInBackground() {
    final generation = _generation;
    unawaited(
      flushPendingReports().catchError((Object error, StackTrace stack) {
        logError(
          'OciServe: voortgang op de achtergrond synchroniseren',
          error.runtimeType,
          stack,
        );
        if (generation == _generation) {
          state = state.copyWith(warningCode: 'sync_failed');
        }
      }),
    );
  }

  @override
  Future<void> _enqueue(
    String organizationId,
    OciServePlaybackSnapshot snapshot,
  ) => _enqueueRaw({
    'kind': 'playback_report_v1',
    'account_id': state.account!.id,
    'organization_id': organizationId,
    'snapshot': snapshot.toJson(),
  });

  /// De versleutelde wachtrij voor nog niet verstuurde gebeurtenissen. Draagt
  /// voortgangsrapporten (`playback_report_v1`) én de auditgebeurtenis
  /// "les geopend" (`lesson_opened_v1`) — beide gaan mee bij de volgende
  /// geslaagde flush.
  @override
  Future<void> _enqueueRaw(Map<String, Object?> item) =>
      OciServeOutboxMutex.serialized(
        state.settings.normalizedBaseUrl,
        () async {
          final pending = await _readOutbox();
          if (pending.length >= 100) {
            state = state.copyWith(warningCode: 'outbox_full');
            throw const OciServeException('outbox_full');
          }
          pending.add(item);
          await _writeOutbox(pending);
          state = state.copyWith(pendingReports: pending.length);
        },
      );

  @override
  Future<List<Map<String, Object?>>> _readOutbox({String? baseUrl}) async {
    final raw = await _secrets.readOciServeOutbox(
      baseUrl ?? state.settings.normalizedBaseUrl,
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.length > 100) {
        throw const OciServeException('outbox_invalid');
      }
      return decoded
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
    } on OciServeException {
      rethrow;
    } catch (error, stack) {
      logError('OciServe: voortgangswachtrij lezen', error.runtimeType, stack);
      throw const OciServeException('outbox_invalid');
    }
  }

  Future<void> _writeOutbox(
    List<Map<String, Object?>> pending, {
    String? baseUrl,
  }) async {
    final base = baseUrl ?? state.settings.normalizedBaseUrl;
    if (pending.isEmpty) {
      await _secrets.deleteOciServeOutbox(base);
    } else {
      await _secrets.writeOciServeOutbox(base, jsonEncode(pending));
    }
  }
}
