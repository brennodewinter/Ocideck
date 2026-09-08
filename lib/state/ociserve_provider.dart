import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/learning_session.dart';
import '../models/ociserve_models.dart';
import '../models/ociserve_settings.dart';
import '../models/playback.dart';
import '../services/ociserve/ociserve_auth.dart';
import '../services/ociserve/ociserve_gateway.dart';
import '../services/ociserve/ociserve_http.dart';
import '../services/secret_store.dart';
import '../utils/log.dart';
import 'secret_store_provider.dart';

const _uuid = Uuid();

typedef OciServeGatewayFactory =
    OciServeApi Function(OciServeSettings settings);
typedef OciServeAuthenticatorFactory =
    OciServeAuthenticator Function(OciServeSettings settings);

final ociServeGatewayFactoryProvider = Provider<OciServeGatewayFactory>(
  (ref) =>
      (settings) => OciServeGateway(settings: settings),
);

final ociServeAuthenticatorFactoryProvider =
    Provider<OciServeAuthenticatorFactory>(
      (ref) =>
          (settings) => OciServePkceAuthenticator(settings: settings),
    );

final ociServeProvider = NotifierProvider<OciServeNotifier, OciServeState>(
  OciServeNotifier.new,
);

final ociServeEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(ociServeProvider.select((state) => state.settings.enabled)),
);

/// De eLearning-koppeling is op elk platform zichtbaar. Op web legt de kaart
/// uit waarom aanmelden zonder veilige sleutelbos niet beschikbaar is.
final ociServeAvailableProvider = Provider<bool>((ref) => true);

/// True only after a restored or fresh token has successfully called `/me`.
final ociServeAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(ociServeProvider.select((state) => state.authenticated)),
);

enum OciServeStatus { loading, signedOut, authenticating, authenticated }

class OciServeState {
  const OciServeState({
    this.settings = const OciServeSettings(),
    this.status = OciServeStatus.loading,
    this.account,
    this.errorCode,
    this.warningCode,
    this.identityProviderHost,
    this.pendingReports = 0,
  });

  final OciServeSettings settings;
  final OciServeStatus status;
  final OciServeAccount? account;
  final String? errorCode;
  final String? warningCode;
  final String? identityProviderHost;
  final int pendingReports;

  bool get authenticated =>
      settings.enabled &&
      status == OciServeStatus.authenticated &&
      account != null;

  bool get loading => status == OciServeStatus.loading;
  bool get authenticating => status == OciServeStatus.authenticating;
  List<OciServeMembership> get memberships =>
      account?.activeMemberships ?? const [];
  String? get error => errorCode;
  int get pendingSync => pendingReports;

  OciServeState copyWith({
    OciServeSettings? settings,
    OciServeStatus? status,
    OciServeAccount? account,
    bool clearAccount = false,
    String? errorCode,
    bool clearError = false,
    String? warningCode,
    bool clearWarning = false,
    String? identityProviderHost,
    bool clearIdentityProviderHost = false,
    int? pendingReports,
  }) => OciServeState(
    settings: settings ?? this.settings,
    status: status ?? this.status,
    account: clearAccount ? null : account ?? this.account,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
    warningCode: clearWarning ? null : warningCode ?? this.warningCode,
    identityProviderHost: clearIdentityProviderHost
        ? null
        : identityProviderHost ?? this.identityProviderHost,
    pendingReports: pendingReports ?? this.pendingReports,
  );
}

/// Owns OciServe connection/session state. Tokens stay private to the notifier;
/// consumers receive only the minimal account/membership read model.
class OciServeNotifier extends Notifier<OciServeState> {
  SecretStore get _secrets => ref.read(secretStoreProvider);
  OciServeGatewayFactory get _gatewayFactory =>
      ref.read(ociServeGatewayFactoryProvider);
  OciServeAuthenticatorFactory get _authFactory =>
      ref.read(ociServeAuthenticatorFactoryProvider);

  OciServeTokens? _tokens;
  OciServeInstallation? _installation;
  OciServeOidcConfiguration? _configuration;
  int _generation = 0;
  Future<void>? _flushInFlight;
  int? _flushGeneration;
  Future<OciServeTokens>? _refreshInFlight;
  Future<void>? _secretWriteInFlight;

  @override
  OciServeState build() {
    ref.onDispose(() => ++_generation);
    _initialize(++_generation);
    return const OciServeState();
  }

  Future<void> _initialize(int generation) async {
    OciServeSettings settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kOciServeSettingsKey);
      settings = raw == null
          ? const OciServeSettings()
          : OciServeSettings.fromJson(
              Map<String, Object?>.from(jsonDecode(raw) as Map),
            );
    } catch (error, stack) {
      logError('OciServe: instellingen lezen', error.runtimeType, stack);
      settings = const OciServeSettings();
    }
    if (generation != _generation) return;
    state = OciServeState(settings: settings, status: OciServeStatus.signedOut);
    if (!settings.enabled ||
        !settings.isConfigured ||
        !settings.rememberLogin ||
        !_secrets.canStore) {
      return;
    }
    final storedRefresh = await _secrets.readOciServeRefreshToken(
      settings.normalizedBaseUrl,
    );
    if (storedRefresh == null ||
        storedRefresh.isEmpty ||
        generation != _generation) {
      return;
    }
    try {
      state = state.copyWith(status: OciServeStatus.authenticating);
      final connection = await _connect(settings);
      settings = connection.settings;
      final gateway = connection.gateway;
      final installation = connection.installation;
      if (generation != _generation) return;
      await _storeResolvedSettings(settings);
      _requireAcceptedIdentityProvider(settings, installation);
      final configuration = await gateway.discoverOidc(installation);
      if (generation != _generation) return;
      final refresh = _boundRefreshToken(
        storedRefresh,
        installation,
        configuration,
      );
      final tokens = await _authFactory(
        settings,
      ).refresh(installation, configuration, refresh);
      final account = await gateway.me(tokens.accessToken);
      if (account.activeMemberships.isEmpty) {
        throw const OciServeException('no_active_membership');
      }
      if (generation != _generation) return;
      _installation = installation;
      _configuration = configuration;
      _tokens = tokens;
      await _persistRefreshToken(settings, tokens);
      if (generation != _generation) return;
      state = state.copyWith(
        status: OciServeStatus.authenticated,
        account: account,
        clearError: true,
      );
      _flushInBackground();
    } catch (error, stack) {
      logError('OciServe: sessie herstellen', error.runtimeType, stack);
      if (generation != _generation) return;
      _tokens = null;
      state = state.copyWith(
        status: OciServeStatus.signedOut,
        clearAccount: true,
        errorCode:
            _safeErrorCode(error) == 'identity_provider_confirmation_required'
            ? 'identity_provider_confirmation_required'
            : 'restore_failed',
      );
    }
  }

  Future<void> saveSettings(
    OciServeSettings settings, {
    bool discardPendingReports = false,
  }) async {
    ++_generation;
    final old = state.settings;
    final serverChanged = old.normalizedBaseUrl != settings.normalizedBaseUrl;
    if (serverChanged) {
      final pending = old.normalizedBaseUrl.isEmpty
          ? const <Map<String, Object?>>[]
          : await _readOutbox(baseUrl: old.normalizedBaseUrl);
      if (pending.isNotEmpty && !discardPendingReports) {
        state = state.copyWith(warningCode: 'pending_reports_not_discarded');
        throw const OciServeException('pending_reports_not_discarded');
      }
      await _secretWriteInFlight;
      await _clearLocalSession(old, clearOutbox: discardPendingReports);
      _tokens = null;
      _installation = null;
      _configuration = null;
      _refreshInFlight = null;
      settings = settings.copyWith(acceptedIdentityProviderHost: '');
    }
    state = state.copyWith(
      settings: settings,
      status: settings.enabled && state.authenticated && !serverChanged
          ? OciServeStatus.authenticated
          : OciServeStatus.signedOut,
      clearAccount: !settings.enabled || serverChanged,
      clearError: true,
      clearWarning: true,
      clearIdentityProviderHost: true,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kOciServeSettingsKey, jsonEncode(settings.toJson()));
    if (!settings.rememberLogin) {
      await _secretWriteInFlight;
      await _secrets.deleteOciServeRefreshToken(settings.normalizedBaseUrl);
    }
    if (!settings.enabled) await logout();
  }

  Future<void> setEnabled(bool enabled) =>
      saveSettings(state.settings.copyWith(enabled: enabled));

  Future<bool> login() async {
    final generation = ++_generation;
    final settings = state.settings;
    if (!settings.enabled || !_secrets.canStore) {
      state = state.copyWith(errorCode: 'not_available');
      return false;
    }
    final invalid = validateOciServeBaseUrl(settings.baseUrl);
    if (invalid != null) {
      state = state.copyWith(errorCode: invalid);
      return false;
    }
    state = state.copyWith(
      status: OciServeStatus.authenticating,
      clearAccount: true,
      clearError: true,
    );
    try {
      final connection = await _connect(settings);
      final resolvedSettings = connection.settings;
      final gateway = connection.gateway;
      final installation = connection.installation;
      if (generation != _generation) return false;
      await _storeResolvedSettings(resolvedSettings);
      _requireAcceptedIdentityProvider(resolvedSettings, installation);
      final configuration = await gateway.discoverOidc(installation);
      if (generation != _generation) return false;
      final tokens = await _authFactory(
        resolvedSettings,
      ).login(installation, configuration);
      final account = await gateway.me(tokens.accessToken);
      if (account.activeMemberships.isEmpty) {
        throw const OciServeException('no_active_membership');
      }
      if (generation != _generation) return false;
      _installation = installation;
      _configuration = configuration;
      _tokens = tokens;
      if (resolvedSettings.rememberLogin) {
        await _persistRefreshToken(resolvedSettings, tokens);
        if (generation != _generation) return false;
      }
      state = state.copyWith(
        status: OciServeStatus.authenticated,
        account: account,
      );
      _flushInBackground();
      return true;
    } catch (error, stack) {
      logError('OciServe: aanmelden afronden', error, stack);
      if (generation != _generation) return false;
      _tokens = null;
      state = state.copyWith(
        status: OciServeStatus.signedOut,
        clearAccount: true,
        errorCode: _safeErrorCode(error),
      );
      return false;
    }
  }

  Future<
    ({
      OciServeSettings settings,
      OciServeApi gateway,
      OciServeInstallation installation,
    })
  >
  _connect(OciServeSettings settings) async {
    Object? firstError;
    StackTrace? firstStack;
    for (final candidate in ociServeConnectionCandidates(settings)) {
      try {
        final gateway = _gatewayFactory(candidate);
        final installation = await gateway.installation().timeout(
          const Duration(seconds: 3),
        );
        return (
          settings: candidate,
          gateway: gateway,
          installation: installation,
        );
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    Error.throwWithStackTrace(firstError!, firstStack!);
  }

  Future<void> _storeResolvedSettings(OciServeSettings settings) async {
    if (state.settings.normalizedBaseUrl == settings.normalizedBaseUrl) return;
    state = state.copyWith(settings: settings);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kOciServeSettingsKey, jsonEncode(settings.toJson()));
  }

  Future<bool> logout() async {
    ++_generation;
    final settings = state.settings;
    _tokens = null;
    _installation = null;
    _configuration = null;
    _refreshInFlight = null;
    state = state.copyWith(
      status: OciServeStatus.signedOut,
      clearAccount: true,
      clearError: true,
    );
    try {
      await _secretWriteInFlight;
      await _clearLocalSession(settings, clearOutbox: false);
      final pending = await _readOutbox();
      state = state.copyWith(
        pendingReports: pending.length,
        warningCode: pending.isEmpty ? null : 'pending_reports_preserved',
        clearWarning: pending.isEmpty,
      );
      return true;
    } catch (error, stack) {
      logError('OciServe: lokale sessie wissen', error.runtimeType, stack);
      state = state.copyWith(errorCode: 'logout_cleanup_failed');
      return false;
    }
  }

  /// Wist na de algemene resetbevestiging ook OciServe-instellingen en de
  /// versleutelde voortgangswachtrij. Zo blijft deze notifier de enige eigenaar
  /// van OciServe-opslag.
  Future<bool> resetLocalData() async {
    ++_generation;
    var settings = state.settings;
    _tokens = null;
    _installation = null;
    _configuration = null;
    _refreshInFlight = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (settings.normalizedBaseUrl.isEmpty) {
        final raw = prefs.getString(kOciServeSettingsKey);
        if (raw != null) {
          settings = OciServeSettings.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          );
        }
      }
      await _secretWriteInFlight;
      await _clearLocalSession(settings, clearOutbox: true);
      await prefs.remove(kOciServeSettingsKey);
      state = const OciServeState(status: OciServeStatus.signedOut);
      return true;
    } catch (error, stack) {
      logError('OciServe: lokale gegevens wissen', error.runtimeType, stack);
      state = state.copyWith(errorCode: 'reset_cleanup_failed');
      return false;
    }
  }

  Future<void> acceptIdentityProvider(String host) async {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty || normalized != state.identityProviderHost) {
      throw const OciServeException('identity_provider_mismatch');
    }
    await saveSettings(
      state.settings.copyWith(acceptedIdentityProviderHost: normalized),
    );
  }

  Future<List<OciServeFeedItem>> learningFeed(String organizationId) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(
      state.settings,
    ).learningFeed(accessToken: access, organizationId: organizationId);
  }

  Future<OciServeLearningState> learningState(String organizationId) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(
      state.settings,
    ).learningState(accessToken: access, organizationId: organizationId);
  }

  Future<OciServePackage> lessonPackage({
    required String organizationId,
    required OciServeFeedItem lesson,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).lessonPackage(
      accessToken: access,
      organizationId: organizationId,
      versionId: lesson.versionId,
      lessonId: lesson.lessonId,
    );
  }

  Future<void> reportPlayback({
    required LearningSessionRef session,
    required PlaybackReport report,
    required DateTime startedAt,
  }) async {
    if (session.serverUrl != state.settings.normalizedBaseUrl ||
        session.accountId != state.account?.id) {
      throw const OciServeException('playback_session_refused');
    }
    _requireMembership(session.organizationId);
    final endedAt = DateTime.now().toUtc();
    final earliestAcceptedStart = endedAt.subtract(const Duration(hours: 24));
    final acceptedStart = startedAt.toUtc().isBefore(earliestAcceptedStart)
        ? earliestAcceptedStart
        : startedAt.toUtc();
    final snapshot = OciServePlaybackSnapshot(
      sessionId: _uuid.v4(),
      courseVersionId: session.courseVersionId,
      lessonId: session.lessonId,
      startedAt: acceptedStart,
      endedAt: endedAt,
      lastSlideAnchor: report.lastSlideId ?? '',
      completed: report.completed,
      slideTimeMs: {
        for (final timing in report.run.perSlide)
          timing.slideId: timing.spent.inMilliseconds.clamp(
            0,
            const Duration(hours: 12).inMilliseconds,
          ),
      },
    );
    await _enqueue(session.organizationId, snapshot);
  }

  Future<void> flushPendingReports() {
    final generation = _generation;
    final running = _flushInFlight;
    if (running != null && _flushGeneration == generation) return running;
    final future = _flushPendingReports();
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
        .where((item) => item['account_id'] == accountId)
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
        final snapshot = OciServePlaybackSnapshot.fromJson(
          Map<String, Object?>.from(item['snapshot']! as Map),
        );
        await gateway.reportPlayback(
          accessToken: access,
          organizationId: organizationId,
          snapshot: snapshot,
        );
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
    final remaining = pending.where((item) => !sent.contains(item)).toList();
    await _writeOutbox(remaining, baseUrl: baseUrl);
    if (generation != _generation) return;
    state = state.copyWith(pendingReports: remaining.length);
  }

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

  Future<String> _accessToken() async {
    final current = _tokens;
    if (!state.authenticated || current == null) {
      throw const OciServeException('not_authenticated');
    }
    if (!current.isExpired) return current.accessToken;
    final installation = _installation;
    final configuration = _configuration;
    if (installation == null || configuration == null) {
      throw const OciServeException('not_authenticated');
    }
    final generation = _generation;
    final settings = state.settings;
    var refresh = _refreshInFlight;
    if (refresh == null) {
      refresh = _authFactory(
        settings,
      ).refresh(installation, configuration, current.refreshToken);
      _refreshInFlight = refresh;
    }
    try {
      final tokens = await refresh;
      if (generation != _generation) {
        throw const OciServeException('not_authenticated');
      }
      _tokens = tokens;
      if (settings.rememberLogin) {
        await _persistRefreshToken(settings, tokens);
        if (generation != _generation) {
          throw const OciServeException('not_authenticated');
        }
      }
      return tokens.accessToken;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  void _requireMembership(String organizationId) {
    if (!state.memberships.any(
      (membership) => membership.organizationId == organizationId,
    )) {
      throw const OciServeException('organization_refused');
    }
  }

  Future<void> _persistRefreshToken(
    OciServeSettings settings,
    OciServeTokens tokens,
  ) {
    final installation = _installation;
    final configuration = _configuration;
    if (installation == null || configuration == null) {
      throw const OciServeException('not_authenticated');
    }
    final write = _secrets.writeOciServeRefreshToken(
      settings.normalizedBaseUrl,
      jsonEncode({
        'version': 1,
        'refresh_token': tokens.refreshToken,
        'issuer': configuration.issuer.toString(),
        'client_id': installation.clientId,
        'token_endpoint': configuration.tokenEndpoint.toString(),
      }),
    );
    _secretWriteInFlight = write;
    return write.whenComplete(() {
      if (identical(_secretWriteInFlight, write)) {
        _secretWriteInFlight = null;
      }
    });
  }

  Future<void> _clearLocalSession(
    OciServeSettings settings, {
    required bool clearOutbox,
  }) async {
    if (settings.normalizedBaseUrl.isEmpty) return;
    await _secrets.deleteOciServeRefreshToken(settings.normalizedBaseUrl);
    if (clearOutbox) {
      await _secrets.deleteOciServeOutbox(settings.normalizedBaseUrl);
    }
  }

  Future<void> _enqueue(
    String organizationId,
    OciServePlaybackSnapshot snapshot,
  ) async {
    final pending = await _readOutbox();
    if (pending.length >= 100) {
      state = state.copyWith(warningCode: 'outbox_full');
      throw const OciServeException('outbox_full');
    }
    pending.add({
      'account_id': state.account!.id,
      'organization_id': organizationId,
      'snapshot': snapshot.toJson(),
    });
    await _writeOutbox(pending);
    state = state.copyWith(pendingReports: pending.length);
  }

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

  static String _safeErrorCode(Object error) => switch (error) {
    OciServeException(:final code) => code,
    SecretStoreUnsupported() => 'keychain_unavailable',
    _ => 'connection_failed',
  };

  void _requireAcceptedIdentityProvider(
    OciServeSettings settings,
    OciServeInstallation installation,
  ) {
    final serverHost = Uri.parse(settings.normalizedBaseUrl).host.toLowerCase();
    final issuerHost = installation.issuer.host.toLowerCase();
    if (issuerHost == serverHost ||
        settings.acceptedIdentityProviderHost == issuerHost) {
      return;
    }
    state = state.copyWith(identityProviderHost: issuerHost);
    throw const OciServeException('identity_provider_confirmation_required');
  }

  String _boundRefreshToken(
    String stored,
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
  ) {
    try {
      final value = Map<String, Object?>.from(jsonDecode(stored) as Map);
      if (value['version'] != 1 ||
          value['issuer'] != configuration.issuer.toString() ||
          value['client_id'] != installation.clientId ||
          value['token_endpoint'] != configuration.tokenEndpoint.toString()) {
        throw const FormatException();
      }
      final token = (value['refresh_token'] as String? ?? '').trim();
      if (token.isEmpty) throw const FormatException();
      return token;
    } catch (error, stack) {
      logError(
        'OciServe: bewaarde sessiebinding lezen',
        error.runtimeType,
        stack,
      );
      throw const OciServeException('stored_session_mismatch');
    }
  }
}
