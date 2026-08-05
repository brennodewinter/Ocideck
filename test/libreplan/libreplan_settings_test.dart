import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/libreplan_settings.dart';

void main() {
  group('LibreplanSettings', () {
    test('defaults are off and empty', () {
      const s = LibreplanSettings();
      expect(s.enabled, isFalse);
      expect(s.baseUrl, '');
      expect(s.username, '');
      expect(s.trustedInternal, isFalse);
      expect(s.hasBackend, isFalse);
      expect(s.isConfigured, isFalse);
    });

    test('hasBackend is true only when both baseUrl and username are set', () {
      expect(
        const LibreplanSettings(baseUrl: 'https://x', username: 'u').hasBackend,
        isTrue,
      );
      expect(const LibreplanSettings(baseUrl: 'https://x').hasBackend, isFalse);
      expect(const LibreplanSettings(username: 'u').hasBackend, isFalse);
      // Whitespace-only counts as empty.
      expect(
        const LibreplanSettings(baseUrl: '  ', username: 'u').hasBackend,
        isFalse,
      );
    });

    test('isConfigured requires enabled AND hasBackend', () {
      expect(
        const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://x',
          username: 'u',
        ).isConfigured,
        isTrue,
      );
      expect(
        const LibreplanSettings(
          enabled: false,
          baseUrl: 'https://x',
          username: 'u',
        ).isConfigured,
        isFalse,
      );
    });

    test('host extracts the hostname from baseUrl', () {
      expect(
        const LibreplanSettings(
          baseUrl: 'https://libreplan.example.org/libreplan/',
        ).host,
        'libreplan.example.org',
      );
      expect(const LibreplanSettings(baseUrl: 'not-a-url').host, '');
      expect(const LibreplanSettings().host, '');
    });

    test('isHttps is true only for https scheme', () {
      expect(const LibreplanSettings(baseUrl: 'https://x').isHttps, isTrue);
      expect(const LibreplanSettings(baseUrl: 'http://x').isHttps, isFalse);
      expect(const LibreplanSettings(baseUrl: '').isHttps, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const s = LibreplanSettings(
        enabled: true,
        baseUrl: 'https://x',
        username: 'u',
        trustedInternal: true,
      );
      expect(s.copyWith(enabled: false).enabled, isFalse);
      expect(s.copyWith(enabled: false).baseUrl, 'https://x');
      expect(s.copyWith(baseUrl: 'https://y').baseUrl, 'https://y');
      expect(s.copyWith(username: 'v').username, 'v');
      expect(s.copyWith(trustedInternal: false).trustedInternal, isFalse);
    });

    test('toJson / fromJson round-trip', () {
      const s = LibreplanSettings(
        enabled: true,
        baseUrl: 'https://x',
        username: 'u',
        trustedInternal: true,
      );
      final json = s.toJson();
      expect(LibreplanSettings.fromJson(json), s);
    });

    test('fromJson tolerates missing keys', () {
      expect(LibreplanSettings.fromJson({}), const LibreplanSettings());
    });

    test('equality and hashCode', () {
      const a = LibreplanSettings(
        enabled: true,
        baseUrl: 'https://x',
        username: 'u',
        trustedInternal: true,
      );
      const b = LibreplanSettings(
        enabled: true,
        baseUrl: 'https://x',
        username: 'u',
        trustedInternal: true,
      );
      const c = LibreplanSettings(
        enabled: false,
        baseUrl: 'https://x',
        username: 'u',
        trustedInternal: true,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
