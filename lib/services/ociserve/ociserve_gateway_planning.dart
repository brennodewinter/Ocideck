part of 'ociserve_gateway.dart';

/// Het planningdeel van [OciServeApi]: zelfinschrijving via het self-service
/// `me/`-oppervlak (issues #2122–#2127). De declaraties staan hier zodat het
/// hoofdbestand onder de bestandsgrens blijft; de implementatie zit in de
/// mixin [_OciServePlanning] hieronder.
abstract class OciServePlanningApi {
  /// Catalogus van uitvoeringen waar zelfinschrijving voor openstaat.
  Future<OciServeOfferingList> myCourseOfferings({
    required String accessToken,
    required String organizationId,
    String? cursor,
    DateTime? from,
    DateTime? to,
  });

  /// Eén uitvoering met sessies en de eigen toelatingsevaluatie.
  Future<OciServeOfferingSummary> myCourseOffering({
    required String accessToken,
    required String organizationId,
    required String offeringId,
  });

  /// Schrijft de caller in: één sessie per klassikale les, eventueel met
  /// wachtlijst en/of vouchercode.
  Future<OciServeRegistration> registerForOffering({
    required String accessToken,
    required String organizationId,
    required String offeringId,
    required List<String> sessionIds,
    required bool allowWaitlist,
    String? voucherCode,
    required String idempotencyKey,
  });

  /// De eigen boekingen, vroegste sessie eerst.
  Future<OciServeBookingList> myBookings({
    required String accessToken,
    required String organizationId,
    String? cursor,
    bool includePast = false,
  });

  /// Meldt de eigen boeking af (idempotent via [idempotencyKey]).
  Future<OciServeSessionBooking> cancelMyBooking({
    required String accessToken,
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  });

  /// Neemt een vrijgekomen plaats aan op een `offered` boeking.
  Future<OciServeSessionBooking> confirmMyBookingOffer({
    required String accessToken,
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  });

  /// Geeft een wachtlijstplaats of aanbod vrij.
  Future<OciServeSessionBooking> declineMyBooking({
    required String accessToken,
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  });
}

/// Leest een RFC 7807-probleemantwoord (`type`, `detail`) plus `Retry-After`
/// uit een foutresponse; `null` als er niets bruikbaars in staat. Faalt
/// stil — een kapot probleemantwoord mag de eigenlijke fout niet verbergen.
OciServeProblem? _problemDetails(OciServeHttpResponse response) {
  try {
    String? type;
    String? detail;
    final decoded = jsonDecode(utf8.decode(response.body));
    if (decoded is Map) {
      type = (decoded['type'] as String?)?.trim();
      detail = (decoded['detail'] as String?)?.trim();
    }
    Duration? retryAfter;
    final raw = response.headers['retry-after']?.trim();
    final seconds = raw == null ? null : int.tryParse(raw);
    if (seconds != null && seconds > 0) {
      retryAfter = Duration(seconds: seconds);
    }
    if (type == null && detail == null && retryAfter == null) return null;
    return OciServeProblem(type: type, detail: detail, retryAfter: retryAfter);
  } on FormatException {
    // Probleemdetails zijn best-effort: een kapotte body mag de eigenlijke
    // foutstatus niet overschrijven.
    return null;
  }
}

/// Planning self-service: het `me/`-oppervlak waarmee een cursist aanbod
/// bekijkt, zich inschrijft en de eigen boekingen beheert (issues
/// #2122–#2127). Alle methoden zijn zelf-gescoped — de server leent de
/// deelnemer uit het access token, de client kan nooit andermans boeking
/// of toelatingsevaluatie opvragen.
///
/// Mutaties sturen een `Idempotency-Key` mee, zoals de bestaande
/// bewijsuploads en examenpogingen: een herhaalde klik of retry levert dan
/// geen dubbele inschrijving op. De aanroeper geeft de sleutel mee zodat
/// één gebruikershandeling één sleutel heeft.
mixin _OciServePlanning on OciServeGatewayBase {
  Uri _planningApi(List<String> segments, {Map<String, String>? query}) {
    final url = _api(segments);
    return query == null || query.isEmpty
        ? url
        : url.replace(queryParameters: query);
  }

  /// Leest de body als object en parseert hem; elke leesfout — kapotte JSON
  /// of een ontbrekend verplicht veld — wordt `invalid_response`, zoals de
  /// rest van de gateway dat doet.
  T _planningParse<T>(
    OciServeHttpResponse response,
    String what,
    T Function(Map<String, Object?>) parse,
  ) {
    try {
      return parse(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: $what lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeOfferingList> myCourseOfferings({
    required String accessToken,
    required String organizationId,
    String? cursor,
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _planningApi(
        ['organizations', organizationId, 'me', 'course-offerings'],
        query: {
          'limit': '100',
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': to.toUtc().toIso8601String(),
        },
      ),
      accessToken: accessToken,
    );
    return _planningParse(
      response,
      'aanbodantwoord',
      OciServeOfferingList.fromJson,
    );
  }

  @override
  Future<OciServeOfferingSummary> myCourseOffering({
    required String accessToken,
    required String organizationId,
    required String offeringId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'course-offerings',
        offeringId,
      ]),
      accessToken: accessToken,
    );
    return _planningParse(
      response,
      'uitvoeringsantwoord',
      OciServeOfferingSummary.fromJson,
    );
  }

  @override
  Future<OciServeRegistration> registerForOffering({
    required String accessToken,
    required String organizationId,
    required String offeringId,
    required List<String> sessionIds,
    required bool allowWaitlist,
    String? voucherCode,
    required String idempotencyKey,
  }) async {
    final voucher = voucherCode?.trim();
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'course-offerings',
        offeringId,
        'registrations',
      ]),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'session_ids': sessionIds,
          'allow_waitlist': allowWaitlist,
          // De code gaat alleen mee in het verzoek; hij wordt nergens
          // bewaard of gelogd (issue #2125).
          if (voucher != null && voucher.isNotEmpty) 'voucher_code': voucher,
        }),
      ),
    );
    if (response.statusCode != 201) {
      throw const OciServeException('invalid_response');
    }
    return _planningParse(
      response,
      'inschrijvingsantwoord',
      OciServeRegistration.fromJson,
    );
  }

  @override
  Future<OciServeBookingList> myBookings({
    required String accessToken,
    required String organizationId,
    String? cursor,
    bool includePast = false,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _planningApi(
        ['organizations', organizationId, 'me', 'bookings'],
        query: {
          'limit': '100',
          if (includePast) 'include_past': 'true',
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        },
      ),
      accessToken: accessToken,
    );
    return _planningParse(
      response,
      'boekingenantwoord',
      OciServeBookingList.fromJson,
    );
  }

  @override
  Future<OciServeSessionBooking> cancelMyBooking({
    required String accessToken,
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _bookingAction(
    accessToken: accessToken,
    organizationId: organizationId,
    bookingId: bookingId,
    action: 'cancel',
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<OciServeSessionBooking> confirmMyBookingOffer({
    required String accessToken,
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _bookingAction(
    accessToken: accessToken,
    organizationId: organizationId,
    bookingId: bookingId,
    action: 'confirm',
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<OciServeSessionBooking> declineMyBooking({
    required String accessToken,
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _bookingAction(
    accessToken: accessToken,
    organizationId: organizationId,
    bookingId: bookingId,
    action: 'decline',
    idempotencyKey: idempotencyKey,
  );

  Future<OciServeSessionBooking> _bookingAction({
    required String accessToken,
    required String organizationId,
    required String bookingId,
    required String action,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'bookings',
        bookingId,
        action,
      ]),
      accessToken: accessToken,
      headers: {'idempotency-key': idempotencyKey},
      body: const [],
    );
    return _planningParse(
      response,
      'boekingmutatie',
      OciServeSessionBooking.fromJson,
    );
  }
}
