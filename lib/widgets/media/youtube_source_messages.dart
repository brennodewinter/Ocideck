import '../../l10n/app_localizations.dart';
import '../../services/media/timed_captions.dart';
import '../../services/media/youtube_source_client.dart';
import '../../services/transcription/transcription_errors.dart';
import '../../utils/user_facing_error.dart';

String youtubeSourceError(AppLocalizations l10n, Object error) {
  if (error is ServerRefused) {
    return l10n.d('De server is niet bereikbaar of weigerde de verbinding.');
  }
  if (error is UnsupportedSource) {
    return l10n
        .d('Dit formaat kan niet op dit apparaat: {reden}')
        .replaceAll('{reden}', error.message);
  }
  if (error is CaptionParseException || error is SourceUnavailable) {
    return l10n.d(
      'Geen bruikbare ondertitels beschikbaar. Kies audio of importeer een bestand.',
    );
  }
  if (error is CapacityExceeded) {
    return l10n.d('Het bestand is te groot of er is te weinig geheugen vrij.');
  }
  if (error is! YoutubeSourceException) return userFacingError(l10n, error);
  return switch (error.failure) {
    YoutubeSourceFailure.configuration || YoutubeSourceFailure.consent =>
      l10n.d('Kies een HTTPS-bronserver of een server op dit apparaat.'),
    YoutubeSourceFailure.protocol => l10n.d(
      'De bronserver gebruikt een niet-ondersteund protocol.',
    ),
    YoutubeSourceFailure.live => l10n.d(
      'Deze bron is nog live of niet afgerond.',
    ),
    YoutubeSourceFailure.access => l10n.d(
      'Deze video is privé, verwijderd of vereist toegang.',
    ),
    YoutubeSourceFailure.rateLimited => l10n.d(
      'YouTube beperkt het aantal verzoeken. Probeer later opnieuw.',
    ),
    YoutubeSourceFailure.busy => l10n.d(
      'De bronserver is bezig. Probeer later opnieuw.',
    ),
    YoutubeSourceFailure.audioMissing => l10n.d(
      'Deze video heeft geen bruikbare audiotrack.',
    ),
    YoutubeSourceFailure.missingHelper => l10n.d(
      'De bronserver mist de vereiste bronhelper.',
    ),
    YoutubeSourceFailure.tooLarge => l10n.d(
      'Het bestand is te groot of er is te weinig geheugen vrij.',
    ),
    YoutubeSourceFailure.captionsMissing => l10n.d(
      'Geen bruikbare ondertitels beschikbaar. Kies audio of importeer een bestand.',
    ),
    YoutubeSourceFailure.cancelled => l10n.t('cancel'),
    _ => l10n.d(
      'De bronserver is niet bereikbaar. Controleer adres, TLS en browsertoegang.',
    ),
  };
}
