/// L10n-bronzinnen voor fouten van de OpenKAT Rocky-client.
///
/// De client praat in interne codes (`desktop_only`, `HTTP 401`, …); de UI
/// vertaalt die hier naar handelingsperspectief — zie
/// `docs/design/OPENKAT_LIVE_UX.md`.
library;

import '../../models/openkat/openkat_installation.dart';
import 'openkat_rocky_client.dart';

/// Zet een [OpenKatRequestException] of denial-code om naar een NL-bronzin
/// voor `l10n.d(...)`.
String openKatErrorMessage(Object error) {
  if (error is OpenKatRequestException) {
    return _fromException(error);
  }
  return 'De verbinding met OpenKAT is mislukt. Controleer het adres en uw netwerk, en probeer opnieuw.';
}

/// Zet een [OpenKatRockyClient.denialReason]-code om naar een NL-bronzin.
String openKatDenialMessage(String? code) {
  switch (code) {
    case 'desktop_only':
      return 'De OpenKAT-koppeling is alleen beschikbaar in de desktopversie.';
    case 'not_configured':
      return 'Vul een weergavenaam en een adres in.';
    case 'token_missing':
      return 'Er is geen toegangstoken. Plak het token van uw beheerder en probeer opnieuw.';
    case 'https_required':
      return 'Alleen HTTPS is toegestaan, tenzij Eigen netwerk aan staat.';
    default:
      return 'De verbinding met OpenKAT is mislukt. Controleer het adres en uw netwerk, en probeer opnieuw.';
  }
}

String _fromException(OpenKatRequestException e) {
  final status = e.statusCode;
  if (status == 401 || status == 403) {
    return 'OpenKAT weigerde het token. Vraag uw beheerder om een geldig API-token en plak het opnieuw.';
  }
  if (status != null) {
    return 'OpenKAT gaf een onverwacht antwoord ($status). Probeer later opnieuw of vraag uw beheerder om hulp.';
  }
  switch (e.message) {
    case 'desktop_only':
    case 'not_configured':
    case 'token_missing':
    case 'https_required':
      return openKatDenialMessage(e.message);
    case 'timeout':
      return 'OpenKAT reageerde niet op tijd. Controleer of de server bereikbaar is en probeer opnieuw.';
    case 'host refused or unreachable':
      return 'Dit adres is niet bereikbaar. Controleer de spelling van de hostnaam en of u op het juiste netwerk zit.';
    case 'response too large':
      return 'OpenKAT gaf een onverwacht groot antwoord. Probeer later opnieuw of vraag uw beheerder om hulp.';
    case 'network':
      return 'De verbinding met OpenKAT is mislukt. Controleer het adres en uw netwerk, en probeer opnieuw.';
    default:
      if (e.message.startsWith('HTTP ')) {
        final code = int.tryParse(e.message.substring(5));
        if (code == 401 || code == 403) {
          return 'OpenKAT weigerde het token. Vraag uw beheerder om een geldig API-token en plak het opnieuw.';
        }
        if (code != null) {
          return 'OpenKAT gaf een onverwacht antwoord ($code). Probeer later opnieuw of vraag uw beheerder om hulp.';
        }
      }
      return 'De verbinding met OpenKAT is mislukt. Controleer het adres en uw netwerk, en probeer opnieuw.';
  }
}

/// Statuslabel voor een installatiekaart.
String openKatStatusLabel(OpenKatInstallationStatus status) {
  switch (status) {
    case OpenKatInstallationStatus.connected:
      return 'Verbonden';
    case OpenKatInstallationStatus.tokenMissing:
      return 'Token ontbreekt';
    case OpenKatInstallationStatus.failed:
      return 'Laatst gecontroleerd mislukt';
    case OpenKatInstallationStatus.unchecked:
      return 'Nog niet gecontroleerd';
  }
}
