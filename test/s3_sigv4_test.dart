import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/s3/s3_sigv4.dart';

/// Toetst [S3Signer] tegen handtekeningen die met botocore — de referentie-
/// implementatie van AWS zelf — zijn uitgerekend over exact dezelfde verzoeken,
/// sleutel en klok. Wijkt onze uitkomst ook maar één bit af, dan zou een echte
/// S3-server het verzoek met 403 weigeren, en dát is wat deze groep afvangt.
///
/// De vectoren zijn bewust niet uit de documentatie overgetikt maar door
/// botocore gegenereerd (`SigV4Auth(creds, 's3', 'us-east-1')` met de klok op
/// 2013-05-24), zodat ze aantoonbaar bij een werkende implementatie horen in
/// plaats van bij een gok.
///
/// De klok gaat als parameter mee ([S3Signer.sign] neemt `now`) juist om dit
/// mogelijk te maken: een signer die intern `DateTime.now()` zou lezen valt niet
/// tegen een vaste vector te leggen.
void main() {
  // De publieke voorbeeldsleutel uit de AWS-documentatie. Geen echt geheim.
  const signer = S3Signer(
    accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
    secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
    region: 'us-east-1',
  );
  final when = DateTime.utc(2013, 5, 24);
  const host = 'examplebucket.s3.amazonaws.com';
  final emptyHash = S3Signer.emptyPayloadHash;

  /// Trekt de `Signature=`-waarde uit de Authorization-header.
  String signatureOf(Map<String, String> headers) {
    final auth = headers['Authorization']!;
    return auth.split('Signature=').last;
  }

  group('botocore-vectoren', () {
    test('GET Object met Range-header', () {
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://$host/test.txt'),
        headers: {'host': host, 'range': 'bytes=0-9'},
        payloadSha256: emptyHash,
        now: when,
      );
      expect(
        signatureOf(headers),
        '67fe34c8530db585abddc51067328adfedb6e42487d2566dc7d927d6e2722900',
      );
    });

    test('PUT Object met een dollarteken in de sleutel', () {
      // sha256 van de letterlijke tekst "Welcome to Amazon S3.".
      const bodyHash =
          '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072';
      final headers = signer.sign(
        method: 'PUT',
        uri: Uri.parse('https://$host/test%24file.text'),
        headers: {'host': host, 'x-amz-storage-class': 'REDUCED_REDUNDANCY'},
        payloadSha256: bodyHash,
        now: when,
      );
      expect(
        signatureOf(headers),
        '0b937fd3b36489ead77c46c408284f7e616019782fa0882af96ddf31ecfecec4',
      );
    });

    test('een rauwe dollar in het pad tekent hetzelfde als de gecodeerde vorm', () {
      // `Uri.parse` laat `$` in een pad staan (het is een sub-delimiter), maar
      // AWS wil hem gecodeerd zien. Beide schrijfwijzen moeten dus op dezelfde
      // handtekening uitkomen, anders hangt het van de aanroeper af of de
      // server het verzoek accepteert.
      String sigFor(String path) => signatureOf(
        signer.sign(
          method: 'PUT',
          uri: Uri.parse('https://$host/$path'),
          headers: {'host': host, 'x-amz-storage-class': 'REDUCED_REDUNDANCY'},
          payloadSha256:
              '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072',
          now: when,
        ),
      );
      expect(sigFor(r'test$file.text'), sigFor('test%24file.text'));
    });

    test('GET Bucket Lifecycle — subresource zonder waarde', () {
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://$host/?lifecycle'),
        headers: {'host': host},
        payloadSha256: emptyHash,
        now: when,
      );
      expect(
        signatureOf(headers),
        '964c7e476ea67fd0dbe754c179c24b69f45f4484575238740e4eef8ee26697ff',
      );
    });

    test('GET Bucket met max-keys en prefix', () {
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://$host/?max-keys=2&prefix=J'),
        headers: {'host': host},
        payloadSha256: emptyHash,
        now: when,
      );
      expect(
        signatureOf(headers),
        'b331a8a008500e1d26eaac3f17e064ed30785ac0cd1bed5e2acc9565175a7d92',
      );
    });

    test('een sleutel met een spatie', () {
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://$host/map/een%20twee.md'),
        headers: {'host': host},
        payloadSha256: emptyHash,
        now: when,
      );
      expect(
        signatureOf(headers),
        '6097ba42a8006b70cd554ddea016e5987765776c7a1c5de91f48135c9f2cfd5e',
      );
    });

    test('ListObjectsV2 zoals de bladeraar hem stuurt', () {
      // Precies de vorm die [S3Service.list] gebruikt: list-type=2 met een
      // delimiter zodat prefixen zich als mappen gedragen.
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse(
          'https://$host/?list-type=2&delimiter=%2F&prefix=decks%2F',
        ),
        headers: {'host': host},
        payloadSha256: emptyHash,
        now: when,
      );
      expect(
        signatureOf(headers),
        'fc5abcfcc63e5978fd47bf92ce3350076bbe49d72e68fee001960157090fa697',
      );
    });
  });

  group('Authorization-header', () {
    test('draagt algoritme, scope en ondertekende headers', () {
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://$host/test.txt'),
        headers: {'host': host},
        payloadSha256: emptyHash,
        now: when,
      );
      expect(
        headers['Authorization'],
        startsWith(
          'AWS4-HMAC-SHA256 '
          'Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, ',
        ),
      );
      // De datum- en payload-header worden altijd meeondertekend, ook als de
      // aanroeper ze niet meegaf.
      expect(
        headers['Authorization'],
        contains('SignedHeaders=host;x-amz-content-sha256;x-amz-date'),
      );
      expect(headers['x-amz-date'], '20130524T000000Z');
      expect(headers['x-amz-content-sha256'], emptyHash);
    });
  });

  group('encodeRfc3986', () {
    test('laat alleen de niet-gereserveerde tekens staan', () {
      expect(S3Signer.encodeRfc3986("aZ0-_.~"), "aZ0-_.~");
    });

    test('escapet wat Uri.encodeComponent ongemoeid laat', () {
      // Dit is de reden dat we niet op Uri.encodeComponent leunen: die laat
      // deze vijf staan en de handtekening zou dan niet kloppen.
      expect(S3Signer.encodeRfc3986("!*'()"), '%21%2A%27%28%29');
      expect(Uri.encodeComponent("!*'()"), "!*'()");
    });

    test('escapet spatie en slash', () {
      expect(S3Signer.encodeRfc3986('a b/c'), 'a%20b%2Fc');
    });

    test('codeert niet-ASCII als UTF-8-bytes', () {
      expect(S3Signer.encodeRfc3986('é'), '%C3%A9');
    });
  });

  group('canonicalUri', () {
    test('een leeg pad wordt de wortel', () {
      expect(S3Signer.canonicalUri(Uri.parse('https://$host')), '/');
    });

    test('codeert per segment, slashes blijven scheidingsteken', () {
      expect(
        S3Signer.canonicalUri(Uri.parse('https://$host/map/een%20twee.md')),
        '/map/een%20twee.md',
      );
    });

    test('normaliseert het pad niet weg', () {
      // Een S3-sleutel mag letterlijk zo heten; wegnormaliseren zou een ander
      // object ondertekenen dan we opvragen.
      expect(S3Signer.canonicalUri(Uri.parse('https://$host/a//b')), '/a//b');
    });
  });

  group('canonicalQuery', () {
    test('sorteert op naam', () {
      expect(
        S3Signer.canonicalQuery(Uri.parse('https://$host/?b=2&a=1&c=3')),
        'a=1&b=2&c=3',
      );
    });

    test('een parameter zonder waarde houdt zijn isgelijkteken', () {
      expect(
        S3Signer.canonicalQuery(Uri.parse('https://$host/?lifecycle')),
        'lifecycle=',
      );
    });

    test('codeert naam en waarde strikt', () {
      expect(
        S3Signer.canonicalQuery(Uri.parse('https://$host/?prefix=a+b%2Fc')),
        'prefix=a%20b%2Fc',
      );
    });

    test('geen query levert een lege string', () {
      expect(S3Signer.canonicalQuery(Uri.parse('https://$host/x')), '');
    });
  });

  group('hashPayload', () {
    test('lege body komt overeen met de bekende sha256 van niets', () {
      expect(
        S3Signer.emptyPayloadHash,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });
}
