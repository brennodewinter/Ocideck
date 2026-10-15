part of 'ociserve_gateway.dart';

/// De portefeuille-import van [OciServeApi] (#2423). De server haalt zelf
/// niets op bij een badgeplatform: OciDeck levert de gevonden credentials aan
/// als import-sessie in het eigen beeld van de cursist, laat hem kiezen, en
/// maakt pas bij `select` bewijsstukken aan. Wat niet gekozen is, wordt nooit
/// gedeeld.
abstract class OciServePortfolioApi {
  /// Start een import-sessie met de gevonden credentials (stap 1: ophalen).
  /// Geeft het `import_id` terug.
  Future<String> createPortfolioImport({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required List<PortfolioImportItemInput> items,
    required String idempotencyKey,
  });

  /// Leest de import-sessie terug voor het keuzescherm.
  Future<OciServePortfolioImport> portfolioImport({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String importId,
  });

  /// Deelt de gekozen items als bewijsstuk (stap 2: delen). Geeft de
  /// `id`'s van de aangemaakte bewijsstukken.
  Future<List<String>> selectPortfolioItems({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String importId,
    required List<String> selectedItemIds,
    required String evidenceTypeId,
    required String evidenceTypeVersionId,
    required String idempotencyKey,
  });

  /// Haalt een credential-document op van een publieke verificatielink die de
  /// cursist zelf heeft geplakt. Dit is egress naar een **derde** — een
  /// willekeurige host, niet de OciServe: dus geen access token, geen
  /// `trustedInternal`, geen redirects en een eigen strakke cap. Alleen een
  /// JSON-document wordt aanvaard; HTML en alles anders is geen credential.
  Future<Object?> fetchPortfolioDocument(Uri publicUrl);
}

mixin _OciServePortfolio on OciServeGatewayBase {
  /// Eén credential-document is klein; de cap houdt een misleidende of
  /// kwaadaardige link binnen een fatsoenlijke grens.
  static const int _portfolioFetchCap = 1024 * 1024;

  @override
  Future<String> createPortfolioImport({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required List<PortfolioImportItemInput> items,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'portfolio-imports',
      ]),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'items': [for (final item in items) item.toJson()],
        }),
      ),
    );
    try {
      final importId = (_jsonObject(response)['import_id'] as String? ?? '')
          .trim();
      if (importId.isEmpty) throw const FormatException('import id');
      return importId;
    } catch (error, stack) {
      logError('OciServe: import aanmaken', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServePortfolioImport> portfolioImport({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String importId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'portfolio-imports',
        importId,
      ]),
      accessToken: accessToken,
    );
    try {
      return OciServePortfolioImport.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: import lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<List<String>> selectPortfolioItems({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String importId,
    required List<String> selectedItemIds,
    required String evidenceTypeId,
    required String evidenceTypeVersionId,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'portfolio-imports',
        importId,
        'select',
      ]),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'selected_item_ids': selectedItemIds,
          'evidence_type_id': evidenceTypeId,
          'evidence_type_version_id': evidenceTypeVersionId,
        }),
      ),
    );
    try {
      final raw = _jsonObject(response)['created_item_ids'];
      if (raw is! List) throw const FormatException('created item ids');
      return List.unmodifiable([
        for (final id in raw)
          if (id is String) id,
      ]);
    } catch (error, stack) {
      logError('OciServe: importkeuze delen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<Object?> fetchPortfolioDocument(Uri publicUrl) async {
    if (publicUrl.scheme.toLowerCase() != 'https') {
      throw const OciServeException('request_refused');
    }
    final response = await _transport.send(
      method: 'GET',
      url: publicUrl,
      trustedInternal: false,
      headers: const {'accept': 'application/json'},
      maxResponseBytes: _portfolioFetchCap,
      timeout: const Duration(seconds: 20),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const OciServeTransportException('network');
    }
    try {
      return jsonDecode(utf8.decode(response.body));
    } catch (error, stack) {
      logError(
        'OciServe: portefeuille-document lezen',
        error.runtimeType,
        stack,
      );
      throw const OciServeException('invalid_response');
    }
  }
}
