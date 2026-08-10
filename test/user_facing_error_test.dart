import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/git/git_forge.dart';
// Geprefixt: `file_service.dart` heeft óók een `ImportFailure` (de enum voor de
// pakket-import); dit is de klasse voor de presentatie-import.
import 'package:ocideck/services/import/importers/import_failure.dart' as pres;
import 'package:ocideck/services/s3/s3_service.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/utils/user_facing_error.dart';

/// Tests the caught-error → user-message mapping. With the active language set
/// to Dutch, `l10n.d(...)` returns its source string verbatim, so we can assert
/// the exact message each branch produces.
void main() {
  const l10n = AppLocalizations(Locale('nl'));
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('userFacingError', () {
    test('webassetbudget benoemt alle media en veiligstellen eerst', () {
      final message = webAssetBudgetMessage(l10n);
      expect(message, contains('presentatiemedia'));
      expect(message, contains('afbeeldingen'));
      expect(message, contains('video'));
      expect(message, contains('audio'));
      expect(
        message.indexOf('Sla je werk eerst op'),
        lessThan(message.indexOf('sluit andere decks')),
      );
    });

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

    test('no two failure kinds share a message', () {
      // Een gedeelde melding betekent dat de UI twee oorzaken niet uit elkaar
      // houdt — precies wat de reden-splitsing van de URL-import (blocked host,
      // DNS-tikfout, 404, TLS, omleiding, geen https) wil voorkomen. De lege
      // cancel-melding telt niet mee: dat is geen fout maar bewuste stilte.
      final byMessage = <String, List<ImportFailure>>{};
      for (final kind in ImportFailure.values) {
        final msg = importFailureMessage(l10n, kind);
        if (msg.isEmpty) continue; // encryptedCancelled is opzettelijk stil
        byMessage.putIfAbsent(msg, () => []).add(kind);
      }
      final shared = byMessage.values.where((k) => k.length > 1).toList();
      expect(shared, isEmpty, reason: 'delen dezelfde melding: $shared');
    });
  });

  group('importFailureText (presentatie-import, #806)', () {
    pres.ImportFailure failure(
      pres.ImportFailureReason reason, {
      Map<String, String> args = const {},
      Object? cause,
    }) => pres.ImportFailure('tech', reason: reason, args: args, cause: cause);

    test('elke reden geeft een niet-lege melding', () {
      for (final reason in pres.ImportFailureReason.values) {
        expect(
          importFailureText(l10n, failure(reason)),
          isNotEmpty,
          reason: '$reason hoort zichzelf uit te leggen',
        );
      }
    });

    test('de plaatshouders worden met de args ingevuld', () {
      final text = importFailureText(
        l10n,
        failure(
          pres.ImportFailureReason.noSlides,
          args: {'bestand': 'werk.pptx', 'formaat': 'pptx'},
        ),
      );
      expect(text, contains('werk.pptx'));
      expect(text, contains('pptx'));
      expect(text, isNot(contains('{bestand}')));
      expect(text, isNot(contains('{formaat}')));
    });

    test('de ruwe technische message komt nooit op het scherm', () {
      // `message` is voor het log; de gebruiker krijgt de vertaalde tekst.
      final text = importFailureText(
        l10n,
        pres.ImportFailure(
          'RUWE TECHNISCHE TEKST',
          reason: pres.ImportFailureReason.corrupt,
          args: const {'bestand': 'x.odp'},
        ),
      );
      expect(text, isNot(contains('RUWE TECHNISCHE TEKST')));
      expect(text, contains('x.odp'));
    });

    test('een other-fout met een exception valt terug op userFacingError', () {
      // De bulk-rij verpakt een schrijffout als een `other`-fout met de
      // exception in `cause`; die hoort netjes benoemd te worden, niet generiek.
      final text = importFailureText(
        l10n,
        failure(
          pres.ImportFailureReason.other,
          cause: FileSystemException('', '', const OSError('', 28)),
        ),
      );
      expect(text, 'De schijf is vol.');
    });

    test('een other-fout zonder cause is de generieke melding', () {
      expect(
        importFailureText(l10n, failure(pres.ImportFailureReason.other)),
        'Importeren mislukt.',
      );
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

  group('gitForgeErrorMessage', () {
    test('every git error kind maps to a non-empty message', () {
      for (final kind in GitForgeError.values) {
        expect(
          gitForgeErrorMessage(l10n, GitForgeException(kind, 'x')),
          isNotEmpty,
          reason: '$kind should explain itself',
        );
      }
    });

    test('no two error kinds share a message', () {
      final byMessage = <String, List<GitForgeError>>{};
      for (final kind in GitForgeError.values) {
        final msg = gitForgeErrorMessage(l10n, GitForgeException(kind, 'x'));
        byMessage.putIfAbsent(msg, () => []).add(kind);
      }
      final shared = byMessage.values.where((k) => k.length > 1).toList();
      expect(shared, isEmpty, reason: 'delen dezelfde melding: $shared');
    });

    test('a 404 does not promise the repository is absent', () {
      // Een forge geeft ook 404 wanneer het token de repo niet mag zien. De
      // melding mag dat niet als zekerheid presenteren — de gebruiker zou
      // anders naar een repo gaan zoeken die er gewoon is.
      final msg = gitForgeErrorMessage(
        l10n,
        const GitForgeException(GitForgeError.notFound, 'x'),
      );
      expect(msg, contains('token'));
    });
  });

  group('s3ErrorMessage', () {
    test('every S3 error kind maps to a non-empty message', () {
      for (final kind in S3Error.values) {
        expect(
          s3ErrorMessage(l10n, S3Exception(kind, 'x')),
          isNotEmpty,
          reason: '$kind should explain itself',
        );
      }
    });

    test('no two error kinds share a message', () {
      final byMessage = <String, List<S3Error>>{};
      for (final kind in S3Error.values) {
        final msg = s3ErrorMessage(l10n, S3Exception(kind, 'x'));
        byMessage.putIfAbsent(msg, () => []).add(kind);
      }
      final shared = byMessage.values.where((k) => k.length > 1).toList();
      expect(shared, isEmpty, reason: 'delen dezelfde melding: $shared');
    });
  });

  group('userFacingError routes every storage exception', () {
    // De aanleiding: GitForgeException stond niet in de dispatch en viel door
    // naar "er ging onverwacht iets mis" — terwijl er een tabel voor bestond.
    // Deze test valt om zodra er een vierde opslagsoort bij komt die vergeten
    // wordt aan te sluiten.
    final generiek = l10n.d(
      'Er ging onverwacht iets mis. Kijk in het logboek voor details.',
    );

    test('a WebDAV, S3 or git exception never falls through to the generic '
        'message', () {
      final gevallen = <Object>[
        WebdavException(WebdavError.auth, 'x'),
        S3Exception(S3Error.auth, 'x'),
        const GitForgeException(GitForgeError.auth, 'x'),
      ];
      for (final e in gevallen) {
        expect(
          userFacingError(l10n, e),
          isNot(generiek),
          reason: '$e hoort een eigen melding te hebben',
        );
      }
    });

    test('the raw service message never reaches the user', () {
      // De ruwe tekst is Nederlands, onvertaald en soms letterlijk
      // "Onverwachte status 418". Die hoort in het logboek, niet op het scherm.
      const ruw = 'Onverwachte status 418';
      expect(
        userFacingError(
          l10n,
          const GitForgeException(GitForgeError.server, ruw),
        ),
        isNot(contains('418')),
      );
    });
  });
}
