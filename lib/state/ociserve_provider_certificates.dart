part of 'ociserve_provider.dart';

/// De certificaten van deze deelnemer (#2426). De lijst is een leesmodel voor
/// "Mijn bewijs"; de PDF wordt pas opgehaald als de gebruiker bewust kiest
/// om te kijken of te bewaren — niets belandt in cache of log.
mixin _OciServeCertificateMethods on OciServeNotifierBase {
  /// Alle certificaten van deze deelnemer bij deze organisatie, inclusief de
  /// ingetrokken exemplaren.
  Future<List<OciServeCertificate>> participantCertificates({
    required String organizationId,
    required String participantId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).participantCertificates(
      accessToken: access,
      organizationId: organizationId,
      participantId: participantId,
    );
  }

  /// De PDF van een certificaat — alleen op expliciet verzoek, voor
  /// bekijken of bewust bewaren.
  Future<Uint8List> certificatePdf({
    required String organizationId,
    required String certificateId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).certificatePdf(
      accessToken: access,
      organizationId: organizationId,
      certificateId: certificateId,
    );
  }
}
