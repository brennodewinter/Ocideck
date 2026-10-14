part of 'ociserve_provider.dart';

/// Bewijssoorten en bewijsstukken: dunne doorgeeflaag naar de gateway, met
/// dezelfde lidmaatschap- en tokenchecks als de rest van de notifier. In een
/// eigen part-bestand om de provider onder de bestandsgrens te houden.
mixin _OciServeEvidenceItemMethods on OciServeNotifierBase {
  Future<List<OciServeEvidenceType>> evidenceTypes(
    String organizationId,
  ) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(
      state.settings,
    ).evidenceTypes(accessToken: access, organizationId: organizationId);
  }

  Future<OciServeEvidenceItem> createEvidenceItem({
    required String organizationId,
    required String participantId,
    required String evidenceTypeId,
    required String uploadId,
    required String idempotencyKey,
    DateTime? declaredValidUntil,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).createEvidenceItem(
      accessToken: access,
      organizationId: organizationId,
      participantId: participantId,
      evidenceTypeId: evidenceTypeId,
      uploadId: uploadId,
      idempotencyKey: idempotencyKey,
      declaredValidUntil: declaredValidUntil,
    );
  }

  Future<List<OciServeEvidenceItem>> evidenceItems({
    required String organizationId,
    required String participantId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).evidenceItems(
      accessToken: access,
      organizationId: organizationId,
      participantId: participantId,
    );
  }
}
