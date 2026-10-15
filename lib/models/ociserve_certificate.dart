import 'package:flutter/foundation.dart';

/// Een door de organisatie uitgegeven certificaat (`CertificateResponse`).
/// Een ingetrokken certificaat blijft in de lijst staan — met die status —
/// want intrekking is een feit in het dossier, geen verdwijning.
@immutable
class OciServeCertificate {
  const OciServeCertificate({
    required this.id,
    required this.title,
    required this.certificateNumber,
    required this.status,
    required this.issuedAt,
    this.description = '',
    this.revokedAt,
    this.revocationReason,
  });

  final String id;
  final String title;
  final String description;
  final String certificateNumber;

  /// `issued` of `revoked`.
  final String status;
  final DateTime issuedAt;
  final DateTime? revokedAt;
  final String? revocationReason;

  bool get isRevoked => status == 'revoked';

  factory OciServeCertificate.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    final title = (json['title'] as String? ?? '').trim();
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('incomplete certificate');
    }
    return OciServeCertificate(
      id: id,
      title: title,
      description: (json['description'] as String? ?? '').trim(),
      certificateNumber: (json['certificate_number'] as String? ?? '').trim(),
      status: (json['status'] as String? ?? '').trim(),
      issuedAt:
          DateTime.tryParse(json['issued_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      revokedAt: DateTime.tryParse(json['revoked_at'] as String? ?? ''),
      revocationReason: (json['revocation_reason'] as String?)?.trim(),
    );
  }
}
