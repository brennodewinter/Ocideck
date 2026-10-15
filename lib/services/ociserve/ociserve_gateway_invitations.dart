part of 'ociserve_gateway.dart';

/// Uitnodigingsregistratie (#2425): de publieke preview- en
/// registratieroutes, en de aangemelde acceptatie. De publieke routes sturen
/// géén token mee (`security: []`) en krijgen één generieke 400 voor elke
/// ongeldige combinatie — die vaagheid is anti-enumeratie en hoort zo naar de
/// gebruiker terug.
abstract class OciServeInvitationsApi {
  /// Controleert uitnodigingsnummer + eenmalige code; geeft alleen het
  /// uitgenodigde e-mailadres terug.
  Future<String> invitationRegistrationPreview({
    required String invitationId,
    required String secret,
  });

  /// Registreert een nieuwe identiteit op de uitnodiging en accepteert hem
  /// atomisch. Het wachtwoord gaat rechtstreeks naar de provider-adapter —
  /// deze methode logt het nooit en bewaart het nergens; de idempotency-
  /// sleutel maakt een retry veilig zonder een tweede account.
  Future<OciServeInvitationResult> invitationRegister({
    required String invitationId,
    required String secret,
    required String displayName,
    required String password,
    required String idempotencyKey,
  });

  /// Accepteert een uitnodiging namens de aangemelde identiteit.
  Future<OciServeInvitationResult> invitationAccept({
    required String accessToken,
    required String invitationId,
    required String secret,
    String? displayName,
    required String idempotencyKey,
  });
}

/// Wat de server teruggeeft na registratie of acceptatie.
class OciServeInvitationResult {
  const OciServeInvitationResult({
    required this.organizationId,
    required this.role,
  });

  final String organizationId;
  final String role;
}

mixin _OciServeInvitations on OciServeGatewayBase {
  @override
  Future<String> invitationRegistrationPreview({
    required String invitationId,
    required String secret,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(['invitation-registration-preview']),
      headers: {'content-type': 'application/json'},
      body: utf8.encode(
        jsonEncode({'invitation_id': invitationId, 'secret': secret}),
      ),
    );
    try {
      final email = (_jsonObject(response)['invited_email'] as String? ?? '')
          .trim();
      if (email.isEmpty) throw const FormatException();
      return email;
    } catch (error, stack) {
      logError('OciServe: uitnodiging controleren', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeInvitationResult> invitationRegister({
    required String invitationId,
    required String secret,
    required String displayName,
    required String password,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(['invitation-registrations']),
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'invitation_id': invitationId,
          'secret': secret,
          'display_name': displayName,
          'password': password,
        }),
      ),
    );
    return _invitationResult(response);
  }

  @override
  Future<OciServeInvitationResult> invitationAccept({
    required String accessToken,
    required String invitationId,
    required String secret,
    String? displayName,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(['invitation-acceptances']),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'invitation_id': invitationId,
          'secret': secret,
          'display_name': ?displayName,
        }),
      ),
    );
    return _invitationResult(response);
  }

  OciServeInvitationResult _invitationResult(OciServeHttpResponse response) {
    try {
      final json = _jsonObject(response);
      final organizationId = (json['organization_id'] as String? ?? '').trim();
      if (organizationId.isEmpty) throw const FormatException();
      return OciServeInvitationResult(
        organizationId: organizationId,
        role: (json['role'] as String? ?? '').trim(),
      );
    } catch (error, stack) {
      logError(
        'OciServe: uitnodigingsantwoord lezen',
        error.runtimeType,
        stack,
      );
      throw const OciServeException('invalid_response');
    }
  }
}
