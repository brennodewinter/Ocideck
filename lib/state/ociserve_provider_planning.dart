part of 'ociserve_provider.dart';

/// Planning self-service: aanbod, inschrijving en eigen boekingen.
/// Dunne doorgeeflaag naar de gateway — lidmaatschap en toegangstoken zijn de
/// zelfde checks als de bestaande eLearning-methoden. Mutaties nemen de
/// idempotency-sleutel van de aanroeper over: één gebruikershandeling is één
/// sleutel, zodat een retry nooit een tweede inschrijving maakt.
mixin _OciServePlanningMethods on OciServeNotifierBase {
  Future<OciServeOfferingList> courseOfferings(
    String organizationId, {
    String? cursor,
    DateTime? from,
    DateTime? to,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).myCourseOfferings(
      accessToken: access,
      organizationId: organizationId,
      cursor: cursor,
      from: from,
      to: to,
    );
  }

  Future<OciServeOfferingSummary> courseOffering({
    required String organizationId,
    required String offeringId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).myCourseOffering(
      accessToken: access,
      organizationId: organizationId,
      offeringId: offeringId,
    );
  }

  Future<OciServeRegistration> registerForOffering({
    required String organizationId,
    required String offeringId,
    required List<String> sessionIds,
    required bool allowWaitlist,
    String? voucherCode,
    required String idempotencyKey,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).registerForOffering(
      accessToken: access,
      organizationId: organizationId,
      offeringId: offeringId,
      sessionIds: sessionIds,
      allowWaitlist: allowWaitlist,
      voucherCode: voucherCode,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<OciServeBookingList> myBookings(
    String organizationId, {
    String? cursor,
    bool includePast = false,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).myBookings(
      accessToken: access,
      organizationId: organizationId,
      cursor: cursor,
      includePast: includePast,
    );
  }

  Future<OciServeSessionBooking> cancelBooking({
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _bookingAction(
    organizationId: organizationId,
    bookingId: bookingId,
    idempotencyKey: idempotencyKey,
    action: (gateway, access, org, id, key) => gateway.cancelMyBooking(
      accessToken: access,
      organizationId: org,
      bookingId: id,
      idempotencyKey: key,
    ),
  );

  Future<OciServeSessionBooking> confirmBookingOffer({
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _bookingAction(
    organizationId: organizationId,
    bookingId: bookingId,
    idempotencyKey: idempotencyKey,
    action: (gateway, access, org, id, key) => gateway.confirmMyBookingOffer(
      accessToken: access,
      organizationId: org,
      bookingId: id,
      idempotencyKey: key,
    ),
  );

  Future<OciServeSessionBooking> declineBooking({
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _bookingAction(
    organizationId: organizationId,
    bookingId: bookingId,
    idempotencyKey: idempotencyKey,
    action: (gateway, access, org, id, key) => gateway.declineMyBooking(
      accessToken: access,
      organizationId: org,
      bookingId: id,
      idempotencyKey: key,
    ),
  );

  Future<OciServeSessionBooking> _bookingAction({
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
    required Future<OciServeSessionBooking> Function(
      OciServeApi gateway,
      String accessToken,
      String organizationId,
      String bookingId,
      String idempotencyKey,
    )
    action,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return action(
      _gatewayFactory(state.settings),
      access,
      organizationId,
      bookingId,
      idempotencyKey,
    );
  }
}
