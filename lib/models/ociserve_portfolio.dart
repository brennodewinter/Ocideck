import 'package:flutter/foundation.dart';

/// The state of a portfolio connection.
///
/// OciServe#524 will define the server-side protocol. Until then,
/// the UI shows `unavailable` so the learner knows the feature
/// exists but is not yet active for their organisation.
enum PortfolioConnectionState {
  /// The server has not enabled portfolio import yet.
  unavailable,
  /// The learner has not connected a portfolio.
  disconnected,
  /// The learner started the OAuth flow but has not finished it.
  connecting,
  /// The learner has a connected portfolio with available credentials.
  connected,
  /// The connection was revoked by the learner or the provider.
  revoked;
}

/// A credential retrieved from a connected portfolio.
///
/// Maps to what OciServe#524 will return. The learner chooses which
/// credentials to share with the organisation for badge evidence.
@immutable
class PortfolioCredential {
  const PortfolioCredential({
    required this.id,
    required this.title,
    required this.issuer,
    this.issuedAt,
    this.expiresAt,
    this.credentialType = '',
    this.selected = false,
  });

  final String id;
  final String title;
  final String issuer;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final String credentialType;
  final bool selected;

  /// Whether the credential is currently valid (not expired).
  bool get isActive =>
      expiresAt == null || expiresAt!.isAfter(DateTime.now());

  PortfolioCredential copyWith({bool? selected}) => PortfolioCredential(
        id: id,
        title: title,
        issuer: issuer,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        credentialType: credentialType,
        selected: selected ?? this.selected,
      );

  factory PortfolioCredential.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('incomplete credential');
    return PortfolioCredential(
      id: id,
      title: (json['title'] as String? ?? '').trim(),
      issuer: (json['issuer'] as String? ?? '').trim(),
      issuedAt: DateTime.tryParse(json['issued_at'] as String? ?? ''),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      credentialType: (json['credential_type'] as String? ?? '').trim(),
    );
  }
}

/// A connected portfolio source (e.g. EduBadges, Open Badges Wallet).
@immutable
class PortfolioConnection {
  const PortfolioConnection({
    required this.providerId,
    required this.providerName,
    required this.state,
    this.connectedAt,
    this.credentials = const [],
  });

  final String providerId;
  final String providerName;
  final PortfolioConnectionState state;
  final DateTime? connectedAt;
  final List<PortfolioCredential> credentials;

  /// The credentials the learner has chosen to share.
  List<PortfolioCredential> get selectedCredentials =>
      credentials.where((c) => c.selected).toList(growable: false);

  factory PortfolioConnection.fromJson(Map<String, Object?> json) {
    final providerId = (json['provider_id'] as String? ?? '').trim();
    if (providerId.isEmpty) {
      throw const FormatException('incomplete portfolio connection');
    }
    final stateStr = (json['state'] as String? ?? 'unavailable').trim();
    final credentialsRaw = json['credentials'] as List? ?? const [];
    return PortfolioConnection(
      providerId: providerId,
      providerName: (json['provider_name'] as String? ?? '').trim(),
      state: switch (stateStr) {
        'disconnected' => PortfolioConnectionState.disconnected,
        'connecting' => PortfolioConnectionState.connecting,
        'connected' => PortfolioConnectionState.connected,
        'revoked' => PortfolioConnectionState.revoked,
        _ => PortfolioConnectionState.unavailable,
      },
      connectedAt: DateTime.tryParse(
        json['connected_at'] as String? ?? '',
      ),
      credentials: credentialsRaw
          .map((item) => PortfolioCredential.fromJson(
                Map<String, Object?>.from(item as Map),
              ))
          .toList(growable: false),
    );
  }
}
