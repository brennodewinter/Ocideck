import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/services/openkat/openkat_error_messages.dart';
import 'package:ocideck/services/openkat/openkat_rocky_client.dart';

void main() {
  group('OpenKatUserMessage.apply', () {
    test('vervangt één placeholder', () {
      const msg = OpenKatUserMessage('Hallo {naam}', {'naam': 'Acme'});
      expect(msg.apply('Hallo {naam}'), 'Hallo Acme');
    });

    test('vervangt meerdere placeholders', () {
      const msg = OpenKatUserMessage(
        '{host}: {n} items',
        {'host': 'ok.example', 'n': '3'},
      );
      expect(msg.apply('{host}: {n} items'), 'ok.example: 3 items');
    });

    test('lege args laat tekst ongewijzigd', () {
      const msg = OpenKatUserMessage('Geen placeholders');
      expect(msg.apply('Geen placeholders'), 'Geen placeholders');
    });
  });

  group('openKatDenialMessage', () {
    test('desktop_only', () {
      expect(
        openKatDenialMessage('desktop_only').source,
        contains('desktopversie'),
      );
    });

    test('not_configured', () {
      expect(
        openKatDenialMessage('not_configured').source,
        contains('weergavenaam'),
      );
    });

    test('token_missing', () {
      expect(openKatDenialMessage('token_missing').source, contains('token'));
    });

    test('https_required', () {
      expect(openKatDenialMessage('https_required').source, contains('HTTPS'));
    });

    test('onbekende code → algemene fout', () {
      expect(openKatDenialMessage('unknown').source, contains('mislukt'));
      expect(openKatDenialMessage(null).source, contains('mislukt'));
    });
  });

  group('openKatErrorMessage', () {
    test('401 → token geweigerd', () {
      final msg = openKatErrorMessage(
        const OpenKatRequestException('auth', statusCode: 401),
      );
      expect(msg.source, contains('weigerde het token'));
    });

    test('403 → token geweigerd', () {
      final msg = openKatErrorMessage(
        const OpenKatRequestException('auth', statusCode: 403),
      );
      expect(msg.source, contains('weigerde het token'));
    });

    test('HTTP-status met code-placeholder', () {
      final msg = openKatErrorMessage(
        const OpenKatRequestException('x', statusCode: 502),
      );
      expect(msg.args['code'], '502');
      expect(msg.apply(msg.source), contains('502'));
    });

    test('timeout', () {
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('timeout'),
        ).source,
        contains('niet op tijd'),
      );
    });

    test('host refused or unreachable', () {
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('host refused or unreachable'),
        ).source,
        contains('niet bereikbaar'),
      );
    });

    test('response too large', () {
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('response too large'),
        ).source,
        contains('groot antwoord'),
      );
    });

    test('network', () {
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('network'),
        ).source,
        contains('mislukt'),
      );
    });

    test('denial-codes via exception message', () {
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('desktop_only'),
        ).source,
        contains('desktopversie'),
      );
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('not_configured'),
        ).source,
        contains('weergavenaam'),
      );
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('token_missing'),
        ).source,
        contains('token'),
      );
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('https_required'),
        ).source,
        contains('HTTPS'),
      );
    });

    test('HTTP-prefix in message met code', () {
      final msg = openKatErrorMessage(
        const OpenKatRequestException('HTTP 503'),
      );
      expect(msg.args['code'], '503');
      expect(msg.apply(msg.source), contains('503'));
    });

    test('HTTP-prefix 401/403 in message', () {
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('HTTP 401'),
        ).source,
        contains('weigerde het token'),
      );
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('HTTP 403'),
        ).source,
        contains('weigerde het token'),
      );
    });

    test('HTTP-prefix zonder parsebare code', () {
      expect(
        openKatErrorMessage(
          const OpenKatRequestException('HTTP oeps'),
        ).source,
        contains('mislukt'),
      );
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
