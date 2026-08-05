import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/openkat_provider.dart';
import 'package:ocideck/state/secret_store_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late SecretStore secrets;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    secrets = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
    container = ProviderContainer(
      overrides: [secretStoreProvider.overrideWithValue(secrets)],
    );
  });

  tearDown(() => container.dispose());

  Future<void> settle() async {
    // OpenKatNotifier.init is async; geef hem een tick.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('addInstallation schrijft metadata zonder token in prefs', () async {
    final notifier = container.read(openKatProvider.notifier);
    await settle();
    await notifier.setEnabled(true);

    final installation = OpenKatInstallation.create(
      name: 'Acceptatie',
      baseUrl: 'https://ok.example/',
    );
    await notifier.addInstallation(installation, token: 'geheim-token');

    final state = container.read(openKatProvider);
    expect(state.installations, hasLength(1));
    expect(state.installations.first.name, 'Acceptatie');
    expect(state.installations.first.baseUrl, 'https://ok.example');

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('openkatInstallations') ?? '';
    expect(raw, contains('Acceptatie'));
    expect(raw, isNot(contains('geheim-token')));

    final token = await secrets.readOpenKatToken(installation.id);
    expect(token, 'geheim-token');
  });

  test('removeInstallation wist token', () async {
    final notifier = container.read(openKatProvider.notifier);
    await settle();
    final installation = OpenKatInstallation.create(
      name: 'X',
      baseUrl: 'https://x.example',
    );
    await notifier.addInstallation(installation, token: 'tok');
    await notifier.removeInstallation(installation.id);

    expect(container.read(openKatInstallationsProvider), isEmpty);
    expect(await secrets.readOpenKatToken(installation.id), isNull);
  });

  test('hasContent bij installatie zonder map', () async {
    final notifier = container.read(openKatProvider.notifier);
    await settle();
    expect(container.read(openKatHasContentProvider), isFalse);

    await notifier.addInstallation(
      OpenKatInstallation.create(name: 'A', baseUrl: 'https://a.example'),
    );
    expect(container.read(openKatHasContentProvider), isTrue);
    expect(container.read(openKatIntegrationRevealProvider), isTrue);
  });
}
