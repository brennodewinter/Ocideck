import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/storage_connection.dart';

/// De herkomst van een deck dat uit S3 komt. Dit is wat "Opslaan naar S3" laat
/// weten waar het terug moet, en waarop de conflictbewaking leunt — dus de
/// randgevallen zitten hier en niet in de UI.
void main() {
  const bucket = S3Bucket(
    endpoint: 'https://s3.eu-central-1.amazonaws.com',
    bucket: 'decks',
    accessKeyId: 'AKIA1',
  );

  const origin = S3Origin(
    connectionId: 'conn-1',
    endpoint: 'https://s3.eu-central-1.amazonaws.com',
    bucket: 'decks',
    remotePath: 'map/een.ocideck',
    etag: '"v1"',
  );

  group('matchesBucket', () {
    test('dezelfde bucket op hetzelfde endpoint', () {
      expect(origin.matchesBucket(bucket), isTrue);
    });

    test('een andere bucket op hetzelfde endpoint telt niet', () {
      // Anders zou het pad van klant A in de bucket van klant B belanden.
      expect(origin.matchesBucket(bucket.copyWith(bucket: 'anders')), isFalse);
    });

    test('dezelfde bucketnaam op een ander endpoint telt niet', () {
      // Bucketnamen zijn niet globaal uniek zodra je ook zelf hostende
      // aanbieders meerekent, dus de naam alleen zegt niets.
      expect(
        origin.matchesBucket(bucket.copyWith(endpoint: 'https://minio.intern')),
        isFalse,
      );
    });

    test('spaties eromheen maken geen verschil', () {
      expect(origin.matchesBucket(bucket.copyWith(bucket: ' decks ')), isTrue);
    });

    test('de regio doet er niet toe voor de herkomst', () {
      // De regio hoort bij het ondertekenen, niet bij de vraag "is dit
      // dezelfde plek?".
      expect(
        origin.matchesBucket(bucket.copyWith(region: 'us-west-2')),
        isTrue,
      );
    });
  });

  group('parentPath', () {
    test('geeft de prefix waarin het object staat', () {
      expect(origin.parentPath, 'map');
    });

    test('een object in de wortel heeft geen prefix', () {
      const root = S3Origin(
        endpoint: 'https://x',
        bucket: 'b',
        remotePath: 'een.md',
      );
      expect(root.parentPath, '');
    });

    test('een diepere prefix blijft heel', () {
      const diep = S3Origin(
        endpoint: 'https://x',
        bucket: 'b',
        remotePath: 'a/b/c/een.md',
      );
      expect(diep.parentPath, 'a/b/c');
    });
  });

  group('etag', () {
    test('zonder etag valt er niets te bewaken', () {
      // Een endpoint dat geen ETag geeft, laat dat zo zien in plaats van een
      // waarde te verzinnen die de guard stil zou uitschakelen.
      const zonder = S3Origin(
        endpoint: 'https://x',
        bucket: 'b',
        remotePath: 'een.md',
      );
      expect(zonder.etag, isNull);
    });
  });

  group('de verbinding terugvinden', () {
    test('een deck vindt zijn bron terug via het verbindings-id', () {
      // Het id overleeft hernoemen en het herstellen van een typefout in het
      // endpoint; daarom wijst de herkomst daarheen en niet naar de URL.
      const settings = AppSettings(
        connections: [
          S3Connection(id: 'conn-1', name: 'Klant A', bucket: bucket),
        ],
      );
      final found = settings.connectionById(origin.connectionId);
      expect(found, isA<S3Connection>());
      expect((found! as S3Connection).bucket.bucket, 'decks');
    });

    test('een verwijderde verbinding levert null op, geen gok', () {
      const settings = AppSettings(connections: []);
      expect(settings.connectionById(origin.connectionId), isNull);
    });
  });
}
