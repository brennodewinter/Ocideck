import 'package:flutter/foundation.dart';

/// Een soort bewijs die de organisatie heeft gepubliceerd (bijvoorbeeld een
/// BHV-certificaat). De cursist kiest er een bij het aanleveren.
@immutable
class OciServeEvidenceType {
  const OciServeEvidenceType({
    required this.id,
    required this.slug,
    required this.title,
  });

  final String id;
  final String slug;
  final String title;

  /// Leest een bewijssoort. Alleen een gepubliceerde soort mag worden
  /// aangeleverd; concepten en gearchiveerde soorten geeft deze lezer niet
  /// terug (`null`).
  static OciServeEvidenceType? fromJson(Map<String, Object?> json) {
    final status = (json['status'] as String? ?? '').trim();
    if (status != 'published') return null;
    final id = (json['id'] as String? ?? '').trim();
    final title = (json['title'] as String? ?? '').trim();
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('incomplete evidence type');
    }
    return OciServeEvidenceType(
      id: id,
      slug: (json['slug'] as String? ?? '').trim(),
      title: title,
    );
  }
}

/// Een gepubliceerde versie van een bewijssoort
/// (`EvidenceTypeVersionResponse`). De portefeuille-selectie koppelt een
/// bewijsstuk aan zo'n versie; de nieuwste gepubliceerde versie is de enige
/// die de server accepteert.
@immutable
class OciServeEvidenceTypeVersion {
  const OciServeEvidenceTypeVersion({required this.id, required this.version});

  final String id;
  final int version;

  factory OciServeEvidenceTypeVersion.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('incomplete type version');
    return OciServeEvidenceTypeVersion(
      id: id,
      version: (json['version'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Waar een bewijsstuk staat in de beoordeling. Een onbekende waarde is een
/// contractbreuk, geen standaardwaarde.
enum OciServeEvidenceContentStatus {
  ingediend,
  inBehandeling,
  geaccepteerd,
  aanvullingGevraagd,
  afgewezen,
  ingetrokken,
  verlopen;

  static OciServeEvidenceContentStatus parse(String value) => switch (value) {
    'ingediend' => ingediend,
    'in_behandeling' => inBehandeling,
    'geaccepteerd' => geaccepteerd,
    'aanvulling_gevraagd' => aanvullingGevraagd,
    'afgewezen' => afgewezen,
    'ingetrokken' => ingetrokken,
    'verlopen' => verlopen,
    _ => throw FormatException('unknown evidence status: $value'),
  };
}

/// Een aangeleverd bewijsstuk zoals een beoordelaar het ziet. Het ontstaat pas
/// als de cursist het bestand koppelt aan een bewijssoort; een losse upload is
/// nog geen bewijsstuk en komt dus niet in een beoordelingswachtrij.
@immutable
class OciServeEvidenceItem {
  const OciServeEvidenceItem({
    required this.id,
    required this.evidenceTypeId,
    required this.status,
    required this.createdAt,
    this.uploadId,
    this.declaredValidUntil,
    this.reviewNote,
  });

  final String id;
  final String evidenceTypeId;
  final OciServeEvidenceContentStatus status;
  final DateTime createdAt;
  final String? uploadId;
  final DateTime? declaredValidUntil;
  final String? reviewNote;

  factory OciServeEvidenceItem.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    final typeId = (json['evidence_type_id'] as String? ?? '').trim();
    final created = DateTime.tryParse(json['created_at'] as String? ?? '');
    if (id.isEmpty || typeId.isEmpty || created == null) {
      throw const FormatException('incomplete evidence item');
    }
    final validUntil = json['declared_valid_until'];
    return OciServeEvidenceItem(
      id: id,
      evidenceTypeId: typeId,
      status: OciServeEvidenceContentStatus.parse(
        (json['content_status'] as String? ?? '').trim(),
      ),
      createdAt: created.toUtc(),
      uploadId: (json['upload_id'] as String?)?.trim(),
      declaredValidUntil: validUntil == null
          ? null
          : DateTime.tryParse(validUntil as String? ?? '')?.toUtc(),
      reviewNote: (json['review_note'] as String?)?.trim(),
    );
  }
}
