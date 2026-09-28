part of 'ociserve_provider.dart';

/// Sessie-activering voor "eLearning volgen": bewaarde aanmelding
/// herstellen of — als er niets te herstellen valt — alleen de
/// bereikbaarheid van de ingestelde server testen.
mixin _OciServeActivationMethods on OciServeNotifierBase {
  /// Wat "eLearning volgen" aan betekent: een bewaarde aanmelding herstellen
  /// als die er is, en anders alleen de bereikbaarheid van de server testen.
  /// Is de dienst uit of onvolledig ingericht, dan blijft de sleutelhanger
  /// met rust en wordt ook geen netwerkverkeer gedaan.
  @override
  Future<void> _activateSession(
    OciServeSettings settings,
    int generation,
  ) async {
    if (!settings.enabled || !settings.isConfigured) {
      _tokens = null;
      _installation = null;
      _configuration = null;
      return;
    }
    final storedRefresh = settings.rememberLogin && _secrets.canStore
        ? await _secrets.readOciServeRefreshToken(settings.normalizedBaseUrl)
        : null;
    if (generation != _generation) return;
    if (storedRefresh == null || storedRefresh.isEmpty) {
      await _probeServerAvailability(settings, generation);
      return;
    }
    // Er ligt een bewaarde aanmelding — ook als de refresh hieronder faalt
    // blijft "account ingesteld" waar, want de sleutel is er wél.
    state = state.copyWith(hasStoredLogin: true);
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
        serverReachable: true,
      );
      _flushInBackground();
    } catch (error, stack) {
      logError('OciServe: sessie herstellen', error.runtimeType, stack);
      if (generation != _generation) return;
      _tokens = null;
      final errorCode = OciServeNotifierBase._safeErrorCode(error);
      state = state.copyWith(
        status: OciServeStatus.signedOut,
        clearAccount: true,
        errorCode: _restoreErrorCode(errorCode),
      );
    }
  }

  /// Test alleen de bereikbaarheid van de ingestelde server: de
  /// installatie-info is anoniem — geen OIDC-discovery, geen login, geen
  /// credentials. Draait als "eLearning volgen" aan staat en er geen
  /// bewaarde aanmelding is om te herstellen: zo kleurt een dode server
  /// eerlijk rood in plaats van eeuwig oranje "ingesteld".
  Future<void> _probeServerAvailability(
    OciServeSettings settings,
    int generation,
  ) async {
    try {
      final connection = await _connect(settings);
      if (generation != _generation) return;
      await _storeResolvedSettings(connection.settings);
      if (generation != _generation) return;
      state = state.copyWith(clearError: true, serverReachable: true);
    } catch (error, stack) {
      logError('OciServe: bereikbaarheid testen', error.runtimeType, stack);
      if (generation != _generation) return;
      state = state.copyWith(
        serverReachable: false,
        errorCode: OciServeNotifierBase._safeErrorCode(error),
      );
    }
  }
}
