part of 'ociserve_provider.dart';

/// De portefeuille-import (#2423): haal credentials binnen via een publieke
/// verificatielink of een gedownload credential-bestand, land ze in een
/// import-sessie in het eigen beeld, en deel pas wat de cursist aanvinkt.
/// Niet-gekozen items verlaten de sessie nooit richting het dossier.
mixin _OciServePortfolioMethods on OciServeNotifierBase {
  /// Leest een publieke verificatielink of plakt een gedecodeerd document en
  /// geeft de gevonden credentials terug. De link gaat naar een willekeurige
  /// externe host — de gateway stuurt daar geen token naartoe.
  Future<List<PortfolioImportItemInput>> fetchPortfolioCredentials(
    Uri publicUrl,
  ) async {
    final gateway = _gatewayFactory(state.settings);
    final decoded = await _nonInteractive(
      () => gateway.fetchPortfolioDocument(publicUrl),
    );
    return portfolioItemsFromJson(decoded);
  }

  /// Landt de gevonden credentials in een import-sessie (stap 1: ophalen).
  /// Geeft het `import_id` van de sessie.
  Future<String> createPortfolioImport({
    required String organizationId,
    required String participantId,
    required List<PortfolioImportItemInput> items,
    required String idempotencyKey,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).createPortfolioImport(
      accessToken: access,
      organizationId: organizationId,
      participantId: participantId,
      items: items,
      idempotencyKey: idempotencyKey,
    );
  }

  /// Leest de import-sessie terug voor het keuzescherm.
  Future<OciServePortfolioImport> portfolioImport({
    required String organizationId,
    required String participantId,
    required String importId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).portfolioImport(
      accessToken: access,
      organizationId: organizationId,
      participantId: participantId,
      importId: importId,
    );
  }

  /// Deelt de aangevinkte items onder [evidenceTypeId] (stap 2: delen) en
  /// geeft de id's van de aangemaakte bewijsstukken. De versie-id zoekt hij
  /// zelf op: altijd de nieuwste gepubliceerde versie van de soort.
  Future<List<String>> sharePortfolioItems({
    required String organizationId,
    required String participantId,
    required String importId,
    required List<String> selectedItemIds,
    required String evidenceTypeId,
    required String idempotencyKey,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    final gateway = _gatewayFactory(state.settings);
    final versions = await gateway.evidenceTypeVersions(
      accessToken: access,
      organizationId: organizationId,
      evidenceTypeId: evidenceTypeId,
    );
    if (versions.isEmpty) {
      throw const OciServeException('evidence_type_not_published');
    }
    final latest = versions.reduce((a, b) => a.version >= b.version ? a : b);
    return gateway.selectPortfolioItems(
      accessToken: access,
      organizationId: organizationId,
      participantId: participantId,
      importId: importId,
      selectedItemIds: selectedItemIds,
      evidenceTypeId: evidenceTypeId,
      evidenceTypeVersionId: latest.id,
      idempotencyKey: idempotencyKey,
    );
  }

  /// Trekt een nog niet beoordeeld bewijsstuk in.
  Future<OciServeEvidenceItem> withdrawEvidenceItem({
    required String organizationId,
    required String participantId,
    required String evidenceItemId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).withdrawEvidenceItem(
      accessToken: access,
      organizationId: organizationId,
      participantId: participantId,
      evidenceItemId: evidenceItemId,
      idempotencyKey: _uuid.v4(),
    );
  }
}
