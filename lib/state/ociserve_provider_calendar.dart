part of 'ociserve_provider.dart';

/// Het agenda-abonnement (#2427): uitgeven/roteren en intrekken. De server
/// toont de feed-URL precies één keer; OciDeck bewaart hem daarom nooit —
/// alleen de verloopdatum blijft over als apparaat-lokale staat, zodat het
/// scherm kan tonen tot wanneer het abonnement loopt. Kwijt is kwijt:
/// wie de link verliest, roteert (de oude sterft) en ziet de nieuwe eenmalig.
mixin _OciServeCalendarMethods on OciServeNotifierBase {
  /// Alleen de verloopdatum, per verbinding — de URL zelf staat bewust
  /// nergens, ook niet in de sleutelbos: hij kan nooit meer getoond worden.
  String _calendarExpiryKey(String organizationId) =>
      'ociserve_calendar_sub_expires_${state.settings.normalizedBaseUrl}_$organizationId';

  /// De bekende verloopdatum van het abonnement bij deze organisatie, of
  /// `null` als er geen bekend actief abonnement is.
  Future<DateTime?> calendarSubscriptionExpiry(String organizationId) async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(
      prefs.getString(_calendarExpiryKey(organizationId)) ?? '',
    );
  }

  /// Maakt het abonnement aan — of roteert het token als er al een was
  /// (de vorige URL is dan dood). Geeft de eenmalige feed-URL plus de
  /// verloopdatum; de UI toont de URL en wijst hem daarna weer weg.
  Future<({Uri feedUrl, DateTime expiresAt})> issueCalendarSubscription(
    String organizationId,
  ) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    final result = await _gatewayFactory(state.settings)
        .issueCalendarSubscription(
          accessToken: access,
          organizationId: organizationId,
          idempotencyKey: _uuid.v4(),
        );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _calendarExpiryKey(organizationId),
      result.expiresAt.toIso8601String(),
    );
    return result;
  }

  /// Trekt het abonnement in. Een 404 op de server betekent "was er al niet
  /// meer" — de lokale staat gaat dan net zo goed weg.
  Future<void> revokeCalendarSubscription(String organizationId) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    try {
      await _gatewayFactory(state.settings).revokeCalendarSubscription(
        accessToken: access,
        organizationId: organizationId,
      );
    } on OciServeException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_calendarExpiryKey(organizationId));
  }
}
