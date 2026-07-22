// Geheimen op een platform zónder sleutelbos: OciDeck bewaart er geen.
//
// **Waarom dit een weigering is en geen versleuteling.** De webkant van
// `flutter_secure_storage` versleutelt met AES-GCM, maar zet — zonder
// `WebOptions.wrapKey` — de sleutel met `exportKey('raw')` in dezelfde
// `localStorage` als de cijfertekst. Sleutel en slot in één la; elk script op
// die pagina leest het geheim terug. Een git-token, een S3-secret, een
// WebDAV-wachtwoord en een AI-sleutel lagen daar dus open, terwijl
// `docs/PRIVACY.md` de sleutelbos van het besturingssysteem belooft.
//
// Deze tests toetsen dat het slot werkelijk dicht is — niet dat de gelukkige weg
// het nog doet. Vandaar de spion: die faalt de test zodra er ook maar één byte
// richting de opslag gaat.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secret_store.dart';

/// Een opslag die niets doet en onthoudt dát er iets langskwam. Elke aanroep
/// hier is een bewijs dat de poort níét gesloten heeft.
class _SpyStorage extends FlutterSecureStorage {
  const _SpyStorage(this.touched);

  final List<String> touched;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => touched.add('write:$key');

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    touched.add('read:$key');
    return 'geheim-dat-er-niet-hoort-te-zijn';
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => touched.add('delete:$key');
}

void main() {
  late List<String> touched;
  late SecretStore refusing;
  late SecretStore storing;

  setUp(() {
    touched = [];
    refusing = SecretStore(storage: _SpyStorage(touched), canStore: false);
    storing = SecretStore(storage: _SpyStorage(touched), canStore: true);
  });

  group('zonder sleutelbos wordt er niets weggeschreven', () {
    test('het git-token gaat de opslag niet in', () async {
      await expectLater(
        refusing.writeGitToken('https://git.example.org', 'librekat', 'ghp_x'),
        throwsA(isA<SecretStoreUnsupported>()),
      );
      expect(touched, isEmpty);
    });

    test('het WebDAV-wachtwoord gaat de opslag niet in', () async {
      await expectLater(
        refusing.writeWebdavPassword('https://cloud.example', 'bram', 'pw'),
        throwsA(isA<SecretStoreUnsupported>()),
      );
      expect(touched, isEmpty);
    });

    test('de S3 secret access key gaat de opslag niet in', () async {
      await expectLater(
        refusing.writeS3SecretKey('https://s3.example', 'AKIA', 'sleutel'),
        throwsA(isA<SecretStoreUnsupported>()),
      );
      expect(touched, isEmpty);
    });

    test('de AI-sleutel gaat de opslag niet in', () async {
      await expectLater(
        refusing.writeAiApiKey('https://ai.example', 'sk-x'),
        throwsA(isA<SecretStoreUnsupported>()),
      );
      expect(touched, isEmpty);
    });

    test('de melding draagt wél de naam maar nooit de waarde', () async {
      try {
        await refusing.writeGitToken('https://git.example', 'o', 'ghp_geheim');
        fail('had moeten weigeren');
      } on SecretStoreUnsupported catch (e) {
        expect(e.label, 'writeGitToken');
        expect(e.toString(), isNot(contains('ghp_geheim')));
      }
    });
  });

  group('zonder sleutelbos komt er ook niets uit', () {
    // Lezen geeft null in plaats van te werpen: er staat werkelijk niets, en
    // elke aanroeper kan al met "geen geheim geconfigureerd" omgaan. Maar het
    // mag de opslag niet aanraken — anders leest het alsnog wat een eerdere
    // versie daar heeft achtergelaten.
    test('lezen raakt de opslag niet aan en geeft null', () async {
      expect(await refusing.readGitToken('https://git.example', 'o'), isNull);
      expect(
        await refusing.readWebdavPassword('https://c.example', 'b'),
        isNull,
      );
      expect(
        await refusing.readS3SecretKey('https://s3.example', 'AKIA'),
        isNull,
      );
      expect(await refusing.readAiApiKey('https://ai.example'), isNull);
      expect(touched, isEmpty);
    });

    test('wissen slaagt stil, want er valt niets te wissen', () async {
      await refusing.deleteGitToken('https://git.example', 'o');
      await refusing.deleteWebdavPassword('https://c.example', 'b');
      await refusing.deleteS3SecretKey('https://s3.example', 'AKIA');
      await refusing.deleteAiApiKey('https://ai.example');
      expect(touched, isEmpty);
    });

    test('canStore vertelt de interface wat er niet kan', () {
      expect(refusing.canStore, isFalse);
      expect(storing.canStore, isTrue);
    });
  });

  group('mét sleutelbos verandert er niets', () {
    // De weigering mag geen enkel platform met een echte sleutelbos raken.
    test('schrijven, lezen en wissen lopen gewoon door', () async {
      await storing.writeGitToken('https://git.example.org', 'librekat', 'x');
      await storing.readGitToken('https://git.example.org', 'librekat');
      await storing.deleteGitToken('https://git.example.org', 'librekat');
      expect(touched, hasLength(3));
      expect(touched.first, startsWith('write:git_pat::'));
    });
  });

  test('op deze machine (desktop) staat de sleutelbos gewoon aan', () {
    // Bewaakt dat de vlag niet per ongeluk overal uit komt te staan: dan zou
    // elke bron stilletjes zijn geheim verliezen op macOS/Windows/Linux.
    expect(platformCanStoreSecrets, isTrue);
  });
}
