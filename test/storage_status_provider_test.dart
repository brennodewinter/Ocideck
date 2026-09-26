import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/s3_settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/secret_store_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/storage_status_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een sleutelhanger in het geheugen; niets raakt de echte keychain.
class _MemorySecretStore extends SecretStore {
  @override
  Future<String?> readWebdavPassword(String b, String u) async => 'wachtwoord';

  @override
  Future<String?> readS3SecretKey(String e, String k) async => 'geheim';

  @override
  Future<String?> readGitToken(String b, String o) async => 'token';
}

/// Programmeerbare probe: per verbinding een completer, zodat de test zelf
/// bepaalt welke probe wanneer terugkomt — dat is precies de race die de
/// provider moet overleven.
class _FakeProbe {
  final calls = <String>[];
  final pending = <String, List<Completer<bool>>>{};

  Future<bool> call(StorageConnection c, SecretStore secrets) {
    calls.add(c.id);
    final completer = Completer<bool>();
    (pending[c.id] ??= []).add(completer);
    return completer.future;
  }

  /// Voltooi de [index]-de nog openstaande probe voor [id] — volgorde uit
  /// de hand houden is precies de race die getest wordt.
  void finish(String id, bool result, {int index = 0}) {
    final list = pending[id] ?? [];
    if (index >= list.length) {
      throw StateError('geen openstaande probe $index voor $id');
    }
    list.removeAt(index).complete(result);
  }
}

const _server = WebdavServer(
  baseUrl: 'https://cloud.example',
  username: 'aisha',
);
const _bucket = S3Bucket(
  endpoint: 'https://s3.example',
  region: 'eu-central-1',
  bucket: 'decks',
  accessKeyId: 'AKIA-test',
);

WebdavConnection _dav({String id = 'w1', String name = 'Kantoor'}) =>
    WebdavConnection(id: id, name: name, server: _server);
S3Connection _s3({String id = 's1'}) =>
    S3Connection(id: id, name: '', bucket: _bucket);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeProbe probe;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    probe = _FakeProbe();
  });

  /// Levende container met de nep-probe en een subscription — autoDispose
  /// breekt de notifier anders af voor de eerste async uitslag landt.
  Future<ProviderContainer> buildContainer(
    List<StorageConnection> connections,
  ) async {
    final notifier = SettingsNotifier(secretStore: _MemorySecretStore());
    final c = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((_) => notifier),
        secretStoreProvider.overrideWithValue(_MemorySecretStore()),
        storageProbeProvider.overrideWithValue(probe.call),
      ],
    );
    addTearDown(c.dispose);
    await notifier.setConnections(connections);
    final sub = c.listen(storageStatusProvider, (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('een lokale map is meteen bereikbaar en wordt nooit geprobed', () async {
    final c = await buildContainer([
      const LocalConnection(id: 'l1', name: 'Schijf', path: '/tmp/decks'),
    ]);
    expect(c.read(storageStatusProvider)['l1'], StorageReach.reachable);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(probe.calls, isEmpty);
  });

  test(
    'een remote verbinding gaat via checking naar de probe-uitslag',
    () async {
      final c = await buildContainer([_dav()]);
      expect(c.read(storageStatusProvider)['w1'], StorageReach.checking);
      expect(probe.calls, ['w1']);

      probe.finish('w1', true);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(storageStatusProvider)['w1'], StorageReach.reachable);
    },
  );

  test('een gemiste probe toont onbereikbaar', () async {
    final c = await buildContainer([_s3()]);
    probe.finish('s1', false);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(storageStatusProvider)['s1'], StorageReach.unreachable);
  });

  test('een onvolledige verbinding komt niet in de map', () async {
    final c = await buildContainer([
      const WebdavConnection(
        id: 'half',
        name: 'Half',
        server: WebdavServer(baseUrl: '', username: ''),
      ),
    ]);
    expect(c.read(storageStatusProvider), isNot(contains('half')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(probe.calls, isEmpty);
  });

  test('een probe voor A raakt een lopende probe voor B niet', () async {
    final c = await buildContainer([_dav(), _s3()]);
    expect(probe.calls, containsAll(['w1', 's1']));

    probe.finish('w1', true);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(storageStatusProvider)['w1'], StorageReach.reachable);
    // B loopt nog en mag gewoon op checking blijven staan.
    expect(c.read(storageStatusProvider)['s1'], StorageReach.checking);

    probe.finish('s1', false);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(storageStatusProvider)['s1'], StorageReach.unreachable);
  });

  test('alleen de nieuwste hertest schrijft haar uitslag', () async {
    final c = await buildContainer([_dav()]);
    probe.finish('w1', true);
    await Future<void>.delayed(Duration.zero);

    // Twee hertests vlak achter elkaar: de eerste uitslag die terugkomt is
    // van de oudste probe en mag niet doorwerken.
    unawaited(c.read(storageStatusProvider.notifier).recheck('w1'));
    unawaited(c.read(storageStatusProvider.notifier).recheck('w1'));
    await Future<void>.delayed(Duration.zero);
    expect(probe.calls, ['w1', 'w1', 'w1']);

    // De oudste van de twee openstaande probes zegt "bereikbaar" — die
    // uitslag is achterhaald en moet vervallen.
    probe.finish('w1', true);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(storageStatusProvider)['w1'], StorageReach.checking);

    probe.finish('w1', false);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(storageStatusProvider)['w1'], StorageReach.unreachable);
  });

  test('recheck hertest een remote verbinding maar geen lokale', () async {
    final c = await buildContainer([
      const LocalConnection(id: 'l1', name: '', path: '/tmp/decks'),
      _dav(),
    ]);
    probe.finish('w1', true);
    await Future<void>.delayed(Duration.zero);

    await c.read(storageStatusProvider.notifier).recheck('l1');
    expect(probe.calls.where((id) => id == 'l1'), isEmpty);

    unawaited(c.read(storageStatusProvider.notifier).recheck('w1'));
    await Future<void>.delayed(Duration.zero);
    expect(probe.calls.where((id) => id == 'w1'), hasLength(2));
  });
}
