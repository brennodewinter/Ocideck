import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/git_settings.dart';
import '../platform/platform_features.dart';
import '../services/git/deck_mirror.dart';
import '../services/git/git_cli.dart';
import '../services/git/git_cli_factory.dart';
import '../services/git/git_forge.dart';
import '../services/git/gitea_forge.dart';
import '../services/git/outbox.dart';
import '../services/git/sync_engine.dart';
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

/// De gehardde git-uitvoerder (§10.2). Eén per proces; op web een stub die
/// [GitCli.isSupported] `false` meldt.
final gitCliProvider = Provider<GitCli>((ref) => createGitCli());

/// De versie van bruikbaar native `git`, of null wanneer het er niet is (web,
/// mobiel, git ontbreekt, te oud, of — op macOS — de Xcode-tools ontbreken,
/// §8.4). Draait de probe één keer en onthoudt het uitkomst voor de rest van het
/// proces.
///
/// **Lui**: een `FutureProvider` rekent pas wanneer iets hem leest, en dat mag
/// hier alléén gebeuren als de gebruiker een git-repo aanraakt — nooit bij het
/// opstarten (§8.4: de macOS-shim zou anders een installatiedialoog kunnen
/// openen). De goedkope [supportsNativeGit]-poort kort dat bovendien af vóór er
/// ook maar een proces start.
final nativeGitVersionProvider = FutureProvider<GitVersion?>((ref) async {
  if (!supportsNativeGit) return null;
  return ref.watch(gitCliProvider).probe();
});

/// De werkkopie waar een offline opslag naartoe schrijft (§8.1). Op web en op
/// desktop-zonder-git is dit een [DraftMirror]; de native clone (Fase 3) komt
/// later. Levenslang, want hij houdt geen dure staat vast.
final draftMirrorProvider = Provider<DeckMirror>((ref) => DraftMirror());

/// De duurzame wachtrij van nog niet gepushte decks (§8.5). Overleeft het
/// afsluiten: hij zit in de sleutel/waarde-opslag.
final outboxProvider = Provider<Outbox>((ref) => Outbox());

/// Verzoent de werkkopie met de forge (§8): maakt commits van wat wacht zodra
/// dat kan. `null` wanneer er geen repo is ingesteld — dan is er niets te
/// synchroniseren. Herbouwd zodra de forge-config wijzigt.
final syncEngineProvider = FutureProvider<SyncEngine?>((ref) async {
  final forge = await ref.watch(gitForgeProvider.future);
  if (forge == null) return null;
  return SyncEngine(
    forge: forge,
    mirror: ref.watch(draftMirrorProvider),
    outbox: ref.watch(outboxProvider),
  );
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
