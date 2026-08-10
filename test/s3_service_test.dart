import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/s3_settings.dart';
import 'package:ocideck/services/s3/s3_service.dart';
import 'package:ocideck/services/s3/s3_sigv4.dart';

const _accessKey = 'AKIAIOSFODNN7EXAMPLE';
const _secret = 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY';
final _clock = DateTime.utc(2013, 5, 24);

/// Eén binnengekomen verzoek op de nepserver.
class _Req {
  _Req({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.body,
    required this.signatureValid,
    this.ifMatch,
    this.ifNoneMatch,
  });

  final String method;

  /// Het pad zoals het over de lijn kwam — dus nog percent-gecodeerd.
  final String path;
  final Map<String, String> query;
  final String? authorization;
  final Uint8List body;

  /// Of de handtekening die de client meestuurde klopt bij het verzoek zoals
  /// de server het ontving. Dit is de kern van de test: als het pad of de query
  /// onderweg anders gecodeerd raakt dan wat ondertekend is, klopt hij niet —
  /// en dan zou een echte S3 met 403 antwoorden.
  final bool signatureValid;

  /// De voorwaarden waaronder de client wilde schrijven; het bewijs dat de
  /// concurrency-guard daadwerkelijk over de lijn ging.
  final String? ifMatch;
  final String? ifNoneMatch;
}

/// Rekent de handtekening opnieuw uit over het verzoek zoals het binnenkwam en
/// vergelijkt hem met wat de client stuurde — precies wat een echte S3 doet.
bool _verifySignature(HttpRequest req) {
  final auth = req.headers.value(HttpHeaders.authorizationHeader);
  if (auth == null) return false;
  final signedHeadersMatch = RegExp(r'SignedHeaders=([^,]+)').firstMatch(auth);
  final claimed = RegExp(r'Signature=([0-9a-f]+)').firstMatch(auth);
  final amzDate = req.headers.value('x-amz-date');
  final payloadHash = req.headers.value('x-amz-content-sha256');
  if (signedHeadersMatch == null ||
      claimed == null ||
      amzDate == null ||
      payloadHash == null) {
    return false;
  }
  // De datum- en payload-header voegt [S3Signer.sign] zelf toe; de overige
  // ondertekende headers halen we uit het verzoek.
  final names = signedHeadersMatch
      .group(1)!
      .split(';')
      .where((n) => n != 'x-amz-date' && n != 'x-amz-content-sha256');
  final headers = <String, String>{
    for (final n in names) n: req.headers.value(n) ?? '',
  };
  const signer = S3Signer(
    accessKeyId: _accessKey,
    secretAccessKey: _secret,
    region: 'us-east-1',
  );
  final recomputed = signer.sign(
    method: req.method,
    uri: req.requestedUri,
    headers: headers,
    payloadSha256: payloadHash,
    now: DateTime.utc(
      int.parse(amzDate.substring(0, 4)),
      int.parse(amzDate.substring(4, 6)),
      int.parse(amzDate.substring(6, 8)),
      int.parse(amzDate.substring(9, 11)),
      int.parse(amzDate.substring(11, 13)),
      int.parse(amzDate.substring(13, 15)),
    ),
  );
  return recomputed['Authorization']!.split('Signature=').last ==
      claimed.group(1);
}

/// Een wegwerp-S3 op loopback. Omdat [S3Service] zijn socket pint op het
/// geresolvede adres en we de bron als `trustedInternal` markeren, laat NetGuard
/// het loopback-adres door en landt het echte verzoek hier — zodat
/// list/download/upload/probe end-to-end draaien zonder een echte bucket.
class _FakeS3 {
  _FakeS3._(this._server, this._responder);

  final HttpServer _server;
  final Future<void> Function(HttpRequest req) _responder;
  final List<_Req> requests = [];

  int get port => _server.port;

  static Future<_FakeS3> start(
    Future<void> Function(HttpRequest req) responder,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeS3._(server, responder);
    server.listen((req) async {
      try {
        final builder = BytesBuilder();
        await for (final chunk in req) {
          builder.add(chunk);
        }
        fake.requests.add(
          _Req(
            method: req.method,
            path: req.uri.path,
            query: req.uri.queryParameters,
            authorization: req.headers.value(HttpHeaders.authorizationHeader),
            body: builder.takeBytes(),
            signatureValid: _verifySignature(req),
            ifMatch: req.headers.value('if-match'),
            ifNoneMatch: req.headers.value('if-none-match'),
          ),
        );
        await fake._responder(req);
      } finally {
        await req.response.close();
      }
    });
    return fake;
  }

  Future<void> stop() => _server.close(force: true);
}

/// Een path-style bron op loopback. Path-style omdat virtual-hosted een
/// bucketnaam vóór de host plakt en `bucket.127.0.0.1` nergens naar resolvet —
/// wat meteen het gangbare geval is voor een zelf gehoste MinIO.
S3Bucket _bucketOn(int port, {String rootPath = ''}) => S3Bucket(
  endpoint: 'http://127.0.0.1:$port',
  region: 'us-east-1',
  bucket: 'decks',
  accessKeyId: _accessKey,
  rootPath: rootPath,
  addressingStyle: S3AddressingStyle.path,
  trustedInternal: true,
);

S3Service _serviceOn(int port, {String rootPath = ''}) => S3Service(
  bucket: _bucketOn(port, rootPath: rootPath),
  secretAccessKey: _secret,
  clock: () => _clock,
);

String _listXml({
  required List<String> keys,
  List<String> prefixes = const [],
  String? nextToken,
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
    '<Name>decks</Name>'
    '<IsTruncated>${nextToken != null}</IsTruncated>'
    '${nextToken != null ? '<NextContinuationToken>$nextToken</NextContinuationToken>' : ''}'
    '${prefixes.map((p) => '<CommonPrefixes><Prefix>$p</Prefix></CommonPrefixes>').join()}'
    '${keys.map((k) => '<Contents><Key>$k</Key><Size>12</Size><ETag>&quot;abc&quot;</ETag></Contents>').join()}'
    '</ListBucketResult>';

void main() {
  group('probe', () {
    test('vraagt een listing van nul sleutels en tekent geldig', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('application', 'xml');
        req.response.write(_listXml(keys: const []));
      });
      addTearDown(fake.stop);

      await _serviceOn(fake.port).probe();

      expect(fake.requests, hasLength(1));
      final r = fake.requests.single;
      expect(r.method, 'GET');
      expect(r.path, '/decks');
      expect(r.query['list-type'], '2');
      expect(r.query['max-keys'], '0');
      expect(r.authorization, startsWith('AWS4-HMAC-SHA256 Credential='));
      expect(r.signatureValid, isTrue);
    });

    test('een 403 komt terug als een auth-fout', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 403;
      });
      addTearDown(fake.stop);

      await expectLater(
        _serviceOn(fake.port).probe(),
        throwsA(isA<S3Exception>().having((e) => e.kind, 'kind', S3Error.auth)),
      );
    });
  });

  group('list', () {
    test('prefixen worden mappen, objecten worden bestanden', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
        req.response.write(
          _listXml(
            keys: const ['een.md', 'twee.ocideck'],
            prefixes: const ['submap/'],
          ),
        );
      });
      addTearDown(fake.stop);

      final entries = await _serviceOn(fake.port).list('');

      expect(entries.map((e) => e.name), ['submap', 'een.md', 'twee.ocideck']);
      expect(entries.first.isCollection, isTrue);
      expect(entries[1].isCollection, isFalse);
      expect(entries[1].isMarkdown, isTrue);
      expect(entries[2].isOcideck, isTrue);
      expect(entries[1].size, 12);
      expect(fake.requests.single.query['delimiter'], '/');
      expect(fake.requests.single.signatureValid, isTrue);
    });

    test('de wortelprefix wordt van de sleutels afgehaald', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
        req.response.write(
          _listXml(
            keys: const ['klant-a/decks/een.md'],
            prefixes: const ['klant-a/decks/oud/'],
          ),
        );
      });
      addTearDown(fake.stop);

      final entries = await _serviceOn(
        fake.port,
        rootPath: 'klant-a/decks',
      ).list('');

      expect(entries.map((e) => e.relativePath), ['oud', 'een.md']);
      expect(fake.requests.single.query['prefix'], 'klant-a/decks/');
    });

    test('haalt volgende paginas op zolang er een token is', () async {
      // Het token bevat een `+`, want een echt continuation-token is base64.
      // Als dat als spatie over de lijn zou gaan, klopt de handtekening niet.
      const token = 'abc+def/ghi=';
      var call = 0;
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
        req.response.write(
          call++ == 0
              ? _listXml(keys: const ['een.md'], nextToken: token)
              : _listXml(keys: const ['twee.md']),
        );
      });
      addTearDown(fake.stop);

      final entries = await _serviceOn(fake.port).list('');

      expect(entries.map((e) => e.name), ['een.md', 'twee.md']);
      expect(fake.requests, hasLength(2));
      expect(fake.requests[1].query['continuation-token'], token);
      expect(fake.requests.every((r) => r.signatureValid), isTrue);
    });
  });

  group('download', () {
    test('geeft bytes en etag terug', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        req.response.add(utf8.encode('# Hallo'));
      });
      addTearDown(fake.stop);

      final file = await _serviceOn(fake.port).download('map/een.md');

      expect(utf8.decode(file.bytes), '# Hallo');
      expect(file.etag, '"v1"');
      expect(fake.requests.single.path, '/decks/map/een.md');
      expect(fake.requests.single.signatureValid, isTrue);
    });

    test('een sleutel met lastige tekens blijft ondertekend kloppen', () async {
      // Haakjes en een spatie: `Uri.encodeComponent` laat haakjes staan, de
      // AWS-regels niet. Gaat dit mis, dan wijkt het ondertekende pad af van
      // het verstuurde pad en weigert een echte S3 met 403.
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
        req.response.add(utf8.encode('x'));
      });
      addTearDown(fake.stop);

      await _serviceOn(fake.port).download("map/notulen (def) 'v2'.md");

      final r = fake.requests.single;
      expect(r.path, '/decks/map/notulen%20%28def%29%20%27v2%27.md');
      expect(r.signatureValid, isTrue);
    });

    test('een 404 komt terug als notFound', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 404;
      });
      addTearDown(fake.stop);

      await expectLater(
        _serviceOn(fake.port).download('weg.md'),
        throwsA(
          isA<S3Exception>().having((e) => e.kind, 'kind', S3Error.notFound),
        ),
      );
    });
  });

  group('upload', () {
    test('stuurt de bytes en geeft de nieuwe etag terug', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.etagHeader, '"v2"');
      });
      addTearDown(fake.stop);

      final etag = await _serviceOn(
        fake.port,
      ).upload('map/een.md', utf8.encode('inhoud'));

      expect(etag, '"v2"');
      final r = fake.requests.single;
      expect(r.method, 'PUT');
      expect(utf8.decode(r.body), 'inhoud');
      expect(r.signatureValid, isTrue);
    });

    test('If-Match gaat mee over de lijn en wordt ondertekend', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
      });
      addTearDown(fake.stop);

      await _serviceOn(
        fake.port,
      ).upload('een.md', utf8.encode('x'), ifMatch: '"v1"');

      expect(fake.requests.single.ifMatch, '"v1"');
      expect(fake.requests.single.signatureValid, isTrue);
      expect(fake.requests.single.authorization, contains('if-match'));
    });

    test('onlyIfAbsent stuurt If-None-Match: *', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 200;
      });
      addTearDown(fake.stop);

      await _serviceOn(
        fake.port,
      ).upload('een.md', utf8.encode('x'), onlyIfAbsent: true);

      expect(fake.requests.single.ifNoneMatch, '*');
    });

    test('een 412 wordt een conflict, geen serverfout', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 412;
      });
      addTearDown(fake.stop);

      await expectLater(
        _serviceOn(fake.port).upload('een.md', const [1], ifMatch: '"v1"'),
        throwsA(
          isA<S3ConflictException>().having(
            (e) => e.expectedEtag,
            'expectedEtag',
            '"v1"',
          ),
        ),
      );
    });

    test('een 501 op een voorwaardelijke PUT is een eigen soort', () async {
      // Een endpoint dat If-Match niet kent. Stilzwijgend overschrijven zou
      // hier het werk van een ander kunnen opeten, dus melden we het apart.
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 501;
      });
      addTearDown(fake.stop);

      await expectLater(
        _serviceOn(fake.port).upload('een.md', const [1], ifMatch: '"v1"'),
        throwsA(
          isA<S3Exception>().having(
            (e) => e.kind,
            'kind',
            S3Error.conditionalUnsupported,
          ),
        ),
      );
    });

    test('een 501 zonder voorwaarde blijft een gewone serverfout', () async {
      final fake = await _FakeS3.start((req) async {
        req.response.statusCode = 501;
      });
      addTearDown(fake.stop);

      await expectLater(
        _serviceOn(fake.port).upload('een.md', const [1]),
        throwsA(
          isA<S3Exception>().having((e) => e.kind, 'kind', S3Error.server),
        ),
      );
    });
  });

  group('veiligheid', () {
    test('een pad buiten de wortelprefix wordt geweigerd', () async {
      final service = _serviceOn(1, rootPath: 'klant-a');
      await expectLater(
        service.download('../klant-b/geheim.md'),
        throwsA(
          isA<S3Exception>().having((e) => e.kind, 'kind', S3Error.config),
        ),
      );
    });

    test('http zonder "vertrouwd intern" wordt geweigerd', () async {
      final service = S3Service(
        bucket: const S3Bucket(
          endpoint: 'http://s3.example.com',
          bucket: 'decks',
          accessKeyId: _accessKey,
        ),
        secretAccessKey: _secret,
      );
      await expectLater(
        service.probe(),
        throwsA(
          isA<S3Exception>()
              .having((e) => e.kind, 'kind', S3Error.insecureScheme)
              .having((e) => e.message, 'message', contains('vertrouwd')),
        ),
      );
    });

    test(
      'een publieke host die naar een privé-adres wijst wordt geweigerd',
      () async {
        // NetGuard weigert een privé-adres zolang de bron niet als vertrouwd
        // intern is gemarkeerd — ook als het endpoint er publiek uitziet.
        final service = S3Service(
          bucket: const S3Bucket(
            endpoint: 'https://127.0.0.1',
            bucket: 'decks',
            accessKeyId: _accessKey,
            addressingStyle: S3AddressingStyle.path,
          ),
          secretAccessKey: _secret,
        );
        await expectLater(
          service.probe(),
          throwsA(
            isA<S3Exception>().having(
              (e) => e.kind,
              'kind',
              S3Error.blockedHost,
            ),
          ),
        );
      },
    );
  });

  group('parseListObjectsV2', () {
    test('slaat het map-object over dat op de delimiter eindigt', () {
      // Sommige clients maken een leeg object `map/` aan om een map te
      // suggereren; dat is geen bestand en hoort niet in de lijst.
      final page = S3Service.parseListObjectsV2(
        _listXml(keys: const ['map/', 'map/een.md']),
        0,
      );
      expect(page.entries.map((e) => e.relativePath), ['map/een.md']);
    });

    test('zonder namespace parseert net zo goed', () {
      // Niet elk S3-compatible endpoint zet er dezelfde namespace omheen.
      final page = S3Service.parseListObjectsV2(
        '<ListBucketResult><Contents><Key>een.md</Key></Contents>'
        '</ListBucketResult>',
        0,
      );
      expect(page.entries.single.name, 'een.md');
    });

    test('geen token wanneer de listing niet afgekapt is', () {
      final page = S3Service.parseListObjectsV2(
        _listXml(keys: const ['een.md']),
        0,
      );
      expect(page.nextContinuationToken, isNull);
    });

    test('onleesbare XML wordt een serverfout', () {
      expect(
        () => S3Service.parseListObjectsV2('<niet afgesloten', 0),
        throwsA(
          isA<S3Exception>().having((e) => e.kind, 'kind', S3Error.server),
        ),
      );
    });
  });
}
