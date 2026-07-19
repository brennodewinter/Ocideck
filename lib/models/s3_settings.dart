import 'package:path/path.dart' as p;

import '../services/s3/s3_sigv4.dart';

/// Hoe de bucketnaam in de URL terechtkomt.
enum S3AddressingStyle {
  /// `https://bucket.s3.eu-central-1.amazonaws.com/sleutel` — wat AWS zelf wil
  /// en waar hun TLS-certificaten op zijn uitgegeven.
  virtualHosted,

  /// `https://minio.intern/bucket/sleutel` — wat de meeste zelf gehoste
  /// endpoints (MinIO, Ceph) willen, omdat een wildcard-certificaat per bucket
  /// daar zelden bestaat.
  path,
}

/// Configuratie van één S3-bron. Bewust géén secret access key: die staat
/// versleuteld in de keychain (zie `SecretStore`), gekeyd op [endpoint] +
/// [accessKeyId]. Deze waarden mogen wél in het prefs-domein.
///
/// Het model is bewust breder dan alleen AWS. Elke S3-compatible dienst is een
/// endpoint plus een regio, en juist de zelf gehoste (MinIO) en Europese
/// aanbieders zijn voor deze app het interessante geval — dus is het endpoint
/// een gewoon invulveld en geen keuzelijst met AWS-regio's.
class S3Bucket {
  /// Endpoint-origin zonder pad en zonder bucketnaam, bv.
  /// `https://s3.eu-central-1.amazonaws.com` of `https://minio.intern:9000`.
  final String endpoint;

  /// Regio zoals hij in de handtekening meegaat. S3-compatible diensten die
  /// geen regio's kennen accepteren doorgaans `us-east-1`.
  final String region;

  final String bucket;

  /// De sleutel-id; de bijbehorende secret zit in de keychain.
  final String accessKeyId;

  /// Prefix binnen de bucket waar de bladeraar opent en waar decks landen.
  /// Leeg = de bucket zelf. In S3-termen is dit gewoon een sleutelprefix; dat
  /// het zich als map gedraagt komt doordat we met een delimiter listen.
  final String rootPath;

  final S3AddressingStyle addressingStyle;

  /// De gebruiker heeft bevestigd dat dit een vertrouwde interne server is; pas
  /// dán mag een privé/LAN-host de SSRF-blokkade passeren. Zelfde afspraak als
  /// bij WebDAV, want een MinIO op het eigen netwerk is het normale geval.
  final bool trustedInternal;

  const S3Bucket({
    required this.endpoint,
    required this.bucket,
    this.region = 'us-east-1',
    this.accessKeyId = '',
    this.rootPath = '',
    this.addressingStyle = S3AddressingStyle.virtualHosted,
    this.trustedInternal = false,
  });

  bool get isConfigured =>
      endpoint.trim().isNotEmpty &&
      bucket.trim().isNotEmpty &&
      accessKeyId.trim().isNotEmpty;

  /// De host waarmee daadwerkelijk verbonden wordt — dus zónder de bucketnaam,
  /// ook bij virtual-hosted adressering. Dit is de naam die [NetGuard] resolvet
  /// en waarop de socket gepind wordt.
  String get endpointHost => Uri.tryParse(endpoint.trim())?.host ?? '';

  /// De host zoals hij in de `Host`-header en dus in de handtekening hoort.
  /// Bij virtual-hosted zit de bucket erin verwerkt; die naam moet ook het
  /// TLS-certificaat dekken.
  String get signingHost => switch (addressingStyle) {
    S3AddressingStyle.virtualHosted => '${bucket.trim()}.$endpointHost',
    S3AddressingStyle.path => endpointHost,
  };

  /// Origin (scheme + host + poort) van [endpoint], zonder pad.
  Uri? get origin {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }

  /// Normaliseer een door de UI gegeven prefix tot een vorm zonder leidende of
  /// afsluitende slash. Geen `..` toegestaan.
  static String normalizeRoot(String raw) {
    var r = raw.trim().replaceAll(RegExp(r'/+'), '/');
    while (r.startsWith('/')) {
      r = r.substring(1);
    }
    while (r.endsWith('/')) {
      r = r.substring(0, r.length - 1);
    }
    return r;
  }

  /// De volledige sleutel voor een pad dat relatief is aan [rootPath], of
  /// `null` wanneer het pad met `..` buiten de wortel zou breken.
  ///
  /// Geeft een sleutel zonder leidende slash terug — dat is hoe S3 sleutels
  /// benoemt, en het scheelt een klasse van fouten waarbij `/a` en `a` twee
  /// verschillende objecten worden.
  String? keyFor(String relativePath) {
    final root = normalizeRoot(rootPath);
    final joined = p.posix.normalize(
      root.isEmpty ? relativePath.trim() : '$root/${relativePath.trim()}',
    );
    final scoped = (joined == '.' || joined == '/') ? '' : joined;
    if (scoped.startsWith('..')) return null; // traversal buiten de bucket
    if (root.isNotEmpty && scoped != root && !p.posix.isWithin(root, scoped)) {
      return null; // traversal buiten de geconfigureerde prefix
    }
    return scoped.startsWith('/') ? scoped.substring(1) : scoped;
  }

  /// Bouw de absolute URL voor een sleutel.
  ///
  /// Het pad wordt hier al met de strikte AWS-regels gecodeerd
  /// ([S3Signer.encodeRfc3986]) in plaats van aan `Uri` overgelaten. Dat is
  /// wezenlijk: S3 vergelijkt onze handtekening met een canonieke vorm die uit
  /// het *ontvangen* pad wordt afgeleid, dus wat er over de lijn gaat moet
  /// byte-voor-byte gelijk zijn aan wat we ondertekenden. `Uri` laat onder meer
  /// `!*'()` ongemoeid en zou dat verband breken — met een 403 tot gevolg die
  /// pas bij een bestandsnaam met een haakje opduikt.
  Uri? uriForKey(String key, {Map<String, String> query = const {}}) {
    final base = origin;
    if (base == null) return null;
    final segments = <String>[
      if (addressingStyle == S3AddressingStyle.path) bucket.trim(),
      ...key.split('/'),
    ].where((s) => s.isNotEmpty).map(S3Signer.encodeRfc3986);
    final path = segments.isEmpty ? '/' : '/${segments.join('/')}';
    final queryString = buildQuery(query);
    return Uri.parse(
      '${base.scheme}://${_authorityFor(base)}$path'
      '${queryString.isEmpty ? '' : '?$queryString'}',
    );
  }

  /// Querystring met beide kanten strikt gecodeerd, om dezelfde reden als het
  /// pad in [uriForKey]. Let op `+`: die komt in een continuation-token voor en
  /// zou door de form-codering van `Uri` als spatie gelezen worden.
  static String buildQuery(Map<String, String> query) => query.entries
      .map(
        (e) =>
            '${S3Signer.encodeRfc3986(e.key)}=${S3Signer.encodeRfc3986(e.value)}',
      )
      .join('&');

  /// De autoriteit zoals hij in de URL hoort — inclusief bucket bij
  /// virtual-hosted, en met de poort als het endpoint er een noemt.
  String _authorityFor(Uri base) {
    final host = switch (addressingStyle) {
      S3AddressingStyle.virtualHosted => '${bucket.trim()}.${base.host}',
      S3AddressingStyle.path => base.host,
    };
    return base.hasPort ? '$host:${base.port}' : host;
  }

  S3Bucket copyWith({
    String? endpoint,
    String? region,
    String? bucket,
    String? accessKeyId,
    String? rootPath,
    S3AddressingStyle? addressingStyle,
    bool? trustedInternal,
  }) => S3Bucket(
    endpoint: endpoint ?? this.endpoint,
    region: region ?? this.region,
    bucket: bucket ?? this.bucket,
    accessKeyId: accessKeyId ?? this.accessKeyId,
    rootPath: rootPath ?? this.rootPath,
    addressingStyle: addressingStyle ?? this.addressingStyle,
    trustedInternal: trustedInternal ?? this.trustedInternal,
  );

  Map<String, Object?> toJson() => {
    'endpoint': endpoint,
    'region': region,
    'bucket': bucket,
    'accessKeyId': accessKeyId,
    'rootPath': rootPath,
    'addressingStyle': addressingStyle.name,
    'trustedInternal': trustedInternal,
  };

  factory S3Bucket.fromJson(Map<String, Object?> json) => S3Bucket(
    endpoint: (json['endpoint'] as String?) ?? '',
    region: (json['region'] as String?) ?? 'us-east-1',
    bucket: (json['bucket'] as String?) ?? '',
    accessKeyId: (json['accessKeyId'] as String?) ?? '',
    rootPath: (json['rootPath'] as String?) ?? '',
    // Een onbekende of ontbrekende waarde valt terug op virtual-hosted in
    // plaats van de bron onbruikbaar te maken.
    addressingStyle: S3AddressingStyle.values.firstWhere(
      (s) => s.name == json['addressingStyle'],
      orElse: () => S3AddressingStyle.virtualHosted,
    ),
    trustedInternal: (json['trustedInternal'] as bool?) ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is S3Bucket &&
      other.endpoint == endpoint &&
      other.region == region &&
      other.bucket == bucket &&
      other.accessKeyId == accessKeyId &&
      other.rootPath == rootPath &&
      other.addressingStyle == addressingStyle &&
      other.trustedInternal == trustedInternal;

  @override
  int get hashCode => Object.hash(
    endpoint,
    region,
    bucket,
    accessKeyId,
    rootPath,
    addressingStyle,
    trustedInternal,
  );
}
