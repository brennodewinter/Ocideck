import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/webdav_service.dart';
import 'settings_provider.dart';

/// Bouwt een [WebdavService] uit de geconfigureerde server plus het wachtwoord
/// uit de keychain. Geeft `null` wanneer geen server is ingesteld of er nog
/// geen wachtwoord is opgeslagen. Wordt herbouwd zodra de serverconfig wijzigt.
final webdavServiceProvider = FutureProvider<WebdavService?>((ref) async {
  final server = ref.watch(settingsProvider).webdavServer;
  if (server == null || !server.isConfigured) return null;
  final password = await ref
      .read(settingsProvider.notifier)
      .readWebdavPassword(server.baseUrl, server.username);
  if (password == null || password.isEmpty) return null;
  return WebdavService(server: server, password: password);
});

/// Listing van één map (pad relatief aan de wortel) voor de browser-dialog.
/// `autoDispose` zodat een gesloten dialog de cache niet vasthoudt.
final webdavListingProvider = FutureProvider.autoDispose
    .family<List<WebdavEntry>, String>((ref, remotePath) async {
      final service = await ref.watch(webdavServiceProvider.future);
      if (service == null) {
        throw WebdavException(
          WebdavError.config,
          'Geen WebDAV-server ingesteld',
        );
      }
      return service.list(remotePath);
    });
