import 'dart:async';
import 'dart:io';

import '../l10n/app_localizations.dart';
import '../services/file_service.dart';
import '../services/s3/s3_service.dart';
import '../services/webdav_service.dart';

/// Vertaal een gevangen [error] naar een korte melding met
/// handelingsperspectief voor in een SnackBar of dialoog. De technische
/// details horen in het log (logError/logWarning), niet bij de gebruiker.
String userFacingError(AppLocalizations l10n, Object error) {
  if (error is WebdavException) return webdavErrorMessage(l10n, error);
  if (error is S3Exception) return s3ErrorMessage(l10n, error);
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
    ImportFailure.needsPassword => l10n.d(
      'Dit pakket is versleuteld; er kon niet om een wachtwoord worden gevraagd.',
    ),
    // Afbreken is geen fout; de aanroepers vangen dit al af vóór deze melding.
    ImportFailure.encryptedCancelled => '',
  };
}

/// Begrijpelijke melding per WebDAV-foutsoort, met bij aanmeldfouten de
/// Nextcloud-tip over app-wachtwoorden (de meest gemaakte instelfout). Die tip
/// staat er voorwaardelijk ("bij Nextcloud") in: deze meldingen komen uit de
/// laag die het servertype niet kent, en voor een andere server is het advies
/// niet fout maar niet van toepassing.
String webdavErrorMessage(AppLocalizations l10n, WebdavException e) {
  return switch (e.kind) {
    WebdavError.config => l10n.d(
      'WebDAV is niet (goed) ingesteld — controleer de servergegevens bij Instellingen → WebDAV.',
    ),
    WebdavError.unknownHost => l10n.d(
      'De servernaam bestaat niet, of is niet op te zoeken. Controleer de server-URL op een typefout.',
    ),
    WebdavError.blockedHost => l10n.d(
      'Deze server heeft een privé- of LAN-adres. Markeer hem als vertrouwd intern bij Instellingen → Opslag.',
    ),
    WebdavError.tls => l10n.d(
      'Het certificaat van deze server wordt niet vertrouwd. Een zelfondertekend certificaat werkt niet; gebruik er een van een erkende uitgever.',
    ),
    WebdavError.redirect => l10n.d(
      'De server stuurt door naar een ander adres. Vul dat adres rechtstreeks in — een omleiding volgen we niet, want die kan de veiligheidscontrole omzeilen.',
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

/// Begrijpelijke melding per S3-foutsoort. Twee ervan verwijzen naar een knop
/// in de instellingen, omdat dat in de praktijk de oorzaak is: een 404 op een
/// bucket die zeker bestaat komt vrijwel altijd door de adressering, en een
/// geweigerde privé-host door de ontbrekende "vertrouwd intern"-vink.
String s3ErrorMessage(AppLocalizations l10n, S3Exception e) {
  return switch (e.kind) {
    S3Error.config => l10n.d(
      'De S3-bucket is niet (goed) ingesteld — controleer endpoint, bucket en sleutels bij Instellingen → Opslag.',
    ),
    S3Error.unknownHost => l10n.d(
      'De endpoint-naam bestaat niet, of is niet op te zoeken. Controleer het endpoint op een typefout.',
    ),
    S3Error.blockedHost => l10n.d(
      'Dit endpoint is niet toegestaan. Markeer een privé/LAN-endpoint eerst als vertrouwd bij Instellingen → Opslag.',
    ),
    S3Error.network => l10n.d(
      'Endpoint niet bereikbaar — controleer je verbinding en het endpoint.',
    ),
    S3Error.auth => l10n.d(
      'Aanmelden mislukt. Controleer de access key, de secret key en de regio — een verkeerde regio geeft dezelfde fout als een verkeerde sleutel.',
    ),
    S3Error.notFound => l10n.d(
      'Niet gevonden in de bucket. Klopt de bucketnaam, probeer dan de andere adressering bij Instellingen → Opslag.',
    ),
    S3Error.tooLarge => l10n.d(
      'Het bestand is groter dan de toegestane limiet.',
    ),
    S3Error.conditionalUnsupported => l10n.d(
      'Dit endpoint kan niet voorwaardelijk schrijven, dus je werk is niet beschermd tegen dat van een ander. Sla op onder een nieuwe naam als er iemand anders aan dit deck werkt.',
    ),
    S3Error.server => l10n.d(
      'Het endpoint gaf een fout. Probeer het later opnieuw.',
    ),
  };
}
