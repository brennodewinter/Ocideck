import 'dart:async';
import 'dart:io';

import '../l10n/app_localizations.dart';
import '../services/file_service.dart';
import '../services/webdav_service.dart';

/// Vertaal een gevangen [error] naar een korte melding met
/// handelingsperspectief voor in een SnackBar of dialoog. De technische
/// details horen in het log (logError/logWarning), niet bij de gebruiker.
String userFacingError(AppLocalizations l10n, Object error) {
  if (error is WebdavException) return webdavErrorMessage(l10n, error);
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    // EPERM(1) / EACCES(13): geen rechten; ENOENT(2): weg; ENOSPC(28): vol.
    if (code == 1 || code == 13) {
      return l10n.d(
        'Geen schrijfrechten op deze locatie. Kies een andere map.',
      );
    }
    if (code == 28) return l10n.d('De schijf is vol.');
    if (code == 2) return l10n.d('Bestand of map niet gevonden.');
    return l10n.d('Kon het bestand niet lezen of schrijven.');
  }
  if (error is SocketException ||
      error is HttpException ||
      error is TimeoutException) {
    return l10n.d(
      'Netwerkfout — controleer je verbinding en probeer het opnieuw.',
    );
  }
  return l10n.d(
    'Er ging onverwacht iets mis. Kijk in het logboek voor details.',
  );
}

/// Begrijpelijke melding per import-weigerreden, zodat de gebruiker weet of
/// het bestand te groot, kapot, geen presentatie of onbereikbaar was.
String importFailureMessage(AppLocalizations l10n, ImportFailure failure) {
  return switch (failure) {
    ImportFailure.tooLarge => l10n.d(
      'Het bestand is groter dan de toegestane limiet.',
    ),
    ImportFailure.corrupt => l10n.d('Het bestand is beschadigd of onleesbaar.'),
    ImportFailure.unsupported => l10n.d(
      'Dit is geen Marp/OciDeck-presentatie.',
    ),
    ImportFailure.limitExceeded => l10n.d(
      'Import geweigerd: het pakket overschrijdt de veiligheidslimieten.',
    ),
    ImportFailure.network => l10n.d(
      'Kon van deze URL geen presentatie ophalen. Controleer de URL en je verbinding.',
    ),
  };
}

/// Begrijpelijke melding per WebDAV-foutsoort, met bij aanmeldfouten de
/// Nextcloud-tip over app-wachtwoorden (de meest gemaakte instelfout).
String webdavErrorMessage(AppLocalizations l10n, WebdavException e) {
  return switch (e.kind) {
    WebdavError.config => l10n.d(
      'Nextcloud is niet (goed) ingesteld — controleer de servergegevens bij Instellingen → Nextcloud.',
    ),
    WebdavError.blockedHost => l10n.d(
      'Deze server is niet toegestaan. Markeer een privé/LAN-server eerst als vertrouwd bij Instellingen → Nextcloud.',
    ),
    WebdavError.network => l10n.d(
      'Server niet bereikbaar — controleer je verbinding en de server-URL.',
    ),
    WebdavError.auth => l10n.d(
      'Aanmelden mislukt. Controleer gebruikersnaam en wachtwoord; gebruik bij Nextcloud een app-wachtwoord, niet je accountwachtwoord.',
    ),
    WebdavError.notFound => l10n.d(
      'Bestand of map niet gevonden op de server.',
    ),
    WebdavError.tooLarge => l10n.d(
      'Het bestand is groter dan de toegestane limiet.',
    ),
    WebdavError.server => l10n.d(
      'De server gaf een fout. Probeer het later opnieuw.',
    ),
  };
}
