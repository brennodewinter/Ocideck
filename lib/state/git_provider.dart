import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/git_settings.dart';
import '../services/git/git_forge.dart';
import '../services/git/gitea_forge.dart';
import 'settings_provider.dart';

/// Bouwt de forge-adapter uit de geconfigureerde repo plus het token uit de
/// keychain. Geeft `null` wanneer er geen repo is ingesteld. Wordt herbouwd
/// zodra de config wijzigt. Spiegelt `webdavServiceProvider`.
///
/// Een leeg token is géén reden om null te geven — anders dan bij WebDAV, want
/// een publieke repo lezen mag zonder.
final gitForgeProvider = FutureProvider<GitForge?>((ref) async {
  final config = ref.watch(settingsProvider).gitRepo;
  if (config == null || !config.isConfigured) return null;
  final token =
      await ref
          .read(settingsProvider.notifier)
          .readGitToken(config.baseUrl, config.owner) ??
      '';

  switch (config.provider) {
    case GitProvider.gitea:
      final forge = GiteaForge(config: config, token: token);
      ref.onDispose(forge.close);
      return forge;
    case GitProvider.github:
    case GitProvider.gitlab:
      // Fase 5. Tot dan is null eerlijker dan een adapter die bij de eerste
      // aanroep omvalt; de UI biedt ze niet aan.
      return null;
  }
});

/// De deckmappen op [branch], als deknaam → pad. `autoDispose` zodat een
/// gesloten dialoog de cache niet vasthoudt.
final gitDeckListProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, branch) async {
      final forge = await ref.watch(gitForgeProvider.future);
      if (forge == null) {
        throw const GitForgeException(
          GitForgeError.config,
          'Geen git-repository ingesteld',
        );
      }
      return forge.listDecks(branch);
    });
