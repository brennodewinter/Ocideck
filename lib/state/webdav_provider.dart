import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/storage_connection.dart';
import '../services/webdav_service.dart';
import 'settings_provider.dart';

/// Bouwt een [WebdavService] voor één WebDAV-verbinding: de opgeslagen
/// serverconfiguratie plus het wachtwoord uit de keychain. Geeft `null` wanneer
/// de verbinding niet (meer) bestaat, half is ingevuld, of er nog geen
/// wachtwoord is opgeslagen. Wordt herbouwd zodra de configuratie wijzigt.
///
/// Gekeyd op verbindings-id en niet op de server zelf: de id blijft gelijk als
/// de gebruiker de server-URL corrigeert, zodat een geopend deck zijn bron niet
/// kwijtraakt bij een typefout die wordt hersteld.
final webdavServiceProvider = FutureProvider.family<WebdavService?, String>((
  ref,
  connectionId,
) async {
  final connection = ref.watch(settingsProvider).connectionById(connectionId);
  if (connection is! WebdavConnection || !connection.isConfigured) return null;
  final server = connection.server;
  final password = await ref
      .read(settingsProvider.notifier)
      .readWebdavPassword(server.baseUrl, server.username);
  if (password == null || password.isEmpty) return null;
  return WebdavService(server: server, password: password);
});

/// De verbinding waarmee de app werkt als de gebruiker niet is gevraagd te
/// kiezen: de bovenste bruikbare WebDAV-verbinding, of `null`.
final primaryWebdavConnectionProvider = Provider<WebdavConnection?>(
  (ref) =>
      ref.watch(settingsProvider).primaryOf(StorageConnectionKind.webdav)
          as WebdavConnection?,
);

/// Alle bruikbare WebDAV-verbindingen, in de volgorde die de gebruiker sleepte
/// — de lijst die de keuzedialoog toont.
final webdavConnectionsProvider = Provider<List<WebdavConnection>>(
  (ref) => ref.watch(settingsProvider).connectionsOf<WebdavConnection>(),
);

/// Listing van één map (pad relatief aan de wortel) voor de browser-dialog.
/// `autoDispose` zodat een gesloten dialog de cache niet vasthoudt.
///
/// De sleutel draagt de verbinding mee: twee servers met dezelfde mapnaam
/// leverden anders elkaars inhoud op uit de cache.
typedef WebdavListingKey = ({String connectionId, String remotePath});

final webdavListingProvider = FutureProvider.autoDispose
    .family<List<WebdavEntry>, WebdavListingKey>((ref, key) async {
      final service = await ref.watch(
        webdavServiceProvider(key.connectionId).future,
      );
      if (service == null) {
        throw WebdavException(
          WebdavError.config,
          'Geen WebDAV-server ingesteld',
        );
      }
      return service.list(key.remotePath);
    });
