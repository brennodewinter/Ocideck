part of 'ociserve_gateway.dart';

/// Het certificatendeel van [OciServeApi] (#2426): de eigen certificatenlijst
/// en de PDF-download. De PDF draagt het verificatiegeheim — de gateway levert
/// alleen de bytes; wat de laag daarmee doet (viewer, bewuste opslag) is een
/// UI-beslissing, en de inhoud komt nooit in een log.
abstract class OciServeCertificatesApi {
  /// De certificaten van deze deelnemer.
  Future<List<OciServeCertificate>> participantCertificates({
    required String accessToken,
    required String organizationId,
    required String participantId,
  });

  /// De PDF van een certificaat. Alleen bytes die er echt als PDF uitzien
  /// verlaten de gateway — de content-header is een claim, geen bewijs.
  Future<Uint8List> certificatePdf({
    required String accessToken,
    required String organizationId,
    required String certificateId,
  });
}

mixin _OciServeCertificates on OciServeGatewayBase {
  /// Een certificaat-PDF is klein; de cap houdt een afwijkende server binnen
  /// dezelfde grens als de bewijsdownloads.
  static const int _certificateCap = 8 * 1024 * 1024;

  @override
  Future<List<OciServeCertificate>> participantCertificates({
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
        'certificates',
      ]),
      accessToken: accessToken,
    );
    try {
      final raw = _jsonObject(response)['certificates'];
      if (raw is! List) throw const FormatException('certificates');
      return List.unmodifiable([
        for (final item in raw)
          OciServeCertificate.fromJson(Map<String, Object?>.from(item as Map)),
      ]);
    } catch (error, stack) {
      logError('OciServe: certificaten lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<Uint8List> certificatePdf({
    required String accessToken,
    required String organizationId,
    required String certificateId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'certificates',
        certificateId,
        'pdf',
      ]),
      accessToken: accessToken,
      cap: _certificateCap,
    );
    final bytes = response.body;
    if (!isSupportedPdfEvidence(bytes)) {
      logError('OciServe: certificaat-PDF lezen', 'invalid_payload', null);
      throw const OciServeException('invalid_response');
    }
    return bytes;
  }
}
