part of 'ociserve_provider.dart';

/// Browser sessions use only an HttpOnly cookie. The gateway marker binds a
/// request to one accepted session ID; the Fetch transport never forwards it
/// as Bearer authentication or exposes the BFF's OAuth tokens.
mixin _OciServeWebMethods on OciServeNotifierBase {
  OciServeTokens _browserTokens(OciServeBrowserSession session) =>
      OciServeTokens(
        accessToken: session.marker,
        refreshToken: '',
        expiresAt: session.expiresAt,
      );

  void _checkBrowserSession(
    OciServeBrowserSession session,
    OciServeInstallation installation,
  ) {
    if (!installation.webSession || session.issuer != installation.issuer) {
      throw const OciServeException('issuer_mismatch');
    }
  }

  @override
  Future<void> _activateWebSession(
    OciServeSettings settings,
    int generation,
  ) async {
    try {
      final restored = await _web.restore(settings);
      if (generation != _generation) return;
      if (restored == null) {
        await _probeServerAvailability(settings, generation);
        return;
      }
      final gateway = _gatewayFactory(settings);
      final installation = await gateway.installation();
      if (generation != _generation) return;
      _requireAcceptedIdentityProvider(settings, installation);
      _checkBrowserSession(restored, installation);
      final account = await gateway.me(restored.marker);
      if (generation != _generation) return;
      if (account.activeMemberships.isEmpty) {
        throw const OciServeException('no_active_membership');
      }
      _installation = installation;
      _tokens = _browserTokens(restored);
      state = state.copyWith(
        status: OciServeStatus.authenticated,
        account: account,
        hasStoredLogin: true,
        serverReachable: true,
        clearError: true,
      );
      _flushInBackground();
    } catch (error, stack) {
      logError('OciServe: browsersessie herstellen', error.runtimeType, stack);
      if (generation != _generation) return;
      _tokens = null;
      state = state.copyWith(
        status: OciServeStatus.signedOut,
        clearAccount: true,
        errorCode: OciServeNotifierBase._safeErrorCode(error),
      );
    }
  }

  @override
  Future<bool> _loginWeb({String? loginHint, bool forceLogin = false}) async {
    _web.prepareLogin();
    final generation = ++_generation;
    final settings = state.settings;
    final need = _pendingWebStepUp;
    final expectedAccount = need == null ? null : state.account?.id;
    state = state.copyWith(
      status: OciServeStatus.authenticating,
      clearAccount: true,
      clearError: true,
    );
    try {
      if (!settings.enabled) throw const OciServeException('disabled');
      final gateway = _gatewayFactory(settings);
      final installation = await gateway.installation();
      if (generation != _generation) return false;
      if (!installation.webSession) {
        throw const OciServeException('web_session_unavailable');
      }
      _requireAcceptedIdentityProvider(settings, installation);
      final session = await _web.login(
        settings,
        stepUp: need,
        loginHint: loginHint,
        forceLogin: forceLogin,
      );
      if (generation != _generation) return false;
      _checkBrowserSession(session, installation);
      final account = await gateway.me(session.marker);
      if (generation != _generation) return false;
      if (expectedAccount != null && account.id != expectedAccount) {
        throw const OciServeException('step_up_account_mismatch');
      }
      if (account.activeMemberships.isEmpty) {
        throw const OciServeException('no_active_membership');
      }
      _installation = installation;
      _tokens = _browserTokens(session);
      _pendingWebStepUp = null;
      state = state.copyWith(
        status: OciServeStatus.authenticated,
        account: account,
        hasStoredLogin: true,
        serverReachable: true,
        clearError: true,
      );
      _flushInBackground();
      return true;
    } catch (error, stack) {
      logError('OciServe: webaanmelding', error.runtimeType, stack);
      if (generation != _generation) return false;
      _tokens = null;
      state = state.copyWith(
        status: OciServeStatus.signedOut,
        clearAccount: true,
        errorCode: OciServeNotifierBase._safeErrorCode(error),
      );
      return false;
    } finally {
      if (generation == _generation && !state.authenticated) _web.cancel();
    }
  }

  @override
  Future<String> _webAccessToken() async {
    if (!state.authenticated || _tokens == null) {
      throw const OciServeException('not_authenticated');
    }
    if (!_tokens!.isExpired) return _tokens!.accessToken;
    final generation = _generation;
    final accountId = state.account!.id;
    final restored = await _web.restore(state.settings);
    if (generation != _generation || restored == null) {
      throw const OciServeException('session_expired');
    }
    final installation = _installation;
    if (installation == null) {
      throw const OciServeException('not_authenticated');
    }
    _checkBrowserSession(restored, installation);
    final account = await _gatewayFactory(state.settings).me(restored.marker);
    if (generation != _generation || account.id != accountId) {
      throw const OciServeException('session_expired');
    }
    _tokens = _browserTokens(restored);
    state = state.copyWith(account: account);
    return restored.marker;
  }

  @override
  Future<String> _completeWebStepUp(OciServeStepUpRequired need) async {
    final generation = _generation;
    final accountId = state.account?.id;
    final installation = _installation;
    if (accountId == null || installation == null) {
      throw const OciServeException('not_authenticated');
    }
    _pendingWebStepUp = need;
    final OciServeBrowserSession session;
    try {
      session = await _web.login(state.settings, stepUp: need);
    } catch (error) {
      if (generation == _generation) {
        state = state.copyWith(errorCode: 'web_step_up_required');
      }
      rethrow;
    }
    if (generation != _generation) throw const OciServeException('cancelled');
    _checkBrowserSession(session, installation);
    final account = await _gatewayFactory(state.settings).me(session.marker);
    if (generation != _generation || account.id != accountId) {
      throw const OciServeException('step_up_account_mismatch');
    }
    _tokens = _browserTokens(session);
    _pendingWebStepUp = null;
    _stepUpEpoch++;
    state = state.copyWith(account: account);
    return session.marker;
  }

  @override
  Future<bool> _logoutWeb() async {
    ++_generation;
    final settings = state.settings;
    final marker = _tokens?.accessToken;
    await _finishLearningSessions(
      settings: settings,
      accountId: state.account?.id,
      access: marker,
    );
    var succeeded = true;
    try {
      await _web.logout(settings, sessionMarker: marker);
    } catch (error, stack) {
      logError('OciServe: websessie afmelden', error.runtimeType, stack);
      succeeded = false;
    }
    _web.cancel();
    _tokens = null;
    _installation = null;
    _configuration = null;
    _pendingWebStepUp = null;
    state = state.copyWith(
      status: OciServeStatus.signedOut,
      clearAccount: true,
      hasStoredLogin: !succeeded,
      clearError: succeeded,
      errorCode: succeeded ? null : 'logout_cleanup_failed',
    );
    return succeeded;
  }
}
