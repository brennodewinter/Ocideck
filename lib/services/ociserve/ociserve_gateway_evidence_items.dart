part of 'ociserve_gateway.dart';

/// Het bewijsstukdeel van [OciServeApi]: bewijssoorten lezen, een geüpload
/// bestand als bewijsstuk indienen en de eigen stukken volgen. Een upload alleen
/// is een losse, geverifieerde blob; pas het bewijsstuk komt in de
/// beoordelingswachtrij van de organisatie.
abstract class OciServeEvidenceItemApi {
  /// De gepubliceerde bewijssoorten van de organisatie.
  Future<List<OciServeEvidenceType>> evidenceTypes({
    required String accessToken,
    required String organizationId,
  });

  /// Dient een schone upload in als bewijsstuk (`ingediend`). De server eist
  /// dat de upload `clean` is en bij deze cursist hoort.
  Future<OciServeEvidenceItem> createEvidenceItem({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String evidenceTypeId,
    required String uploadId,
    required String idempotencyKey,
    DateTime? declaredValidUntil,
  });

  /// De gepubliceerde versies van een bewijssoort. De portefeuille-selectie
  /// (#2423) heeft de versie-id nodig om een bewijsstuk te maken.
  Future<List<OciServeEvidenceTypeVersion>> evidenceTypeVersions({
    required String accessToken,
    required String organizationId,
    required String evidenceTypeId,
  });

  /// Trekt een `ingediend` of `in_behandeling` bewijsstuk in. Alleen de
  /// cursist zelf mag intrekken.
  Future<OciServeEvidenceItem> withdrawEvidenceItem({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String evidenceItemId,
    required String idempotencyKey,
  });

  /// De eigen bewijsstukken van de cursist.
  Future<List<OciServeEvidenceItem>> evidenceItems({
    required String accessToken,
    required String organizationId,
    required String participantId,
  });
}

mixin _OciServeEvidenceItems on OciServeGatewayBase {
  @override
  Future<List<OciServeEvidenceType>> evidenceTypes({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'evidence-types']),
      accessToken: accessToken,
    );
    try {
      final raw = _jsonObject(response)['evidence_types'];
      if (raw is! List) throw const FormatException('evidence types');
      return List.unmodifiable([
        for (final item in raw)
          ?OciServeEvidenceType.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
      ]);
    } catch (error, stack) {
      logError('OciServe: bewijssoorten lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeEvidenceItem> createEvidenceItem({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String evidenceTypeId,
    required String uploadId,
    required String idempotencyKey,
    DateTime? declaredValidUntil,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'evidence-items',
      ]),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'evidence_type_id': evidenceTypeId,
          'upload_id': uploadId,
          if (declaredValidUntil != null)
            'declared_valid_until': declaredValidUntil
                .toUtc()
                .toIso8601String(),
        }),
      ),
    );
    try {
      return OciServeEvidenceItem.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: bewijsstuk indienen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<List<OciServeEvidenceTypeVersion>> evidenceTypeVersions({
    required String accessToken,
    required String organizationId,
    required String evidenceTypeId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'evidence-types',
        evidenceTypeId,
        'versions',
      ]),
      accessToken: accessToken,
    );
    try {
      final raw = _jsonObject(response)['versions'];
      if (raw is! List) throw const FormatException('type versions');
      return List.unmodifiable([
        for (final item in raw)
          OciServeEvidenceTypeVersion.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
      ]);
    } catch (error, stack) {
      logError('OciServe: bewijssoortversies lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeEvidenceItem> withdrawEvidenceItem({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String evidenceItemId,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'evidence-items',
        evidenceItemId,
        'withdraw',
      ]),
      accessToken: accessToken,
      headers: {'idempotency-key': idempotencyKey},
    );
    try {
      return OciServeEvidenceItem.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: bewijsstuk intrekken', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<List<OciServeEvidenceItem>> evidenceItems({
    required String accessToken,
    required String organizationId,
    required String participantId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'evidence-items',
      ]),
      accessToken: accessToken,
    );
    try {
      final raw = _jsonObject(response)['evidence_items'];
      if (raw is! List) throw const FormatException('evidence items');
      return List.unmodifiable([
        for (final item in raw)
          OciServeEvidenceItem.fromJson(Map<String, Object?>.from(item as Map)),
      ]);
    } catch (error, stack) {
      logError('OciServe: bewijsstukken lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }
}
