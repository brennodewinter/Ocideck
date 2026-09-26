import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/storage_connection.dart';
import '../platform/platform_features.dart';
import '../services/secret_store.dart';
import '../services/storage_probe.dart';
import 'secret_store_provider.dart';
import 'settings_provider.dart';

/// Bereikbaarheid van één opslagverbinding zoals de lampjes hem tonen.
enum StorageReach { checking, reachable, unreachable }

/// De probe-naad voor tests: productie roept [probeStorageConnection], tests
/// leveren een programmeerbare uitkomst zonder het netwerk te raken.
final storageProbeProvider =
    Provider<Future<bool> Function(StorageConnection, SecretStore)>(
      (ref) => probeStorageConnection,
    );

/// Per geconfigureerde verbinding de bereikbaarheid, gekeyd op
/// [StorageConnection.id]. Verbindingen die niet compleet ingesteld zijn en
/// remote verbindingen op web (waar `dart:io` niet bestaat) komen niet in de
/// map — hun lampje hoort er dan ook niet te zijn.
final storageStatusProvider =
    NotifierProvider.autoDispose<
      StorageStatusNotifier,
      Map<String, StorageReach>
    >(StorageStatusNotifier.new);

class StorageStatusNotifier extends Notifier<Map<String, StorageReach>> {
  /// Configuratie-vingerafdruk per verbinding, zodat een naamswijziging niet
  /// opnieuw pingt maar een andere server wél.
  final Map<String, String> _configSeen = {};

  /// Laat-terugkomende probes: alleen de nieuwste poging per verbinding mag
  /// haar uitslag schrijven — een hertik of herbouw onderweg laat de oudere
  /// stilletjes vervallen in plaats van een achterhaalde kleur te zetten.
  final Map<String, int> _probeTicket = {};

  /// De laatste uitkomst per verbinding — bij een herbouw (bijvoorbeeld een
  /// nieuwe verbinding erbij) blijft die staan in plaats van terug te
  /// flitsen naar "loopt" voor iets dat allang bekend was.
  final Map<String, StorageReach> _last = {};

  @override
  Map<String, StorageReach> build() {
    final connections = ref.watch(
      settingsProvider.select((s) => s.connections),
    );
    final result = <String, StorageReach>{};
    final previous = Map<String, String>.of(_configSeen);
    _configSeen.clear();
    for (final c in connections) {
      if (!c.isConfigured) continue;
      _configSeen[c.id] = jsonEncode(c.toJson());
      if (c is LocalConnection) {
        result[c.id] = StorageReach.reachable;
        continue;
      }
      // Op web bestaat de `dart:io`-transport niet; de lampjes doen alsof de
      // verbinding er niet is, net als de versiecheck op web.
      if (isWebPlatform) continue;
      // Alleen opnieuw pingen als de configuratie veranderde; de vorige
      // uitslag blijft anders gewoon staan.
      final unchanged = previous[c.id] == _configSeen[c.id];
      result[c.id] = unchanged
          ? (_last[c.id] ?? StorageReach.checking)
          : StorageReach.checking;
      if (!unchanged || result[c.id] == StorageReach.checking) {
        unawaited(_probe(c));
      }
    }
    _last
      ..clear()
      ..addAll(result);
    return result;
  }

  Future<void> _probe(StorageConnection c) async {
    final ticket = (_probeTicket[c.id] ?? 0) + 1;
    _probeTicket[c.id] = ticket;
    final ok = await ref.read(storageProbeProvider)(
      c,
      ref.read(secretStoreProvider),
    );
    // De notifier kan onderweg zijn afgebroken (autoDispose: het scherm met
    // de lampjes is weg). `state` aanraken gooit dan — de uitslag hoeft dan
    // ook nergens meer heen.
    if (!ref.mounted) return;
    // Alleen de nieuwste probe voor deze verbinding schrijft, en alleen als
    // de verbinding nog in de uitslag voorkomt.
    if (_probeTicket[c.id] != ticket || !state.containsKey(c.id)) return;
    final reach = ok ? StorageReach.reachable : StorageReach.unreachable;
    _last[c.id] = reach;
    state = {...state, c.id: reach};
  }

  /// Handmatige hertest vanuit een lampje — gebruiker-geïnitieerd, dus altijd.
  Future<void> recheck(String connectionId) async {
    final connection = ref
        .read(settingsProvider)
        .connections
        .where((c) => c.id == connectionId)
        .firstOrNull;
    if (connection == null || connection is LocalConnection) return;
    state = {...state, connectionId: StorageReach.checking};
    await _probe(connection);
  }
}
