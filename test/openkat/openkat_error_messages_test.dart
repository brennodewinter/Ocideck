import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/services/openkat/openkat_error_messages.dart';
import 'package:ocideck/services/openkat/openkat_rocky_client.dart';

void main() {
  group('OpenKatUserMessage.apply', () {
    test('vervangt placeholders', () {
      const msg = OpenKatUserMessage('Hallo {naam}', {'naam': 'Acme'});
      expect(msg.apply('Hallo {naam}'), 'Hallo Acme');
    });
  });

  group('openKatDenialMessage', () {
    test('kent alle denial-codes', () {
      expect(
        openKatDenialMessage('desktop_only').source,
        contains('desktopversie'),
      );
      expect(openKatDenialMessage('token_missing').source, contains('token'));
      expect(openKatDenialMessage('https_required').source, contains('HTTPS'));
      expect(openKatDenialMessage('unknown').source, contains('mislukt'));
    });
  });

  group('openKatErrorMessage', () {
    test('401/403 → token geweigerd', () {
      final msg = openKatErrorMessage(
        const OpenKatRequestException('auth', statusCode: 401),
      );
      expect(msg.source, contains('weigerde het token'));
    });

    test('HTTP-status met code-placeholder', () {
      final msg = openKatErrorMessage(
        const OpenKatRequestException('x', statusCode: 502),
      );
      expect(msg.apply(msg.source), contains('502'));
    });

    test('timeout en netwerk', () {
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('timeout'),
        ).source,
        contains('niet op tijd'),
      );
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('network'),
        ).source,
        contains('mislukt'),
      );
    });

    test('HTTP-prefix in message', () {
      final msg = openKatErrorMessage(
        const OpenKatRequestException('HTTP 503'),
      );
      expect(msg.args['code'], '503');
    });

    test('onbekende fout', () {
      expect(openKatErrorMessage(Exception('x')).source, contains('mislukt'));
    });
  });

  group('openKatStatusLabel', () {
    test('alle statussen', () {
      expect(
        openKatStatusLabel(OpenKatInstallationStatus.connected),
        'Verbonden',
      );
      expect(
        openKatStatusLabel(OpenKatInstallationStatus.tokenMissing),
        'Token ontbreekt',
      );
      expect(
        openKatStatusLabel(OpenKatInstallationStatus.failed),
        'Laatst gecontroleerd mislukt',
      );
      expect(
        openKatStatusLabel(OpenKatInstallationStatus.unchecked),
        'Nog niet gecontroleerd',
      );
    });
  });
}
