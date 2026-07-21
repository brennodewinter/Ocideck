import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/storage_connection.dart';
import '../platform/platform_features.dart';
import '../services/presentation_search/git_presentation_source.dart';
import '../services/presentation_search/presentation_source.dart';
import '../services/presentation_search/remote_presentation_source.dart';
import '../services/presentation_search/storage_file_clients.dart';
import 'deck_provider.dart';
import 'git_provider.dart';
import 's3_provider.dart';
import 'settings_provider.dart';
import 'webdav_provider.dart';

/// Bouw een [PresentationSource] per geconfigureerde remote verbinding: git,
/// WebDAV en S3 — de bronnen die 'Slide zoeken' naast de lokale bibliotheken
/// aftast.
///
/// De clients (met token of wachtwoord uit de keychain) worden hier alvast
/// klaargezet; het netwerkverkeer zelf gebeurt pas in de finder, op de
/// achtergrond. Een verbinding zonder bruikbare client valt weg: half ingevuld
/// of ingetrokken hoort geen lege bron in de lijst op te leveren.
Future<List<PresentationSource>> buildRemotePresentationSources(
  WidgetRef ref,
) async {
  final settings = ref.read(settingsProvider);
  final fileService = ref.read(fileServiceProvider);
  final sources = <PresentationSource>[];

  for (final conn in settings.connectionsOf<GitConnection>()) {
    final forge = await ref.read(gitForgeProvider(conn.id).future);
    if (forge == null) continue;
    final name = conn.name.trim();
    sources.add(
      GitPresentationSource(
        forge: forge,
        config: conn.repo,
        fileService: fileService,
        label: 'Git: ${name.isEmpty ? conn.repo.slug : name}',
      ),
    );
  }

  // WebDAV en S3 leunen op dart:io (socket-pinning); op web bestaan ze niet.
  if (!supportsNetworkDeckSources) return sources;

  for (final conn in settings.connectionsOf<WebdavConnection>()) {
    final service = await ref.read(webdavServiceProvider(conn.id).future);
    if (service == null) continue;
    final name = conn.name.trim();
    sources.add(
      RemotePresentationSource(
        client: WebdavFileClient(service),
        fileService: fileService,
        label: name.isEmpty ? 'WebDAV' : 'WebDAV: $name',
        pathPrefix: 'webdav:${conn.id}',
      ),
    );
  }

  for (final conn in settings.connectionsOf<S3Connection>()) {
    final service = await ref.read(s3ServiceProvider(conn.id).future);
    if (service == null) continue;
    final name = conn.name.trim();
    sources.add(
      RemotePresentationSource(
        client: S3FileClient(service),
        fileService: fileService,
        label: name.isEmpty ? 'S3' : 'S3: $name',
        pathPrefix: 's3:${conn.id}',
      ),
    );
  }

  return sources;
}
