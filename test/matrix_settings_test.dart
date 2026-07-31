// Tests for the Matrix account model (`lib/models/matrix_settings.dart`, P-D).

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/matrix_settings.dart';

void main() {
  const server = MatrixServer(
    homeserverUrl: 'https://matrix.example.org',
    userId: '@alice:example.org',
    deviceId: 'DEVICE1',
    trustedInternal: true,
    pinnedCertSha256: 'abc',
  );

  test('survives a JSON round-trip', () {
    expect(MatrixServer.fromJson(server.toJson()), server);
  });

  test('fromJson tolerates missing optional fields', () {
    final back = MatrixServer.fromJson({
      'homeserverUrl': 'https://hs',
      'userId': '@a:hs',
    });
    expect(back.deviceId, '');
    expect(back.trustedInternal, isFalse);
    expect(back.pinnedCertSha256, '');
  });

  test('isConfigured needs both a homeserver and a user id', () {
    expect(server.isConfigured, isTrue);
    expect(
      const MatrixServer(homeserverUrl: 'https://hs', userId: '').isConfigured,
      isFalse,
    );
    expect(
      const MatrixServer(homeserverUrl: '', userId: '@a:hs').isConfigured,
      isFalse,
    );
  });

  test('origin and host parse the homeserver, or are null/empty', () {
    expect(server.host, 'matrix.example.org');
    expect(server.origin?.scheme, 'https');
    const bad = MatrixServer(homeserverUrl: 'not a url', userId: '@a:hs');
    expect(bad.origin, isNull);
    expect(bad.host, '');
  });

  test('participantId is userId:deviceId', () {
    expect(server.participantId, '@alice:example.org:DEVICE1');
  });

  test('copyWith replaces only the named fields', () {
    final updated = server.copyWith(deviceId: 'DEVICE2');
    expect(updated.deviceId, 'DEVICE2');
    expect(updated.userId, server.userId);
    expect(updated.trustedInternal, server.trustedInternal);
  });

  test('equality and hashCode cover all fields', () {
    expect(server, server.copyWith());
    expect(server.hashCode, server.copyWith().hashCode);
    expect(server, isNot(server.copyWith(userId: '@bob:example.org')));
  });
}
