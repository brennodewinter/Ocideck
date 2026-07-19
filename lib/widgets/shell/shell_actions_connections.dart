// Part of the app_shell library — see ../app_shell.dart.
//
// Welke bestandsverbinding voert een handeling uit?
//
// Apart gezet omdat het één vraag is die overal terugkomt, en omdat het antwoord
// een regel bevat die je op elke aanroepplek opnieuw fout zou kunnen doen: bij
// precies één bruikbare verbinding wordt er níets gevraagd. Wie één server heeft
// — de meeste mensen — houdt daardoor exact de flow van vroeger, en de vraag
// verschijnt pas wanneer het een echte vraag is.
//
// Deck-gebonden handelingen komen hier niet langs. Die volgen de herkomst van
// het geopende deck (`AppSettings.gitConnectionFor`, `WebdavOrigin.connectionId`),
// want die weet al bij welke opdrachtgever het werk hoort — en een keuzedialoog
// zou de gebruiker de kans geven daar per ongeluk van af te wijken.
part of '../app_shell.dart';

/// Laat de gebruiker een git-verbinding kiezen. Bij één verbinding gebeurt dat
/// zonder dialoog; bij geen enkele volgt de melding dat er niets staat
/// ingesteld.
Future<GitConnection?> _pickGitConnection(
  BuildContext context,
  WidgetRef ref,
) async {
  final connections = ref.read(gitConnectionsProvider);
  if (connections.isEmpty) {
    _gitNotConfigured(context);
    return null;
  }
  return StorageConnectionPicker.show(context, connections);
}

void _gitNotConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'Stel eerst een git-repository in bij Instellingen → Opslag.',
        ),
      ),
    ),
  );
}

/// Laat de gebruiker een WebDAV-verbinding kiezen. Bij één verbinding gebeurt
/// dat zonder dialoog; bij geen enkele volgt de melding dat er niets staat
/// ingesteld.
Future<WebdavConnection?> _pickWebdavConnection(
  BuildContext context,
  WidgetRef ref,
) async {
  final connections = ref.read(webdavConnectionsProvider);
  if (connections.isEmpty) {
    _webdavNotConfigured(context);
    return null;
  }
  return StorageConnectionPicker.show(context, connections);
}

void _webdavNotConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'Stel eerst een WebDAV-server in bij Instellingen → Opslag.',
        ),
      ),
    ),
  );
}
