import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/s3_settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/s3/s3_service.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/state/s3_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/webdav_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een sleutelhanger in het geheugen; niets raakt de echte keychain.
class _MemorySecretStore extends SecretStore {
  final Map<String, String> _store = {};

  @override
  Future<void> writeWebdavPassword(String b, String u, String p) async {
    _store[SecretStore.webdavKey(b, u)] = p;
  }

  @override
  Future<String?> readWebdavPassword(String b, String u) async =>
      _store[SecretStore.webdavKey(b, u)];

  @override
  Future<void> deleteWebdavPassword(String b, String u) async {
    _store.remove(SecretStore.webdavKey(b, u));
  }

  @override
  Future<void> writeS3SecretKey(String e, String k, String s) async {
    _store[SecretStore.s3SecretKeyKey(e, k)] = s;
  }

  @override
  Future<String?> readS3SecretKey(String e, String k) async =>
      _store[SecretStore.s3SecretKeyKey(e, k)];

  @override
  Future<void> deleteS3SecretKey(String e, String k) async {
    _store.remove(SecretStore.s3SecretKeyKey(e, k));
  }
}

/// De providers die een verbinding uit de instellingen plus een geheim uit de
/// sleutelhanger tot een bruikbare client smeden.
///
/// De regel die ze allemaal delen: liever niets dan iets halfs. Een verbinding
/// die is verwijderd, half is ingevuld, of waarvan het geheim ontbreekt, moet
/// `null` opleveren — een client die daarop toch gebouwd wordt, faalt pas op de
/// lijn, met een foutmelding die niets zegt over de eigenlijke oorzaak.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemorySecretStore secrets;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secrets = _MemorySecretStore();
  });

  Future<ProviderContainer> containerWith(
    List<StorageConnection> connections,
  ) async {
    final notifier = SettingsNotifier(secretStore: secrets);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith((_) => notifier)],
    );
    addTearDown(container.dispose);
    container.read(settingsProvider); // bouw de notifier op
    // Afwachten: de notifier laadt prefs asynchroon, en elke statewijziging
    // maakt de afgeleide providers opnieuw ongeldig.
    await notifier.setConnections(connections);
    return container;
  }

  const server = WebdavServer(
    baseUrl: 'https://cloud.example',
    username: 'aisha',
    rootPath: '/Presentaties',
  );
  const bucket = S3Bucket(
    endpoint: 'https://s3.example',
    region: 'eu-central-1',
    bucket: 'presentaties',
    accessKeyId: 'AKIA-wegwerp',
  );

  WebdavConnection dav({String id = 'w1', String name = 'Kantoor'}) =>
      WebdavConnection(id: id, name: name, server: server);
  S3Connection s3({String id = 's1', String name = 'Archief'}) =>
      S3Connection(id: id, name: name, bucket: bucket);

  group('webdavServiceProvider', () {
    test('bouwt een client als configuratie én wachtwoord er zijn', () async {
      await secrets.writeWebdavPassword(
        server.baseUrl,
        server.username,
        'app-wachtwoord',
      );
      final container = await containerWith([dav()]);

      final service = await container.read(webdavServiceProvider('w1').future);
      expect(service, isNotNull);
      expect(service!.server.baseUrl, server.baseUrl);
    });

    test('geeft niets terug zonder wachtwoord in de sleutelhanger', () async {
      final container = await containerWith([dav()]);

      expect(await container.read(webdavServiceProvider('w1').future), isNull);
    });

    test('geeft niets terug voor een onbekende verbinding', () async {
      await secrets.writeWebdavPassword(
        server.baseUrl,
        server.username,
        'app-wachtwoord',
      );
      final container = await containerWith([dav()]);

      // Een verbinding die de gebruiker intussen verwijderd heeft.
      expect(await container.read(webdavServiceProvider('weg').future), isNull);
    });

    test('een half ingevulde verbinding levert geen client op', () async {
      const half = WebdavServer(baseUrl: 'https://cloud.example', username: '');
      await secrets.writeWebdavPassword(half.baseUrl, '', 'app-wachtwoord');
      final container = await containerWith([
        const WebdavConnection(id: 'w1', name: 'Half', server: half),
      ]);

      expect(await container.read(webdavServiceProvider('w1').future), isNull);
    });

    test('een S3-verbinding onder dezelfde id levert geen WebDAV op', () async {
      // De id's leven in één lijst; een provider die alleen op id kijkt zou
      // hier een client op de verkeerde soort bouwen.
      final container = await containerWith([s3(id: 'gedeeld')]);

      expect(
        await container.read(webdavServiceProvider('gedeeld').future),
        isNull,
      );
    });
  });

  group('s3ServiceProvider', () {
    test('bouwt een client als bucket én sleutel er zijn', () async {
      await secrets.writeS3SecretKey(
        bucket.endpoint,
        bucket.accessKeyId,
        'wegwerp-secret',
      );
      final container = await containerWith([s3()]);

      final service = await container.read(s3ServiceProvider('s1').future);
      expect(service, isNotNull);
      expect(service!.bucket.bucket, 'presentaties');
    });

    test('geeft niets terug zonder secret key', () async {
      final container = await containerWith([s3()]);

      expect(await container.read(s3ServiceProvider('s1').future), isNull);
    });

    test('een lege secret key telt niet als sleutel', () async {
      await secrets.writeS3SecretKey(bucket.endpoint, bucket.accessKeyId, '');
      final container = await containerWith([s3()]);

      expect(await container.read(s3ServiceProvider('s1').future), isNull);
    });

    test('een WebDAV-verbinding onder dezelfde id levert geen S3 op', () async {
      final container = await containerWith([dav(id: 'gedeeld')]);

      expect(await container.read(s3ServiceProvider('gedeeld').future), isNull);
    });
  });

  group('de afgeleide lijsten', () {
    test('de primaire verbinding is de bovenste van haar soort', () async {
      final container = await containerWith([
        s3(id: 's1', name: 'Eerste'),
        dav(id: 'w1', name: 'Kantoor'),
        s3(id: 's2', name: 'Tweede'),
      ]);

      // De volgorde is betekenisvol: de gebruiker sleepte hem zo.
      expect(container.read(primaryS3ConnectionProvider)?.id, 's1');
      expect(container.read(primaryWebdavConnectionProvider)?.id, 'w1');
    });

    test('zonder verbinding van die soort is er geen primaire', () async {
      final container = await containerWith([dav()]);

      expect(container.read(primaryS3ConnectionProvider), isNull);
      expect(container.read(primaryWebdavConnectionProvider), isNotNull);
    });

    test('de keuzelijsten houden de volgorde en scheiden de soorten', () async {
      final container = await containerWith([
        s3(id: 's1', name: 'Eerste'),
        dav(id: 'w1', name: 'Kantoor'),
        s3(id: 's2', name: 'Tweede'),
      ]);

      expect(container.read(s3ConnectionsProvider).map((c) => c.id), [
        's1',
        's2',
      ]);
      expect(container.read(webdavConnectionsProvider).map((c) => c.id), [
        'w1',
      ]);
    });
  });

  group('de listing-providers', () {
    test('zonder ingestelde server komt er een uitlegbare fout', () async {
      final container = await containerWith([]);
      // De listing is autoDispose (een gesloten dialoog houdt de cache niet
      // vast), dus hij moet hier aan een luisteraar hangen om te overleven.
      final dav = webdavListingProvider((connectionId: 'w1', remotePath: ''));
      final s3 = s3ListingProvider((connectionId: 's1', remotePath: ''));
      container.listen(dav, (_, _) {});
      container.listen(s3, (_, _) {});

      // Niet "er ging iets mis" maar de soort fout die de bladeraar tot
      // "controleer je instellingen" kan vertalen.
      await expectLater(
        container.read(dav.future),
        throwsA(
          isA<WebdavException>().having(
            (e) => e.kind,
            'kind',
            WebdavError.config,
          ),
        ),
      );
      await expectLater(
        container.read(s3.future),
        throwsA(
          isA<S3Exception>().having((e) => e.kind, 'kind', S3Error.config),
        ),
      );
    });

    test('dezelfde mapnaam op twee servers is niet dezelfde cache', () async {
      // De sleutel draagt de verbinding mee; deed hij dat niet, dan zag de
      // tweede server de inhoud van de eerste.
      const a = (connectionId: 'w1', remotePath: 'Rapporten');
      const b = (connectionId: 'w2', remotePath: 'Rapporten');
      expect(a == b, isFalse);
      expect(webdavListingProvider(a) == webdavListingProvider(b), isFalse);
      expect(
        webdavListingProvider(a) ==
            webdavListingProvider((
              connectionId: 'w1',
              remotePath: 'Rapporten',
            )),
        isTrue,
      );
    });
  });
}
