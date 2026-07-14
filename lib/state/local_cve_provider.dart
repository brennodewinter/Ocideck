import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cve_hit.dart';
import '../models/local_cve_status.dart';
import '../services/cve/local_cve_database.dart';
import '../utils/log.dart';

/// De toestand van de lokale CVE-database.
class LocalCveState {
  /// False op het web; dan hoort de hele sectie niet getoond te worden.
  final bool supported;

  /// De eerste keer nog aan het kijken wat er ligt.
  final bool loading;

  /// Wat er ligt, of null wanneer er niets ligt.
  final LocalCveStats? stats;

  /// Loopt er een opbouw, en hoe ver is hij.
  final CveIngestProgress? progress;

  /// Waarom de vorige opbouw niet lukte.
  final CveIngestFailure? failure;

  const LocalCveState({
    this.supported = localCveSupported,
    this.loading = true,
    this.stats,
    this.progress,
    this.failure,
  });

  bool get busy => progress != null;

  /// Er ligt een bruikbare index: zoeken kan offline, en hoeft dus niets te
  /// lekken.
  bool get available => (stats?.records ?? 0) > 0;

  LocalCveState copyWith({
    bool? loading,
    LocalCveStats? stats,
    CveIngestProgress? progress,
    CveIngestFailure? failure,
    bool clearStats = false,
    bool clearProgress = false,
    bool clearFailure = false,
  }) => LocalCveState(
    supported: supported,
    loading: loading ?? this.loading,
    stats: clearStats ? null : (stats ?? this.stats),
    progress: clearProgress ? null : (progress ?? this.progress),
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

class LocalCveNotifier extends Notifier<LocalCveState> {
  LocalCveDatabase? _db;

  /// Wordt op true gezet door [cancel]; de ingest polst hem tussen de stappen
  /// en tijdens de download.
  bool _cancelled = false;

  @override
  LocalCveState build() {
    _refresh();
    return const LocalCveState();
  }

  Future<LocalCveDatabase> _database() async =>
      _db ??= await createLocalCveDatabase();

  Future<void> _refresh() async {
    if (!localCveSupported) {
      state = state.copyWith(loading: false);
      return;
    }
    try {
      final stats = await (await _database()).stats();
      state = state.copyWith(
        loading: false,
        stats: stats,
        clearStats: stats == null,
      );
    } catch (e) {
      logError('LocalCveNotifier: kon de lokale CVE-index niet lezen', e);
      state = state.copyWith(loading: false);
    }
  }

  /// Haalt de nieuwste bulkrelease op en bouwt de index opnieuw. Duurt lang en
  /// is groot — de UI waarschuwt daarvoor vóórdat dit begint.
  Future<void> download() async {
    if (state.busy) return;
    _cancelled = false;
    state = state.copyWith(
      progress: const CveIngestProgress(phase: CveIngestPhase.discovering),
      clearFailure: true,
    );

    try {
      final stats = await (await _database()).build(
        onProgress: (p) {
          // Een afgebroken opbouw mag de balk niet weer aanzetten.
          if (_cancelled) return;
          state = state.copyWith(progress: p);
        },
        isCancelled: () => _cancelled,
      );
      state = state.copyWith(stats: stats, clearProgress: true);
    } on CveIngestException catch (e) {
      state = state.copyWith(failure: e.failure, clearProgress: true);
    } catch (e) {
      logError('LocalCveNotifier: opbouw van de lokale CVE-index mislukte', e);
      state = state.copyWith(
        failure: CveIngestFailure.networkFailed,
        clearProgress: true,
      );
    }
  }

  /// Zoekt in de lokale index. Er gaat niets het apparaat uit — dat is de hele
  /// reden dat deze database bestaat.
  Future<List<CveHit>> search(String query) async {
    if (!state.available) return const [];
    try {
      final records = await (await _database()).search(query);
      return [for (final r in records) r.toHit()];
    } catch (e) {
      logError('LocalCveNotifier: lokaal zoeken mislukte', e);
      return const [];
    }
  }

  /// Breekt een lopende opbouw af. De half geschreven index wordt weggegooid;
  /// een bestaande, werkende index blijft staan.
  void cancel() => _cancelled = true;

  Future<void> delete() async {
    if (state.busy) return;
    try {
      await (await _database()).delete();
    } catch (e) {
      logError('LocalCveNotifier: kon de lokale CVE-index niet verwijderen', e);
    }
    state = state.copyWith(clearStats: true, clearFailure: true);
  }
}

final localCveProvider = NotifierProvider<LocalCveNotifier, LocalCveState>(
  LocalCveNotifier.new,
);

/// Of de lokale database bruikbaar is. De CVE-picker gebruikt dit om offline te
/// zoeken — en dan hóéft de online-poort niet eens open.
final localCveAvailableProvider = Provider<bool>(
  (ref) => !kIsWeb && ref.watch(localCveProvider).available,
);
