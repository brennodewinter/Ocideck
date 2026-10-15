part of 'ociserve_provider.dart';

/// Uitnodigingen (#2425). Preview en registratie zijn publiek — ze lopen vóór
/// er een sessie is en gebruiken alleen het ingestelde serveradres. Acceptatie
/// is juist aangemeld: die hoort bij een bestaande identiteit die een extra
/// organisatie binnenkomt.
mixin _OciServeInvitationMethods on OciServeNotifierBase {
  /// Controleert uitnodigingsnummer + eenmalige code en geeft het
  /// uitgenodigde adres terug. Elke ongeldige combinatie krijgt dezelfde
  /// generieke 400 — dat is anti-enumeratie, geen gebrek aan detail.
  Future<String> previewInvitation({
    required String invitationId,
    required String secret,
  }) {
    return _gatewayFactory(
      state.settings,
    ).invitationRegistrationPreview(invitationId: invitationId, secret: secret);
  }

  /// Registreert en accepteert de uitnodiging atomisch. Het wachtwoord gaat
  /// alleen mee in dit request — nergens anders. De sleutel hoort bij één
  /// schermsessie, zodat dubbelklikken en herstel nooit een tweede account
  /// maken.
  Future<OciServeInvitationResult> registerInvitation({
    required String invitationId,
    required String secret,
    required String displayName,
    required String password,
    required String idempotencyKey,
  }) {
    return _gatewayFactory(state.settings).invitationRegister(
      invitationId: invitationId,
      secret: secret,
      displayName: displayName,
      password: password,
      idempotencyKey: idempotencyKey,
    );
  }

  /// Accepteert een uitnodiging met het bestaande account; daarna zit de
  /// nieuwe organisatie in het lidmaatschap, dus verversen we `me`.
  Future<void> acceptInvitation({
    required String invitationId,
    required String secret,
    String? displayName,
    required String idempotencyKey,
  }) async {
    final access = await _accessToken();
    await _gatewayFactory(state.settings).invitationAccept(
      accessToken: access,
      invitationId: invitationId,
      secret: secret,
      displayName: displayName,
      idempotencyKey: idempotencyKey,
    );
    final account = await _gatewayFactory(state.settings).me(access);
    state = state.copyWith(account: account);
  }
}
