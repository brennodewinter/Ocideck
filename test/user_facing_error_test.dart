import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/utils/user_facing_error.dart';

/// Tests the caught-error → user-message mapping. With the active language set
/// to Dutch, `l10n.d(...)` returns its source string verbatim, so we can assert
/// the exact message each branch produces.
void main() {
  const l10n = AppLocalizations(Locale('nl'));
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('userFacingError', () {
    test('maps filesystem permission errors to a "no write rights" hint', () {
      for (final code in [1, 13]) {
        final e = FileSystemException('denied', '/x', OSError('EACCES', code));
        expect(
          userFacingError(l10n, e),
          'Geen schrijfrechten op deze locatie. Kies een andere map.',
        );
      }
    });

    test('maps ENOSPC to "disk full" and ENOENT to "not found"', () {
      expect(
        userFacingError(l10n, FileSystemException('', '', OSError('', 28))),
        'De schijf is vol.',
      );
      expect(
        userFacingError(l10n, FileSystemException('', '', OSError('', 2))),
        'Bestand of map niet gevonden.',
      );
    });

    test('maps an unknown filesystem error code to the generic IO message', () {
      expect(
        userFacingError(l10n, FileSystemException('', '', OSError('', 99))),
        'Kon het bestand niet lezen of schrijven.',
      );
    });

    test('maps network exceptions to the connection message', () {
      for (final e in [
        const SocketException('down'),
        const HttpException('bad'),
        TimeoutException('slow'),
      ]) {
        expect(
          userFacingError(l10n, e),
          'Netwerkfout — controleer je verbinding en probeer het opnieuw.',
        );
      }
    });

    test('delegates WebdavException to the WebDAV mapper', () {
      final e = WebdavException(WebdavError.auth, 'boom');
      expect(userFacingError(l10n, e), webdavErrorMessage(l10n, e));
    });

    test('falls back to the generic message for anything else', () {
      expect(
        userFacingError(l10n, ArgumentError('nope')),
        'Er ging onverwacht iets mis. Kijk in het logboek voor details.',
      );
    });
  });

  group('importFailureMessage', () {
    test('every failure reason maps to a non-empty message, except cancel', () {
      for (final failure in ImportFailure.values) {
        final msg = importFailureMessage(l10n, failure);
        if (failure == ImportFailure.encryptedCancelled) {
          expect(msg, isEmpty, reason: 'cancel is not an error');
        } else {
          expect(msg, isNotEmpty, reason: '$failure should explain itself');
        }
      }
    });
  });

  group('webdavErrorMessage', () {
    test('every WebDAV error kind maps to a non-empty message', () {
      for (final kind in WebdavError.values) {
        expect(
          webdavErrorMessage(l10n, WebdavException(kind, 'x')),
          isNotEmpty,
          reason: '$kind should explain itself',
        );
      }
    });

    test('no two error kinds share a message', () {
      // Een gedeelde melding betekent dat de UI twee oorzaken niet uit elkaar
      // houdt, en dat is precies waar dit stukje over gaat: wie ze weer
      // samenvoegt, plakt de diagnose dicht die de servicelaag al had.
      final byMessage = <String, List<WebdavError>>{};
      for (final kind in WebdavError.values) {
        final msg = webdavErrorMessage(l10n, WebdavException(kind, 'x'));
        byMessage.putIfAbsent(msg, () => []).add(kind);
      }
      final shared = byMessage.values.where((k) => k.length > 1).toList();
      expect(shared, isEmpty, reason: 'delen dezelfde melding: $shared');
    });

    test('an unknown host is not blamed on the trusted-internal setting', () {
      // De oude tekst stuurde bij een tikfout in de hostnaam aan op het
      // omzetten van een veiligheidsvink. Dat loste niets op en verzwakte de
      // instelling: het advies hoort alleen bij een écht privé-adres.
      final unknown = webdavErrorMessage(
        l10n,
        WebdavException(WebdavError.unknownHost, 'x'),
      );
      expect(unknown, contains('typefout'));
      expect(unknown, isNot(contains('vertrouwd')));

      final blocked = webdavErrorMessage(
        l10n,
        WebdavException(WebdavError.blockedHost, 'x'),
      );
      expect(blocked, contains('vertrouwd intern'));
    });

    test('the auth message carries the Nextcloud app-password tip', () {
      final msg = webdavErrorMessage(
        l10n,
        WebdavException(WebdavError.auth, 'x'),
      );
      expect(msg, contains('app-wachtwoord'));
    });
  });
}
