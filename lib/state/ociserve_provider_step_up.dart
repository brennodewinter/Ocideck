part of 'ociserve_provider.dart';

/// Sleutel van de zone waarin een stap-omhoog-aanmelding niet mag starten.
const Symbol _ociServeNonInteractiveZone = #ociServeNonInteractive;

/// Stap-omhoog-aanmelding (RFC 9470).
///
/// Een organisatie kan eisen dat leden recent of sterk genoeg zijn aangemeld.
/// Antwoordt de server daarom met een uitdaging, dan meldt deze mixin opnieuw
/// aan met wat de uitdaging vraagt en herhaalt de gateway het verzoek één keer
/// met het verse token. Een gewone vernieuwing van het token zou niets
/// veranderen: de `auth_time` van de oorspronkelijke aanmelding blijft gelden.
mixin _OciServeStepUpMethods on OciServeNotifierBase {
  /// Voert [body] uit zonder dat een uitdaging een browser mag openen. Voor
  /// alles wat niet door een handeling van de gebruiker is gevraagd:
  /// achtergrondsynchronisatie, plaatjes. De uitdaging gaat dan als fout naar
  /// de aanroeper en de gebruiker ziet pas een browser bij wat hij zelf deed.
  @override
  Future<T> _nonInteractive<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_ociServeNonInteractiveZone: true});

  @override
  Future<String> _handleStepUp(OciServeStepUpRequired need, int epoch) async {
    if (Zone.current[_ociServeNonInteractiveZone] == true) throw need;
    if (!state.authenticated || _tokens == null) {
      throw const OciServeException('not_authenticated');
    }
    // Een aanmelding die klaar is nadat dit verzoek werd opgebouwd, geldt ook
    // hiervoor: gelijktijdige verzoeken openen niet elk een eigen browser, en
    // een vervolgstap van een handeling met een oud token pakt het nieuwe.
    if (_stepUpEpoch > epoch) return _accessToken();
    return _stepUpInFlight ??= _completeStepUp(
      need,
    ).whenComplete(() => _stepUpInFlight = null);
  }

  Future<String> _completeStepUp(OciServeStepUpRequired need) async {
    final installation = _installation;
    final configuration = _configuration;
    final accountId = state.account?.id;
    final settings = state.settings;
    if (installation == null || configuration == null || accountId == null) {
      throw const OciServeException('not_authenticated');
    }
    final generation = _generation;
    final tokens = await _authFactory(
      settings,
    ).login(installation, configuration, stepUp: need);
    if (generation != _generation) {
      throw const OciServeException('not_authenticated');
    }
    // De browser kan met een ander account zijn aangemeld, bijvoorbeeld op een
    // gedeelde computer. Dat token mag nooit in de plaats komen van dat van
    // degene die hier is aangemeld. De ongewijzigde gateway: `/me` valt niet
    // onder een organisatiebeleid.
    final account = await ref
        .read(ociServeGatewayFactoryProvider)(settings)
        .me(tokens.accessToken);
    if (generation != _generation) {
      throw const OciServeException('not_authenticated');
    }
    if (account.id != accountId) {
      throw const OciServeException('step_up_account_mismatch');
    }
    if (account.activeMemberships.isEmpty) {
      throw const OciServeException('no_active_membership');
    }
    _tokens = tokens;
    _stepUpEpoch++;
    if (settings.rememberLogin) {
      await _persistRefreshToken(settings, tokens);
      if (generation != _generation) {
        throw const OciServeException('not_authenticated');
      }
    }
    state = state.copyWith(account: account);
    return tokens.accessToken;
  }
}
