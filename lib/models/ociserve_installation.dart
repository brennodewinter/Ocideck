part of 'ociserve_models.dart';

@immutable
class OciServeInstallation {
  const OciServeInstallation({
    required this.clientId,
    required this.issuer,
    this.webSession = false,
  });

  final String clientId;
  final Uri issuer;
  final bool webSession;

  factory OciServeInstallation.fromJson(Map<String, Object?> json) {
    final oidc = json['oidc'] is Map
        ? Map<String, Object?>.from(json['oidc']! as Map)
        : const <String, Object?>{};
    String field(String key) =>
        ((json[key] ?? oidc[key]) as String? ?? '').trim();
    final clientId = field('ocideck_native_client_id');
    final issuer = Uri.tryParse(field('oidc_issuer'));
    if ((clientId.isEmpty && json['ocideck_web_session'] != true) ||
        issuer == null) {
      throw const FormatException('incomplete OciServe installation');
    }
    return OciServeInstallation(
      clientId: clientId,
      issuer: issuer,
      webSession: json['ocideck_web_session'] == true,
    );
  }
}
