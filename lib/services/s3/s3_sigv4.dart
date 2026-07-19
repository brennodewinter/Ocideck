import 'dart:convert';

import 'package:crypto/crypto.dart';

/// AWS Signature Version 4 voor S3 en S3-compatible endpoints (MinIO, Ceph,
/// Wasabi, Scaleway, Hetzner).
///
/// Bewust met de hand geschreven in plaats van via een AWS-SDK. Twee redenen.
/// Een SDK brengt zijn eigen HTTP-stack mee en die zou langs [NetGuard] heen
/// verbinden — precies de socket-pinning die elke andere netwerkbron in deze app
/// wél toepast. En het algoritme is klein genoeg om volledig te toetsen: de
/// testvectoren van AWS zelf staan in `test/s3_sigv4_test.dart`.
///
/// Alleen ondertekenen, geen netwerk: deze klasse rekent een set headers uit en
/// laat het verzenden aan [S3Service]. Daardoor is hij zuiver testbaar zonder
/// server.
class S3Signer {
  final String accessKeyId;
  final String secretAccessKey;
  final String region;

  const S3Signer({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.region,
  });

  /// De enige service die we ondertekenen. Staat als constante zodat de
  /// scope-string niet per aanroep gespeld hoeft te worden.
  static const String service = 's3';

  static const String algorithm = 'AWS4-HMAC-SHA256';

  /// Wat je in `x-amz-content-sha256` zet als de body niet vooraf te hashen is.
  /// Wij gebruiken hem niet — elke upload zit al volledig in het geheugen omdat
  /// de groottelimiet dat afdwingt — maar S3-endpoints kennen hem en een
  /// toekomstige streaming-upload heeft hem nodig.
  static const String unsignedPayload = 'UNSIGNED-PAYLOAD';

  /// Rekent de headers uit die aan het verzoek toegevoegd moeten worden:
  /// `x-amz-date`, `x-amz-content-sha256` en `Authorization`.
  ///
  /// [headers] moet minstens `host` bevatten — dat is de header waarmee de
  /// handtekening aan déze server vastzit. [payloadSha256] is de hex-hash van de
  /// body ([hashPayload]), of [unsignedPayload].
  ///
  /// [now] wordt verplicht meegegeven in plaats van intern opgehaald, zodat de
  /// test tegen een vaste klok kan draaien.
  Map<String, String> sign({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String payloadSha256,
    required DateTime now,
  }) {
    final utc = now.toUtc();
    final amzDate = _amzDate(utc);
    final dateStamp = amzDate.substring(0, 8);

    // De datum- en payload-header horen ondertekend te worden, dus ze gaan de
    // canonieke set in vóórdat we die vastleggen.
    final signed = <String, String>{
      ...headers,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadSha256,
    };

    final canonicalHeaders = _canonicalHeaders(signed);
    final signedHeaders = _signedHeaders(signed);

    final canonicalRequest = [
      method.toUpperCase(),
      canonicalUri(uri),
      canonicalQuery(uri),
      canonicalHeaders,
      signedHeaders,
      payloadSha256,
    ].join('\n');

    final scope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      algorithm,
      amzDate,
      scope,
      _hex(sha256.convert(utf8.encode(canonicalRequest)).bytes),
    ].join('\n');

    final signature = _hex(_hmac(_signingKey(dateStamp), stringToSign));

    return {
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadSha256,
      'Authorization':
          '$algorithm Credential=$accessKeyId/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    };
  }

  /// Hex-sha256 van een body, zoals `x-amz-content-sha256` hem wil.
  static String hashPayload(List<int> bytes) =>
      _hex(sha256.convert(bytes).bytes);

  /// Hex-sha256 van een lege body — de waarde voor elke GET, HEAD en DELETE.
  static final String emptyPayloadHash = hashPayload(const <int>[]);

  /// Het pad, per segment één keer gecodeerd.
  ///
  /// S3 wijkt hier af van de andere AWS-diensten: die coderen het pad tweemaal,
  /// S3 eenmaal. Ook normaliseren we niet — een sleutel mag letterlijk `a//b`
  /// of `a/./b` heten en dan is dát het pad dat ondertekend moet worden.
  static String canonicalUri(Uri uri) {
    if (uri.path.isEmpty || uri.path == '/') return '/';
    // `pathSegments` decodeert; we coderen elk segment opnieuw met de strikte
    // regels van AWS, die ruimer escapen dan `Uri.encodeComponent`.
    final segments = uri.path
        .split('/')
        .map((s) => encodeRfc3986(Uri.decodeComponent(s)));
    return segments.join('/');
  }

  /// Querystring met de parameters op naam gesorteerd en beide kanten strikt
  /// gecodeerd. Een parameter zonder waarde houdt zijn `=`.
  static String canonicalQuery(Uri uri) {
    if (uri.queryParameters.isEmpty) return '';
    final pairs = <MapEntry<String, String>>[];
    uri.queryParametersAll.forEach((key, values) {
      for (final v in values) {
        pairs.add(MapEntry(encodeRfc3986(key), encodeRfc3986(v)));
      }
    });
    // Sorteren op gecodeerde naam, en bij gelijke naam op waarde — dat is de
    // volgorde die AWS voorschrijft.
    pairs.sort((a, b) {
      final byKey = a.key.compareTo(b.key);
      return byKey != 0 ? byKey : a.value.compareTo(b.value);
    });
    return pairs.map((e) => '${e.key}=${e.value}').join('&');
  }

  /// Percent-codering volgens RFC 3986 zoals AWS die eist: alleen
  /// `A-Z a-z 0-9 - _ . ~` blijven staan, de rest wordt `%XX` in hoofdletters.
  ///
  /// Niet `Uri.encodeComponent`: die laat `!`, `*`, `'`, `(` en `)` ongemoeid,
  /// en een sleutel met een apostrof zou daardoor een handtekening opleveren die
  /// de server verwerpt.
  static String encodeRfc3986(String input) {
    final out = StringBuffer();
    for (final byte in utf8.encode(input)) {
      if (_isUnreserved(byte)) {
        out.writeCharCode(byte);
      } else {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  static bool _isUnreserved(int b) {
    const dash = 0x2D, dot = 0x2E, underscore = 0x5F, tilde = 0x7E;
    return (b >= 0x41 && b <= 0x5A) || // A-Z
        (b >= 0x61 && b <= 0x7A) || // a-z
        (b >= 0x30 && b <= 0x39) || // 0-9
        b == dash ||
        b == dot ||
        b == underscore ||
        b == tilde;
  }

  /// `naam:waarde\n` per header, namen in kleine letters en gesorteerd, waarden
  /// getrimd met opeenvolgende spaties samengetrokken.
  static String _canonicalHeaders(Map<String, String> headers) {
    final normalized = <String, String>{};
    headers.forEach((k, v) {
      normalized[k.toLowerCase().trim()] = v.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
    });
    final names = normalized.keys.toList()..sort();
    return names.map((n) => '$n:${normalized[n]}\n').join();
  }

  static String _signedHeaders(Map<String, String> headers) {
    final names = headers.keys.map((k) => k.toLowerCase().trim()).toList()
      ..sort();
    return names.join(';');
  }

  /// De afgeleide ondertekensleutel: vier geketende HMAC's, zodat de echte
  /// secret nooit rechtstreeks het verzoek ondertekent en de sleutel per dag,
  /// regio en dienst verschilt.
  List<int> _signingKey(String dateStamp) {
    final kDate = _hmac(utf8.encode('AWS4$secretAccessKey'), dateStamp);
    final kRegion = _hmac(kDate, region);
    final kService = _hmac(kRegion, service);
    return _hmac(kService, 'aws4_request');
  }

  static List<int> _hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// `20130524T000000Z` — de basisvorm van ISO 8601, zonder scheidingstekens.
  static String _amzDate(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
        '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}'
        '${two(utc.second)}Z';
  }
}
