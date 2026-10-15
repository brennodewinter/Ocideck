part of 'ociserve_gateway.dart';

/// Het agenda-abonnement van de deelnemer (#2427). POST geeft eenmalig de
/// volledige feed-URL met het bearer-token erin; de server bewaart alleen de
/// hash. Daarom geldt: de URL gaat nooit een log of een opslag in — hij
/// bestaat alleen in het scherm dat hem toont. Een tweede POST roteert het
/// token en maakt de vorige URL ongeldig.
abstract class OciServeCalendarApi {
  /// Maakt het abonnement aan of roteert het token. Geeft de eenmalige
  /// absolute feed-URL en de verloopdatum.
  Future<({Uri feedUrl, DateTime expiresAt})> issueCalendarSubscription({
    required String accessToken,
    required String organizationId,
    required String idempotencyKey,
  });

  /// Trekt het abonnement in; daarna is de feed-URL dood.
  Future<void> revokeCalendarSubscription({
    required String accessToken,
    required String organizationId,
  });
}

mixin _OciServeCalendar on OciServeGatewayBase {
  @override
  Future<({Uri feedUrl, DateTime expiresAt})> issueCalendarSubscription({
    required String accessToken,
    required String organizationId,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'calendar-subscription',
      ]),
      accessToken: accessToken,
      headers: {'idempotency-key': idempotencyKey},
    );
    try {
      final json = _jsonObject(response);
      final raw = (json['url'] as String? ?? '').trim();
      final expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '');
      if (raw.isEmpty || expiresAt == null) throw const FormatException();
      // `url` is relatief aan de API-basis; de gebruiker plakt hem in een
      // agenda-app en heeft dus het absolute adres nodig.
      final feedUrl = Uri.parse(settings.normalizedBaseUrl).resolve(raw);
      return (feedUrl: feedUrl, expiresAt: expiresAt);
    } catch (error, stack) {
      // Alleen het type fout gaat de log in — nooit de URL met het token.
      logError(
        'OciServe: agenda-abonnement uitgeven',
        error.runtimeType,
        stack,
      );
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<void> revokeCalendarSubscription({
    required String accessToken,
    required String organizationId,
  }) async {
    await _send(
      method: 'DELETE',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'calendar-subscription',
      ]),
      accessToken: accessToken,
    );
  }
}
