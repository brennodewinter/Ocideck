import 'package:flutter/foundation.dart';

/// Eén gevonden credential zoals OciDeck hem aanlevert aan de import-sessie
/// (`PortfolioImportCreateRequest.items[]`). De server haalt zelf niets op bij
/// een badgeplatform (#2423) — OciDeck levert wat de cursist heeft gevonden.
@immutable
class PortfolioImportItemInput {
  const PortfolioImportItemInput({
    required this.issuerId,
    required this.title,
    this.credentialId,
    this.issuedAt,
    this.validUntil,
    this.rawCredential,
  });

  final String issuerId;
  final String title;
  final String? credentialId;
  final DateTime? issuedAt;
  final DateTime? validUntil;
  final Map<String, Object?>? rawCredential;

  Map<String, Object?> toJson() => {
    'issuer_id': issuerId,
    if (credentialId != null && credentialId!.isNotEmpty)
      'credential_id': credentialId,
    'title': title,
    if (issuedAt != null) 'issued_at': issuedAt!.toUtc().toIso8601String(),
    if (validUntil != null)
      'valid_until': validUntil!.toUtc().toIso8601String(),
    if (rawCredential != null) 'raw_credential': rawCredential,
  };
}

/// Eén item in een lopende import-sessie (`PortfolioImportItemResponse`).
@immutable
class OciServePortfolioImportItem {
  const OciServePortfolioImportItem({
    required this.id,
    required this.title,
    this.issuerId = '',
    this.credentialId = '',
    this.issuedAt,
    this.validUntil,
    this.selected = false,
  });

  final String id;
  final String title;
  final String issuerId;
  final String credentialId;
  final DateTime? issuedAt;
  final DateTime? validUntil;
  final bool selected;

  factory OciServePortfolioImportItem.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('incomplete import item');
    return OciServePortfolioImportItem(
      id: id,
      title: (json['title'] as String? ?? '').trim(),
      issuerId: (json['issuer_id'] as String? ?? '').trim(),
      credentialId: (json['credential_id'] as String? ?? '').trim(),
      issuedAt: DateTime.tryParse(json['issued_at'] as String? ?? ''),
      validUntil: DateTime.tryParse(json['valid_until'] as String? ?? ''),
      selected: json['selected'] == true,
    );
  }
}

/// Een import-sessie (`PortfolioImportResponse`): de gevonden items in het
/// eigen beeld van de cursist, voordat er iets gedeeld is.
@immutable
class OciServePortfolioImport {
  const OciServePortfolioImport({
    required this.importId,
    required this.status,
    required this.items,
  });

  final String importId;
  final String status;
  final List<OciServePortfolioImportItem> items;

  factory OciServePortfolioImport.fromJson(Map<String, Object?> json) {
    final importId = (json['import_id'] as String? ?? '').trim();
    if (importId.isEmpty) {
      throw const FormatException('incomplete portfolio import');
    }
    final raw = json['items'];
    return OciServePortfolioImport(
      importId: importId,
      status: (json['status'] as String? ?? '').trim(),
      items: List.unmodifiable([
        if (raw is List)
          for (final item in raw)
            OciServePortfolioImportItem.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
      ]),
    );
  }
}

/// Vertaalt een gedecodeerd credential-document naar import-items. Verdraagt
/// drie vormen: één credential-object, een lijst van objecten, of een object
/// met een `credentials`- of `items`-lijst (zoals een gedownloade
/// Open Badges-export). Een object zonder herkenbare issuer en titel levert
/// niets op — liever niets dan een verzonnen veld.
List<PortfolioImportItemInput> portfolioItemsFromJson(Object? decoded) {
  final raw = <Object?>[];
  if (decoded is List) {
    raw.addAll(decoded);
  } else if (decoded is Map) {
    final nested = decoded['credentials'] ?? decoded['items'];
    if (nested is List) {
      raw.addAll(nested);
    } else {
      raw.add(decoded);
    }
  }
  return [
    for (final item in raw)
      if (item is Map) ?_credentialToItem(Map<String, Object?>.from(item)),
  ];
}

/// Leest de contractvelden uit een Open Badges 2.x- of 3.0-achtig object.
/// De veldnamen verschillen per versie; elk bekende alternatief wordt geprobeerd.
PortfolioImportItemInput? _credentialToItem(Map<String, Object?> credential) {
  String nested(List<String> path) {
    Object? node = credential;
    for (final key in path) {
      if (node is! Map) return '';
      node = node[key];
    }
    return node is String ? node.trim() : '';
  }

  final issuer = credential['issuer'];
  final issuerId = switch (issuer) {
    Map<Object?, Object?> m =>
      (m['id'] as String? ?? m['url'] as String? ?? '').trim(),
    String s => s.trim(),
    _ => '',
  };
  var title = nested(['credentialSubject', 'achievement', 'name']);
  if (title.isEmpty) title = nested(['badge', 'name']);
  if (title.isEmpty) title = (credential['name'] as String? ?? '').trim();
  if (issuerId.isEmpty || title.isEmpty) return null;
  DateTime? date(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc();
  }

  final issued =
      date(nested(['validFrom'])) ??
      date(nested(['issuanceDate'])) ??
      date(nested(['issuedOn'])) ??
      date(nested(['issued_at']));
  final validUntil =
      date(nested(['validUntil'])) ??
      date(nested(['expirationDate'])) ??
      date(nested(['expires']));
  final credentialId = (credential['id'] as String? ?? '').trim();
  return PortfolioImportItemInput(
    issuerId: issuerId,
    title: title,
    credentialId: credentialId.isEmpty ? null : credentialId,
    issuedAt: issued,
    validUntil: validUntil,
    rawCredential: credential,
  );
}
