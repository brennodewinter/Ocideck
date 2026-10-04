part of 'ociserve_provider.dart';

/// Managed Intake aan de organisatorkant (FORM_INTAKE.md §7.8): één naad
/// die lidmaatschap toetst en het accesstoken ophaalt, waarna de aanroeper
/// zelf kiest welke intake-route hij nodig heeft. De twaalf routes zijn
/// contract-werk van de gateway; hier elke aanroep nog eens omhullen zou
/// alleen een tweede lijst namen toevoegen.
mixin _OciServeIntakeMethods on OciServeNotifierBase {
  /// Voert [call] uit met een geauthenticeerde gateway voor
  /// [organizationId] — lidmaatschap en token zoals elke organisatorroute.
  Future<T> withIntakeGateway<T>(
    String organizationId,
    Future<T> Function(OciServeIntakeApi api, String accessToken) call,
  ) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return call(_gatewayFactory(state.settings), access);
  }
}
