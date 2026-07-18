import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/git_settings.dart';
import '../platform/platform_features.dart';
import '../services/git/deck_mirror.dart';
import '../services/git/git_cli.dart';
import '../services/git/git_cli_factory.dart';
import '../services/git/git_forge.dart';
import '../services/git/gitea_forge.dart';
import '../services/git/github_forge.dart';
import '../services/git/gitlab_forge.dart';
import '../services/git/native_git_mirror_api.dart';
import '../services/git/native_git_mirror_factory.dart';
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
      final forge = GitHubForge(config: config, token: token);
      ref.onDispose(forge.close);
      return forge;
    case GitProvider.gitlab:
      final forge = GitLabForge(config: config, token: token);
      ref.onDispose(forge.close);
      return forge;
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

/// De native werkkopie: een échte clone met echte historie (§8.2), of `null`
/// wanneer die er niet kan zijn — geen bruikbaar git, geen ingestelde repo, of
/// web. Dan valt de app terug op [draftMirrorProvider] + de REST-SyncEngine.
///
/// Wordt herbouwd zodra de git-config wijzigt; de probe erachter draait maar
/// één keer (zie [nativeGitVersionProvider]).
final nativeGitMirrorProvider = FutureProvider<NativeGitMirror?>((ref) async {
  final version = await ref.watch(nativeGitVersionProvider.future);
  if (version == null) return null;
  final config = ref.watch(settingsProvider).gitRepo;
  if (config == null || !config.isConfigured) return null;
  final token =
      await ref
          .read(settingsProvider.notifier)
          .readGitToken(config.baseUrl, config.owner) ??
      '';
  return createNativeGitMirror(
    git: ref.watch(gitCliProvider),
    config: config,
    token: token,
  );
});

/// De werkkopie waar een offline REST-opslag naartoe schrijft (§8.1) — op web en
/// op desktop-zonder-git. Levenslang, want hij houdt geen dure staat vast.
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

/// De release-tags van één deck (§9.4), nieuwste bovenaan. `autoDispose` zodat
/// een gesloten versiekiezer de cache niet vasthoudt.
final gitDeckTagsProvider = FutureProvider.autoDispose
    .family<List<TagRef>, String>((ref, deckName) async {
      final forge = await ref.watch(gitForgeProvider.future);
      if (forge == null) {
        throw const GitForgeException(
          GitForgeError.config,
          'Geen git-repository ingesteld',
        );
      }
      final mine = [
        for (final tag in await forge.listTags())
          if (GitRepoLayout.isReleaseTagFor(tag.name, deckName)) tag,
      ]..sort((a, b) => b.name.compareTo(a.name));
      return mine;
    });
