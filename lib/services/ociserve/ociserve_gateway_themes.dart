part of 'ociserve_gateway.dart';

/// Het themaregister van de organisatie (#2429): profielen delen, ophalen,
/// bijwerken en verwijderen. Bijwerken gebeurt met `If-Match` op de ETag —
/// een 409 betekent dat iemand anders tussendoor schreef (of dat de naam al
/// bezet is), nooit een stille overschrijving.
abstract class OciServeThemesApi {
  /// De profielen van de organisatie, gepagineerd.
  Future<({List<OciServeTheme> themes, String? nextCursor})> themes({
    required String accessToken,
    required String organizationId,
    String? cursor,
  });

  /// Eén profiel, met de ETag die een latere `PUT` als `If-Match` meestuurt.
  Future<({OciServeTheme theme, String? etag})> theme({
    required String accessToken,
    required String organizationId,
    required String themeId,
  });

  /// Nieuw profiel; 409 als de naam al bestaat.
  Future<OciServeTheme> createTheme({
    required String accessToken,
    required String organizationId,
    required String name,
    required Map<String, Object?> definition,
    required String idempotencyKey,
  });

  /// Werkt een bestaand profiel bij. [ifMatch] is de ETag van de versie die
  /// de aanroeper zag, of `*` als de gebruiker bewust koos om te overschrijven.
  Future<({OciServeTheme theme, String? etag})> updateTheme({
    required String accessToken,
    required String organizationId,
    required String themeId,
    required String name,
    required Map<String, Object?> definition,
    required String ifMatch,
  });

  /// Verwijdert een profiel; 409 voor ingebouwde profielen en profielen die
  /// een cursus gebruikt.
  Future<void> deleteTheme({
    required String accessToken,
    required String organizationId,
    required String themeId,
  });
}

mixin _OciServeThemes on OciServeGatewayBase {
  OciServeTheme _theme(Map<String, Object?> json) =>
      OciServeTheme.fromJson(json);

  @override
  Future<({List<OciServeTheme> themes, String? nextCursor})> themes({
    required String accessToken,
    required String organizationId,
    String? cursor,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'themes',
      ]).replace(queryParameters: {'cursor': ?cursor}),
      accessToken: accessToken,
    );
    try {
      final json = _jsonObject(response);
      final raw = json['themes'];
      if (raw is! List) throw const FormatException('themes');
      return (
        themes: List<OciServeTheme>.unmodifiable([
          for (final item in raw)
            _theme(Map<String, Object?>.from(item as Map)),
        ]),
        nextCursor: json['next_cursor'] as String?,
      );
    } catch (error, stack) {
      logError('OciServe: themas lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<({OciServeTheme theme, String? etag})> theme({
    required String accessToken,
    required String organizationId,
    required String themeId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'themes', themeId]),
      accessToken: accessToken,
    );
    try {
      return (
        theme: _theme(_jsonObject(response)),
        etag: response.headers['etag'],
      );
    } catch (error, stack) {
      logError('OciServe: thema lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeTheme> createTheme({
    required String accessToken,
    required String organizationId,
    required String name,
    required Map<String, Object?> definition,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(['organizations', organizationId, 'themes']),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(jsonEncode({'name': name, 'definition': definition})),
    );
    try {
      return _theme(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: thema delen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<({OciServeTheme theme, String? etag})> updateTheme({
    required String accessToken,
    required String organizationId,
    required String themeId,
    required String name,
    required Map<String, Object?> definition,
    required String ifMatch,
  }) async {
    final response = await _send(
      method: 'PUT',
      url: _api(['organizations', organizationId, 'themes', themeId]),
      accessToken: accessToken,
      headers: {'content-type': 'application/json', 'if-match': ifMatch},
      body: utf8.encode(jsonEncode({'name': name, 'definition': definition})),
    );
    try {
      return (
        theme: _theme(_jsonObject(response)),
        etag: response.headers['etag'],
      );
    } catch (error, stack) {
      logError('OciServe: thema bijwerken', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<void> deleteTheme({
    required String accessToken,
    required String organizationId,
    required String themeId,
  }) async {
    await _send(
      method: 'DELETE',
      url: _api(['organizations', organizationId, 'themes', themeId]),
      accessToken: accessToken,
    );
  }
}
