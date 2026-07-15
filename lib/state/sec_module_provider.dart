// State for the "Informatieveiligheid" module (PENTEST_MIAUW.md §6).
//
// A lightweight module framework: a single toggle, OFF by default, whose
// enabled flag + provisioned pack version live in the one shared_preferences
// domain (like every other setting). Enabling runs provisioning
// (SecModuleProvisioner) and, on success, flips a REVEAL flag that the module's
// features (the Informatieveiligheid picker tab, MIAUW templates and the
// finding/checklist/scope-matrix slide types) read via [secModuleRevealProvider].
// Disabling clears the reveal but KEEPS the cached pack.
//
// This is deliberately reusable: a future domain extension can reuse the same
// enable → provision → reveal pattern.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/secmodule/sec_module_provisioner.dart';
import '../services/secmodule/sec_pack_config.dart';
import '../services/secmodule/sec_pack_platform.dart';
import '../utils/log.dart';
import 'consent_provider.dart';

const _enabledKey = 'secModuleEnabled';
const _versionKey = 'secModulePackVersion';

/// Loads the app-bundled baseline pack (a pubspec asset) as bytes, or null when
/// it is missing/unreadable — the provisioner then falls through to a mirror.
Future<Uint8List?> _loadBundledSecPack() async {
  try {
    final data = await rootBundle.load(secPackAssetKey);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (e) {
    logWarning('secModule: kon meegeleverd pakket niet laden', e);
    return null;
  }
}

/// The provisioner used by the notifier. Overridden in tests with a fake
/// transport + in-memory store so nothing hits the network or disk.
final secModuleProvisionerProvider = Provider<SecModuleProvisioner>((ref) {
  return SecModuleProvisioner(
    transport: createSecPackTransport(),
    store: createSecPackStore(),
    bundledPackLoader: _loadBundledSecPack,
  );
});

final secModuleProvider = NotifierProvider<SecModuleNotifier, SecModuleState>(
  SecModuleNotifier.new,
);

/// The gating provider later features watch. True only when the module is on
/// AND a matching pack has been provisioned — so nothing lights up until the
/// data is actually present locally.
final secModuleRevealProvider = Provider<bool>((ref) {
  final state = ref.watch(secModuleProvider);
  return state.revealed;
});

class SecModuleState {
  final bool enabled;

  /// The pack version currently provisioned locally, or null when none is.
  final String? provisionedVersion;

  /// A provisioning run is in progress.
  final bool busy;

  /// Result of the last provisioning attempt (for the settings UI to explain
  /// why nothing was revealed, e.g. no consent / web unsupported).
  final SecProvisionStatus? lastStatus;

  /// Prefs still loading on first build.
  final bool loading;

  const SecModuleState({
    this.enabled = false,
    this.provisionedVersion,
    this.busy = false,
    this.lastStatus,
    this.loading = true,
  });

  /// Reveal = the module is on and the expected pack is provisioned.
  bool get revealed => enabled && provisionedVersion == secPackVersion;

  SecModuleState copyWith({
    bool? enabled,
    String? provisionedVersion,
    bool clearProvisionedVersion = false,
    bool? busy,
    SecProvisionStatus? lastStatus,
    bool? loading,
  }) {
    return SecModuleState(
      enabled: enabled ?? this.enabled,
      provisionedVersion: clearProvisionedVersion
          ? null
          : (provisionedVersion ?? this.provisionedVersion),
      busy: busy ?? this.busy,
      lastStatus: lastStatus ?? this.lastStatus,
      loading: loading ?? this.loading,
    );
  }
}

class SecModuleNotifier extends Notifier<SecModuleState> {
  @override
  SecModuleState build() {
    _initialize();
    return const SecModuleState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_enabledKey) ?? false;
      final version = prefs.getString(_versionKey);
      // Reconcile the persisted version with the cache: a version recorded in
      // prefs is only trusted when the pack is actually present + verified.
      final provisioner = ref.read(secModuleProvisionerProvider);
      final provisioned = await provisioner.isProvisioned();
      state = state.copyWith(
        enabled: enabled,
        provisionedVersion: provisioned ? secPackVersion : null,
        clearProvisionedVersion: !provisioned,
        loading: false,
      );
      if (enabled && !provisioned) {
        // The web cache store persists nothing, so a page reload drops the
        // provisioned marker while the toggle stays on — the module would
        // silently lose its slide types and commands. Re-provision from the
        // bundled pack (offline, no consent) so it re-reveals. On desktop this
        // only runs if the on-disk cache was lost.
        await _provision();
      } else if (!provisioned && version != null) {
        // Drop a stale prefs entry so state and prefs stay in step.
        await prefs.remove(_versionKey);
      }
    } catch (e) {
      debugPrint('SecModuleNotifier: kon moduletoestand niet laden: $e');
      state = state.copyWith(loading: false);
    }
  }

  /// Turn the module on: persist the flag, then provision (fetch + verify +
  /// cache) so the reveal flag can flip. Every fetch is gated by the outbound
  /// consent; without it, provisioning reports [SecProvisionStatus.noConsent]
  /// and nothing is revealed.
  Future<SecProvisionStatus> enable() async {
    state = state.copyWith(enabled: true, busy: true);
    await _persistBool(_enabledKey, true);
    return _provision();
  }

  /// Re-run provisioning for an already-enabled module — the "try again" action
  /// after a fetch failed (no mirror reachable) or after the user has just
  /// granted the outbound consent. Same pipeline as [enable] minus flipping the
  /// toggle, so it is a no-op safe to call whenever the module is on.
  Future<SecProvisionStatus> retry() async {
    if (!state.enabled) return SecProvisionStatus.noConsent;
    state = state.copyWith(busy: true);
    return _provision();
  }

  /// Bijwerken: haal de referentiegegevens opnieuw op, óók als er al een
  /// geverifieerd pakket ligt. Zonder de force-vlag zou dit meteen op
  /// `alreadyCached` stuiten en dus niets doen — een knop die doet alsof.
  Future<SecProvisionStatus> refresh() async {
    if (!state.enabled) return SecProvisionStatus.noConsent;
    state = state.copyWith(busy: true);
    return _provision(force: true);
  }

  /// The shared fetch → verify → cache run behind [enable] and [retry].
  Future<SecProvisionStatus> _provision({bool force = false}) async {
    final hasConsent = ref.read(consentProvider).hasAccepted;
    final provisioner = ref.read(secModuleProvisionerProvider);
    final result = await provisioner.provision(
      hasConsent: hasConsent,
      force: force,
    );
    await _applyResult(result);
    return result.status;
  }

  /// Manual local-file import fallback (fallback #3 / air-gapped). Verifies the
  /// bytes against the pinned hash + inner manifest, then caches. No consent
  /// needed: nothing leaves the device.
  Future<SecProvisionStatus> provisionFromBytes(List<int> bytes) async {
    state = state.copyWith(busy: true);
    final provisioner = ref.read(secModuleProvisionerProvider);
    final result = await provisioner.provisionFromBytes(bytes);
    await _applyResult(result);
    return result.status;
  }

  Future<void> _applyResult(SecProvisionResult result) async {
    if (result.isProvisioned) {
      state = state.copyWith(
        provisionedVersion: result.version,
        busy: false,
        lastStatus: result.status,
      );
      await _persistString(_versionKey, result.version ?? secPackVersion);
    } else {
      state = state.copyWith(busy: false, lastStatus: result.status);
    }
  }

  /// Turn the module off: clear the reveal (via the enabled flag) but KEEP the
  /// cached pack, so re-enabling is instant and offline. A separate "clean up"
  /// ([cleanUpCache]) removes the cache when the user really wants the space.
  Future<void> disable() async {
    state = state.copyWith(enabled: false);
    await _persistBool(_enabledKey, false);
  }

  /// Remove the cached pack from disk and forget the provisioned version.
  Future<void> cleanUpCache() async {
    final provisioner = ref.read(secModuleProvisionerProvider);
    await provisioner.cleanUp();
    state = state.copyWith(clearProvisionedVersion: true);
    await _removeKey(_versionKey);
  }

  Future<void> _persistBool(String key, bool value) =>
      _persist((prefs) => prefs.setBool(key, value));

  Future<void> _persistString(String key, String value) =>
      _persist((prefs) => prefs.setString(key, value));

  Future<void> _removeKey(String key) => _persist((prefs) => prefs.remove(key));

  Future<void> _persist(Future<void> Function(SharedPreferences) write) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await write(prefs);
    } catch (e, s) {
      // State already updated for this session; only persistence is lost.
      logError('SecModuleNotifier: prefs-schrijf mislukt', e, s);
    }
  }
}
