import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een sleutelbos in het geheugen. `weiger` bootst een keychain na die niet
/// meewerkt — het geval waarin de migratie de oude waarde móet laten staan.
class _FakeKeychain implements FlutterSecureStorage {
  final Map<String, String> entries = {};
  bool weiger = false;

  @override
  Future<String?> read({
    required String key,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) async {
    if (weiger) throw Exception('keychain dicht');
    return entries[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) async {
    if (weiger) throw Exception('keychain dicht');
    if (value == null) {
      entries.remove(key);
    } else {
      entries[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) async {
    if (weiger) throw Exception('keychain dicht');
    entries.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeKeychain keychain;

  setUp(() {
    keychain = _FakeKeychain();
  });

  Future<SettingsNotifier> loaded() async {
    final notifier = SettingsNotifier(
      secretStore: SecretStore(storage: keychain),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return notifier;
  }

  test('je eigen gegevens gaan naar de sleutelbos, niet naar prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = await loaded();

    await notifier.setPrivacyOwnIdentity('Bram de Vries\nbram@voorbeeld.test');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('privacyOwnIdentity'),
      isNull,
      reason: 'naam en e-mailadres horen niet in het platte prefs-domein',
    );
    expect(
      keychain.entries[SecretStore.privacyOwnIdentityKey],
      'Bram de Vries\nbram@voorbeeld.test',
    );
  });

  test('een bestaande prefs-waarde verhuist eenmalig mee', () async {
    SharedPreferences.setMockInitialValues({
      'privacyOwnIdentity': 'Bram de Vries\n0600000000',
    });

    final notifier = await loaded();

    expect(notifier.state.privacyOwnIdentity, 'Bram de Vries\n0600000000');
    expect(
      keychain.entries[SecretStore.privacyOwnIdentityKey],
      'Bram de Vries\n0600000000',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('privacyOwnIdentity'), isNull);
  });

  test('een weigerende sleutelbos laat de oude waarde staan', () async {
    SharedPreferences.setMockInitialValues({
      'privacyOwnIdentity': 'Bram de Vries',
    });
    keychain.weiger = true;

    final notifier = await loaded();

    expect(notifier.state.privacyOwnIdentity, 'Bram de Vries');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('privacyOwnIdentity'),
      'Bram de Vries',
      reason:
          'zonder deze waarde meldt de scanner de naam van de gebruiker zelf; '
          'die kwijtraken is erger dan hem één sessie langer op de oude plek '
          'laten staan',
    );
  });

  test('na een herstart komt de waarde uit de sleutelbos terug', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await loaded();
    await first.setPrivacyOwnIdentity('bram@voorbeeld.test');

    final second = await loaded();

    expect(second.state.privacyOwnIdentity, 'bram@voorbeeld.test');
  });
}
