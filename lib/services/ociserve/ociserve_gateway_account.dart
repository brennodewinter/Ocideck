part of 'ociserve_gateway.dart';

/// Het accountdeel van [OciServeApi] (issue #2428): de aanmelding als
/// auditgebeurtenis registreren, het daadwerkelijk openen van een les melden,
/// en de eigen profielfoto wijzigen of verwijderen.
abstract class OciServeAccountApi {
  /// Registreert een geslaagde interactieve aanmelding bij OciServe. De
  /// server schrijft die in het toegangslogboek van de organisatie — zodat
  /// een beheerder kan zien wanneer een cursist voor het laatst echt
  /// aanmeldde, niet alleen wanneer een token werd ververst.
  Future<void> reportOciDeckLogin({
    required String accessToken,
    required String idempotencyKey,
  });

  /// Meldt dat een les na een geslaagde integriteitscontrole écht geopend
  /// is — niet bij het downloaden en niet bij een mislukte open. De server
  /// gebruikt dit voor "de cursist is begonnen" in de leerstatistieken.
  Future<void> markLessonOpened({
    required String accessToken,
    required String organizationId,
    required String versionId,
    required String lessonId,
    required String idempotencyKey,
  });

  /// Vervangt de eigen profielfoto. Geeft de hash terug die `GET me/avatar`
  /// daarna serveert. De server bewaakt een 5-MiB-grens en toetst de bytes
  /// aan het verklaarde beeldtype; dezelfde tweewaardige toets staat hier
  /// al, zodat een afwijzing niet pas op de server ontdekt wordt.
  Future<String> replaceAccountAvatar({
    required String accessToken,
    required Uint8List bytes,
    required String contentType,
  });

  /// Verwijdert de eigen profielfoto.
  Future<void> removeAccountAvatar({required String accessToken});
}

mixin _OciServeAccount on OciServeGatewayBase implements OciServeAccountApi {
  @override
  Future<void> reportOciDeckLogin({
    required String accessToken,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(['auth', 'ocideck-login']),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode('{}'),
    );
    if (response.statusCode != 204) {
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<void> markLessonOpened({
    required String accessToken,
    required String organizationId,
    required String versionId,
    required String lessonId,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'course-versions',
        versionId,
        'lessons',
        lessonId,
        'opened',
      ]),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode('{}'),
    );
    if (response.statusCode != 204) {
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<String> replaceAccountAvatar({
    required String accessToken,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final declared = contentType.trim().toLowerCase();
    if (bytes.isEmpty ||
        bytes.length > _avatarCap ||
        !_hasMatchingImageSignature(bytes, declared)) {
      throw const OciServeException('invalid_avatar_image');
    }
    final boundary = 'ocideck-avatar-${_uuid.v4()}';
    final head = utf8.encode(
      '--$boundary\r\n'
      'content-disposition: form-data; name="file"; '
      'filename="avatar.${declared == 'image/png'
          ? 'png'
          : declared == 'image/jpeg'
          ? 'jpg'
          : 'webp'}"\r\n'
      'content-type: $declared\r\n\r\n',
    );
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    final response = await _send(
      method: 'PUT',
      url: _api(['me', 'avatar']),
      accessToken: accessToken,
      headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
      body: [...head, ...bytes, ...tail],
    );
    try {
      final hash = (_jsonObject(response)['hash'] as String? ?? '')
          .trim()
          .toLowerCase();
      // De server mag de afbeelding herschalen of van metadata ontdoen —
      // daarom wordt de teruggegeven hash alleen op vorm getoetst, niet op
      // gelijkheid met de verstuurde bytes.
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        throw const FormatException('avatar hash missing');
      }
      return hash;
    } catch (error, stack) {
      logError(
        'OciServe: profielfoto-antwoord lezen',
        error.runtimeType,
        stack,
      );
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<void> removeAccountAvatar({required String accessToken}) async {
    final response = await _send(
      method: 'DELETE',
      url: _api(['me', 'avatar']),
      accessToken: accessToken,
      body: const [],
    );
    if (response.statusCode != 204) {
      throw const OciServeException('invalid_response');
    }
  }
}
