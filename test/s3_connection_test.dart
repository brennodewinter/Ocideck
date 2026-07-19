import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/secret_store.dart';

/// Het model-deel van de S3-bron: hoe een verbinding de prefs in en uit gaat,
/// hoe hij zich in de verbindingenlijst gedraagt, en hoe een pad naar een
/// sleutel wordt. De netwerkkant staat in `s3_service_test.dart`.
void main() {
  const bucket = S3Bucket(
    endpoint: 'https://s3.eu-central-1.amazonaws.com',
    region: 'eu-central-1',
    bucket: 'decks',
    accessKeyId: 'AKIA1',
    rootPath: 'klant-a',
    addressingStyle: S3AddressingStyle.path,
    trustedInternal: true,
  );

  group('opslag en teruglezen', () {
    test('een verbinding overleeft een rondje JSON', () {
      const connection = S3Connection(
        id: 'id-1',
        name: 'Klant A',
        bucket: bucket,
      );
      final decoded = StorageConnection.decodeList(
        StorageConnection.encodeList([connection]),
      );
      expect(decoded, hasLength(1));
      final s3 = decoded.single as S3Connection;
      expect(s3.id, 'id-1');
      expect(s3.name, 'Klant A');
      expect(s3.bucket, bucket);
    });

    test(
      'een ontbrekende adresseringsstijl valt terug in plaats van te breken',
      () {
        // Een bron uit een versie van vóór de keuze draagt het veld nog niet; die
        // onbruikbaar maken zou het werk van de gebruiker opeten.
        final restored = StorageConnection.fromJson({
          'id': 'id-2',
          'name': '',
          'kind': 's3',
          'config': {'endpoint': 'https://x', 'bucket': 'b'},
        });
        expect(
          (restored as S3Connection).bucket.addressingStyle,
          S3AddressingStyle.virtualHosted,
        );
        expect(restored.bucket.region, 'us-east-1');
      },
    );

    test('een S3-bron naast de andere soorten blijft op zijn plek staan', () {
      // De volgorde is betekenisvol (primaryOf leest de bovenste), dus hij mag
      // niet door het decoderen verschuiven.
      final list = StorageConnection.decodeList(
        StorageConnection.encodeList(const [
          LocalConnection(id: 'a', name: '', path: '/tmp'),
          S3Connection(id: 'b', name: '', bucket: bucket),
          LocalConnection(id: 'c', name: '', path: '/var'),
        ]),
      );
      expect(list.map((c) => c.kind), [
        StorageConnectionKind.local,
        StorageConnectionKind.s3,
        StorageConnectionKind.local,
      ]);
    });
  });

  group('in de verbindingenlijst', () {
    test('de bovenste bruikbare S3-bron is de standaard', () {
      const half = S3Connection(
        id: 'half',
        name: '',
        // Zonder access key id is hij niet bruikbaar.
        bucket: S3Bucket(endpoint: 'https://x', bucket: 'b'),
      );
      const goed = S3Connection(id: 'goed', name: '', bucket: bucket);
      const settings = AppSettings(connections: [half, goed]);
      // De halve blijft in de lijst staan — hem weggooien zou het werk van de
      // gebruiker opeten — maar telt niet mee als bruikbare bron: niet voor de
      // standaard, en ook niet in de keuzelijst.
      expect(settings.connections, hasLength(2));
      expect(settings.s3Bucket, bucket);
      expect(settings.connectionsOf<S3Connection>().map((c) => c.id), ['goed']);
    });

    test('geen S3-bron levert geen bucket op', () {
      const settings = AppSettings(
        connections: [LocalConnection(id: 'a', name: '', path: '/tmp')],
      );
      expect(settings.s3Bucket, isNull);
    });

    test('de naam valt terug op de bucketnaam', () {
      // Niet op de endpoint-host: twee buckets op hetzelfde endpoint is het
      // gangbare geval, dezelfde bucket op twee endpoints niet.
      const connection = S3Connection(id: 'a', name: '', bucket: bucket);
      expect(connection.fallbackLabel, 'decks');
    });
  });

  group('keyFor', () {
    test('plakt de wortelprefix ervoor, zonder leidende slash', () {
      expect(bucket.keyFor('map/een.md'), 'klant-a/map/een.md');
    });

    test('een leeg pad is de wortelprefix zelf', () {
      expect(bucket.keyFor(''), 'klant-a');
    });

    test('zonder wortelprefix is de sleutel het pad', () {
      const plat = S3Bucket(endpoint: 'https://x', bucket: 'b');
      expect(plat.keyFor('een.md'), 'een.md');
    });

    test('een pad dat uit de wortel breekt wordt geweigerd', () {
      expect(bucket.keyFor('../klant-b/geheim.md'), isNull);
      expect(bucket.keyFor('../../etc/passwd'), isNull);
    });

    test('een pad dat binnen de wortel terugkomt mag wel', () {
      expect(bucket.keyFor('map/../een.md'), 'klant-a/een.md');
    });

    test('zonder wortelprefix breekt .. alsnog niet uit de bucket', () {
      const plat = S3Bucket(endpoint: 'https://x', bucket: 'b');
      expect(plat.keyFor('../buiten.md'), isNull);
    });
  });

  group('normalizeRoot', () {
    test('haalt leidende en afsluitende slashes weg', () {
      expect(S3Bucket.normalizeRoot('/decks/'), 'decks');
      expect(S3Bucket.normalizeRoot('///a//b///'), 'a/b');
      expect(S3Bucket.normalizeRoot('  '), '');
    });
  });

  group('adressering', () {
    test('virtual-hosted zet de bucket vóór de host', () {
      const b = S3Bucket(
        endpoint: 'https://s3.eu-central-1.amazonaws.com',
        bucket: 'decks',
        accessKeyId: 'k',
      );
      expect(b.signingHost, 'decks.s3.eu-central-1.amazonaws.com');
      expect(b.endpointHost, 's3.eu-central-1.amazonaws.com');
      expect(
        b.uriForKey('een.md').toString(),
        'https://decks.s3.eu-central-1.amazonaws.com/een.md',
      );
    });

    test('path-style zet de bucket in het pad en houdt de poort', () {
      const b = S3Bucket(
        endpoint: 'https://minio.intern:9000',
        bucket: 'decks',
        accessKeyId: 'k',
        addressingStyle: S3AddressingStyle.path,
      );
      expect(b.signingHost, 'minio.intern');
      expect(
        b.uriForKey('map/een.md').toString(),
        'https://minio.intern:9000/decks/map/een.md',
      );
    });

    test(
      'de sleutel wordt met de AWS-regels gecodeerd, niet met die van Uri',
      () {
        const b = S3Bucket(
          endpoint: 'https://x.example.com',
          bucket: 'decks',
          accessKeyId: 'k',
          addressingStyle: S3AddressingStyle.path,
        );
        // Haakjes en apostrof: Uri laat die staan, AWS wil ze gecodeerd. Zou dat
        // hier misgaan, dan wijkt het verstuurde pad af van het ondertekende.
        expect(
          b.uriForKey("notulen (def) 'v2'.md").toString(),
          'https://x.example.com/decks/notulen%20%28def%29%20%27v2%27.md',
        );
      },
    );
  });

  group('keychain-sleutel', () {
    test('normaliseert een trailing slash weg', () {
      expect(
        SecretStore.s3SecretKeyKey('https://x/', 'AKIA1'),
        SecretStore.s3SecretKeyKey('https://x', 'AKIA1'),
      );
    });

    test('verschillende sleutels krijgen verschillende entries', () {
      expect(
        SecretStore.s3SecretKeyKey('https://x', 'AKIA1'),
        isNot(SecretStore.s3SecretKeyKey('https://x', 'AKIA2')),
      );
    });
  });

  group('verifiedAt', () {
    // "Ingevuld" is niet hetzelfde als "werkt". De statusregel werd groen bij
    // een server die nooit was aangeraakt; dit veld is het verschil.
    test('round-trips through the connection list', () {
      final when = DateTime.utc(2026, 7, 19, 14, 22);
      final list = [
        S3Connection(
          id: 'a',
          name: 'Klant A',
          bucket: const S3Bucket(
            endpoint: 'https://s3.example.com',
            bucket: 'decks',
            region: 'eu-central-1',
            accessKeyId: 'AKIA1',
          ),
          verifiedAt: when,
        ),
      ];
      final back = StorageConnection.decodeList(
        StorageConnection.encodeList(list),
      );
      expect(back.single.verifiedAt, when);
    });

    test('a connection that was never tested has none', () {
      final back = StorageConnection.decodeList(
        StorageConnection.encodeList([
          const LocalConnection(id: 'a', name: 'Privé', path: '/tmp/x'),
        ]),
      );
      expect(back.single.verifiedAt, isNull);
    });

    test('an unreadable date means "never tested", not a lost connection', () {
      // Eén kapot veld mag de verbinding niet onbruikbaar maken: de
      // servergegevens zijn nog prima, alleen de waarneming is weg.
      final back = StorageConnection.decodeList(
        '[{"id":"a","name":"Klant A","kind":"local",'
        '"verifiedAt":"gisteren","config":{"path":"/tmp/x"}}]',
      );
      expect(back, hasLength(1));
      expect(back.single.verifiedAt, isNull);
      expect(back.single.isConfigured, isTrue);
    });

    test('clearVerified wipes it, and a plain copyWith keeps it', () {
      final when = DateTime.utc(2026, 7, 19);
      final c = LocalConnection(
        id: 'a',
        name: 'Privé',
        path: '/tmp/x',
        verifiedAt: when,
      );
      expect(c.copyWith(name: 'Anders').verifiedAt, when);
      expect(c.copyWith(clearVerified: true).verifiedAt, isNull);
    });
  });
}
