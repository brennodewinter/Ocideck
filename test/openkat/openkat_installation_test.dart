import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';

void main() {
  group('normalizeOpenKatBaseUrl', () {
    test('stript trailing slashes', () {
      expect(
        normalizeOpenKatBaseUrl('https://openkat.example/'),
        'https://openkat.example',
      );
      expect(
        normalizeOpenKatBaseUrl('https://openkat.example///'),
        'https://openkat.example',
      );
    });
  });

  group('validateOpenKatBaseUrl', () {
    test('leeg adres', () {
      expect(
        validateOpenKatBaseUrl('', trustedInternal: false),
        contains('Vul een adres in'),
      );
    });

    test('HTTP zonder LAN geweigerd', () {
      expect(
        validateOpenKatBaseUrl(
          'http://openkat.lan',
          trustedInternal: false,
        ),
        contains('https://'),
      );
    });

    test('HTTP met LAN toegestaan', () {
      expect(
        validateOpenKatBaseUrl('http://openkat.lan', trustedInternal: true),
        isNull,
      );
    });

    test('HTTPS ok', () {
      expect(
        validateOpenKatBaseUrl(
          'https://openkat.voorbeeld.nl',
          trustedInternal: false,
        ),
        isNull,
      );
    });
  });

  group('OpenKatInstallation json', () {
    test('round-trip', () {
      final original = OpenKatInstallation.create(
        name: 'Productie',
        baseUrl: 'https://openkat.example/',
        trustedInternal: false,
      ).copyWith(
        lastStatus: OpenKatInstallationStatus.connected,
        lastCheckedAt: DateTime.utc(2026, 8, 5, 12),
      );
      final restored = OpenKatInstallation.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, 'Productie');
      expect(restored.baseUrl, 'https://openkat.example');
      expect(restored.lastStatus, OpenKatInstallationStatus.connected);
      expect(restored.host, 'openkat.example');
    });

    test('token zit niet in prefs-json', () {
      final json = OpenKatInstallation.create(
        name: 'X',
        baseUrl: 'https://a.example',
      ).toJson();
      expect(json.keys, isNot(contains('token')));
      expect(json.keys, isNot(contains('password')));
    });
  });
}
