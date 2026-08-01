import 'dart:async';
import 'dart:io';

import '../l10n/app_localizations.dart';
import '../services/file_service.dart';
import '../services/git/git_forge.dart';
// Geprefixt: `file_service.dart` heeft óók een `ImportFailure` (de enum voor de
// pakket-import), en dat is een ander type dan deze klasse voor de
// presentatie-import.
import '../services/import/importers/import_failure.dart' as pres;
import '../services/s3/s3_service.dart';
import '../services/webdav_service.dart';
import '../services/web_asset_store.dart';

/// Vertaal een gevangen [error] naar een korte melding met
/// handelingsperspectief voor in een SnackBar of dialoog. De technische
/// details horen in het log (logError/logWarning), niet bij de gebruiker.
String userFacingError(AppLocalizations l10n, Object error) {
  if (error is WebAssetBudgetExceeded) return webAssetBudgetMessage(l10n);
  if (error is WebdavException) return webdavErrorMessage(l10n, error);
  if (error is S3Exception) return s3ErrorMessage(l10n, error);
  if (error is GitForgeException) return gitForgeErrorMessage(l10n, error);
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

/// Handelingsperspectief bij het appbrede webassetbudget. Eerst veiligstellen:
/// herladen maakt wel geheugen vrij, maar wist ook alle niet-opgeslagen media.
String webAssetBudgetMessage(AppLocalizations l10n) => l10n.d(
  'Het webgeheugen voor presentatiemedia is vol (maximaal 256 MB). Sla je werk eerst op als .ocideck om verlies te voorkomen. Gebruik daarna minder of kleinere afbeeldingen, video’s of audiobestanden, sluit andere decks of herlaad zonder andere decks te openen.',
);

/// Begrijpelijke melding waarom een presentatie-import (pptx/odp/key) mislukte.
///
/// De servicelaag draagt een [ImportFailureReason] plus [ImportFailure.args];
/// de tekst wordt hier gekozen en vertaald. De ruwe [ImportFailure.message] is
/// een technische Nederlandse string die in het log hoort, niet op het scherm —
/// zonder deze functie las een Franse gebruiker "dit bestand is geen herkende
/// presentatie" in het Nederlands (#806). Zelfde afspraak als
/// [webdavErrorMessage], [s3ErrorMessage] en [gitForgeErrorMessage].
///
/// De `{naam}`-plaatshouders worden ná het vertalen ingevuld, zodat elke taal
/// zelf bepaalt waar de bestandsnaam en het formaat in de zin landen.
String importFailureText(AppLocalizations l10n, pres.ImportFailure failure) {
  String fill(String template) {
    var out = template;
    failure.args.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  // Elke bronstring op één regel, niet met aangrenzende literals opgebroken:
  // Dart voegt die vóór de aanroep samen, dus `l10n.d` krijgt de hele string —
  // maar de vertaalpoort (`app_localizations_test`) leest per `.d(` maar één
  // literal en zou anders alleen het eerste stuk bewaken. Eén regel houdt
  // sleutel, runtime en poort gelijk.
  return switch (failure.reason) {
    pres.ImportFailureReason.tooLarge => fill(
      l10n.d(
        '{bestand} is groter dan de limiet van {limiet} en wordt niet geïmporteerd.',
      ),
    ),
    pres.ImportFailureReason.memoryBudgetExceeded => webAssetBudgetMessage(
      l10n,
    ),
    pres.ImportFailureReason.notAPresentation => fill(
      l10n.d(
        '{bestand} is geen herkende presentatie. OciDeck leest PowerPoint (.pptx), OpenDocument (.odp) en Keynote (.key).',
      ),
    ),
    pres.ImportFailureReason.corrupt => fill(
      l10n.d(
        '{bestand} lijkt beschadigd: het archief kan niet volledig worden uitgepakt.',
      ),
    ),
    pres.ImportFailureReason.formatNotSupported => fill(
      l10n.d('Het {formaat}-formaat wordt nog niet ondersteund ({bestand}).'),
    ),
    pres.ImportFailureReason.noSlides => fill(
      l10n.d(
        'Geen dia’s gevonden in {bestand} — is dit een geldig {formaat}-bestand?',
      ),
    ),
    pres.ImportFailureReason.unreadable => fill(
      l10n.d('Kon {bestand} niet lezen als {formaat}-presentatie.'),
    ),
    pres.ImportFailureReason.unsafeContent => fill(
      l10n.d('{bestand} bevat uitvoerbare inhoud en wordt niet geïmporteerd.'),
    ),
    // Geen bekende importreden. Draagt de fout een gevangen exception (een
    // schrijffout uit de bulk-rij: volle schijf, geen rechten), benoem die dan
    // netjes; anders een generieke melding.
    pres.ImportFailureReason.other =>
      failure.cause != null
          ? userFacingError(l10n, failure.cause!)
          : l10n.d('Importeren mislukt.'),
  };
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
      'WebDAV is niet (goed) ingesteld — controleer de servergegevens bij Instellingen → Opslag.',
    ),
    WebdavError.unknownHost => l10n.d(
      'De servernaam bestaat niet, of is niet op te zoeken. Controleer de server-URL op een typefout.',
    ),
    WebdavError.blockedHost => l10n.d(
      'Deze server heeft een privé- of LAN-adres. Markeer hem als vertrouwd intern bij Instellingen → Opslag.',
    ),
    WebdavError.tls => l10n.d(
      'Het certificaat van deze server wordt niet vertrouwd. Bij een zelf gehoste server kun je het bekijken en vertrouwen bij Instellingen → Opslag.',
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
    WebdavError.forbidden => l10n.d(
      'Je bent aangemeld, maar hebt hier geen toegang. Je wachtwoord is niet het probleem — vraag de beheerder om rechten op deze map.',
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

/// Begrijpelijke melding per git-forge-foutsoort.
///
/// Kwam er niet eerder, en dat was te merken: `GitForgeException` viel door
/// [userFacingError] heen naar "er ging onverwacht iets mis", en de schermen
/// die hem wél apart afvingen toonden `e.message` rechtstreeks. Die tekst is
/// door de servicelaag samengesteld en gaat nooit door `l10n.d()`, dus een
/// Engelstalige gebruiker las Nederlands — en bij een onbekende status stond er
/// letterlijk "Onverwachte status 418".
///
/// De ruwe [GitForgeException.message] blijft bestaan en hoort in het logboek:
/// daar wil je juist die 418 zien. Dit is de laag ervoor. Zelfde afspraak als
/// bij [webdavErrorMessage] en [s3ErrorMessage].
String gitForgeErrorMessage(AppLocalizations l10n, GitForgeException e) {
  return switch (e.kind) {
    GitForgeError.config => l10n.d(
      'De git-repository is niet (goed) ingesteld — controleer server, eigenaar en repository bij Instellingen → Opslag.',
    ),
    GitForgeError.unknownHost => l10n.d(
      'De servernaam van de forge bestaat niet, of is niet op te zoeken. Controleer de server-URL op een typefout.',
    ),
    GitForgeError.blockedHost => l10n.d(
      'Deze forge heeft een privé- of LAN-adres. Markeer hem als vertrouwd intern bij Instellingen → Opslag.',
    ),
    GitForgeError.tls => l10n.d(
      'Het certificaat van de forge wordt niet vertrouwd. Bij een zelf gehoste forge kun je het bekijken en vertrouwen bij Instellingen → Opslag.',
    ),
    GitForgeError.network => l10n.d(
      'De forge is niet bereikbaar — controleer je verbinding en de server-URL.',
    ),
    GitForgeError.auth => l10n.d(
      'Aanmelden bij de forge mislukt. Controleer je token: het heeft leesrechten op de repository nodig, en schrijfrechten om op te slaan.',
    ),
    // De forge geeft ook 404 wanneer het token de repo niet mag zien: hij
    // verraadt liever niet dát hij bestaat. De melding mag dat niet als
    // zekerheid presenteren.
    GitForgeError.forbidden => l10n.d(
      'Je token is geldig, maar mag dit niet. Geef het meer rechten, of wacht als de forge een limiet oplegt.',
    ),
    GitForgeError.notFound => l10n.d(
      'Niet gevonden in de repository — of je token mag het niet zien.',
    ),
    GitForgeError.tooLarge => l10n.d(
      'Het bestand is groter dan de toegestane limiet.',
    ),
    GitForgeError.server => l10n.d(
      'De forge gaf een fout. Probeer het later opnieuw.',
    ),
    GitForgeError.malformed => l10n.d(
      'Dit adres antwoordt niet als een forge. Klopt de soort forge bij Instellingen → Opslag?',
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
    S3Error.tls => l10n.d(
      'Het certificaat van het endpoint wordt niet vertrouwd. Bij een zelf gehost endpoint kun je het bekijken en vertrouwen bij Instellingen → Opslag.',
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
