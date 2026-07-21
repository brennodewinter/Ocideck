import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/git_settings.dart';
import '../models/storage_connection.dart';
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
import '../services/git/draft_store_factory.dart';
import '../utils/log.dart';
import 'provider_retry.dart';
import 'settings_provider.dart';

/// Alle bruikbare git-verbindingen, in de volgorde die de gebruiker sleepte —
/// de lijst die de keuzedialoog toont.
final gitConnectionsProvider = Provider<List<GitConnection>>(
  (ref) => ref.watch(settingsProvider).connectionsOf<GitConnection>(),
);

/// De verbinding waarmee de app werkt als er niet is gevraagd te kiezen: de
/// bovenste bruikbare git-verbinding, of `null`.
final primaryGitConnectionProvider = Provider<GitConnection?>(
  (ref) =>
      ref.watch(settingsProvider).primaryOf(StorageConnectionKind.git)
          as GitConnection?,
);

/// De configuratie van één git-verbinding, of `null` als hij niet (meer)
/// bestaat of half is ingevuld.
final gitConfigProvider = Provider.family<GitRepoConfig?, String>((
  ref,
  connectionId,
) {
  final c = ref.watch(settingsProvider).connectionById(connectionId);
  return c is GitConnection && c.isConfigured ? c.repo : null;
});

/// Bouwt de forge-adapter voor één verbinding: de opgeslagen repo plus het
/// token uit de keychain. Geeft `null` wanneer de verbinding niet (meer)
/// bestaat. Wordt herbouwd zodra de config wijzigt. Spiegelt
/// `webdavServiceProvider`, tot en met het keyen op verbindings-id: dat blijft
/// gelijk als de gebruiker een typefout in de URL herstelt.
///
/// Een leeg token is géén reden om null te geven — anders dan bij WebDAV, want
/// een publieke repo lezen mag zonder.
final gitForgeProvider = FutureProvider.family<GitForge?, String>((
  ref,
  connectionId,
) async {
  final config = ref.watch(gitConfigProvider(connectionId));
  if (config == null) return null;
  final token =
      await ref
          .read(settingsProvider.notifier)
          .readGitToken(config.baseUrl, config.owner) ??
      '';

  final forge = createGitForge(config: config, token: token);
  ref.onDispose(forge.close);
  return forge;
});

/// Bouw de adapter die bij [config] hoort.
///
/// Losstaand van [gitForgeProvider] omdat de settings-dialoog een verbinding
/// moet kunnen testen die nog niet is opgeslagen — er is dan geen
/// connectionId om een provider op te draaien. De aanroeper sluit hem zelf.
GitForge createGitForge({
  required GitRepoConfig config,
  required String token,
}) => switch (config.provider) {
  GitProvider.gitea => GiteaForge(config: config, token: token),
  GitProvider.github => GitHubForge(config: config, token: token),
  GitProvider.gitlab => GitLabForge(config: config, token: token),
};

/// Hoeveel decks er over alle git-verbindingen samen nog in een wachtrij
/// staan.
///
/// Werk dat offline is opgeslagen blijft wachten tot er weer verbinding is, en
/// dat is precies het soort ding dat je vergeet. Tot nu toe zag je het alleen
/// wanneer je er zelf naar vroeg — dan stond het er al dagen.
///
/// Ververst niet vanzelf. De wachtrij verandert op precies twee plekken — bij
/// het inschuiven van een opslag en bij het legen — en die roepen daar
/// `invalidate(gitQueueCountProvider)` aan. Een timer zou hetzelfde antwoord
/// telkens opnieuw van schijf lezen; hem vergeten geeft een badge die
/// achterloopt, en dat is erger dan geen badge.
final gitQueueCountProvider = FutureProvider<int>((ref) async {
  final connections = ref
      .watch(settingsProvider)
      .connections
      .whereType<GitConnection>();
  var total = 0;
  for (final connection in connections) {
    final pending = await ref.read(outboxProvider(connection.id)).pending();
    total += pending.length;
  }
  return total;
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
final nativeGitMirrorProvider = FutureProvider.family<NativeGitMirror?, String>(
  (ref, connectionId) async {
    final version = await ref.watch(nativeGitVersionProvider.future);
    if (version == null) return null;
    final config = ref.watch(gitConfigProvider(connectionId));
    if (config == null) return null;
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
  },
);

/// De opslagsleutel van één verbinding, of leeg wanneer hij niet bruikbaar is.
/// Alles wat per repo gescheiden moet blijven — de werkkopie, de wachtrij —
/// hangt hieraan.
final _repoScopeProvider = Provider.family<String, String>(
  (ref, connectionId) =>
      ref.watch(gitConfigProvider(connectionId))?.storageSlug ?? '',
);

/// De werkkopie waar een offline REST-opslag naartoe schrijft (§8.1) — op web en
/// op desktop-zonder-git. Per repo gescheiden: een repo is een
/// vertrouwensgrens, en twee repo's met een gelijknamig deck deelden anders
/// dezelfde bestanden.
final draftMirrorProvider = Provider.family<DeckMirror, String>((
  ref,
  connectionId,
) {
  final scope = ref.watch(_repoScopeProvider(connectionId));
  final store = createDraftStore(scope: scope);
  // Werk uit de tijd van één repo hoort bij de repo die toen was ingesteld —
  // en dat is deze. Eenmalig; daarna vindt de sweep niets meer.
  unawaited(_adoptLegacy(store.adoptLegacyEntries, 'werkkopie'));
  return DraftMirror(store: store);
});

/// De duurzame wachtrij van nog niet gepushte decks (§8.5). Overleeft het
/// afsluiten: hij zit in de sleutel/waarde-opslag. Ook per repo gescheiden —
/// zonder dat duwde een flush de hele wachtrij naar de forge die op dat moment
/// was ingesteld, ongeacht voor welke repo het werk bedoeld was.
final outboxProvider = Provider.family<Outbox, String>((ref, connectionId) {
  final outbox = Outbox(scope: ref.watch(_repoScopeProvider(connectionId)));
  unawaited(_adoptLegacy(outbox.adoptLegacyEntries, 'wachtrij'));
  return outbox;
});

/// De overname mag de provider niet ophouden en mag hem al helemaal niet laten
/// omvallen: mislukt hij, dan staat het oude werk er nog steeds — onbereikbaar,
/// maar niet weg — en dat is een logregel waard, geen crash.
Future<void> _adoptLegacy(Future<int> Function() adopt, String wat) async {
  try {
    await adopt();
  } catch (e, s) {
    logError('git: overnemen van de oude $wat mislukt', e, s);
  }
}

/// Verzoent de werkkopie met de forge (§8): maakt commits van wat wacht zodra
/// dat kan. `null` wanneer er geen repo is ingesteld — dan is er niets te
/// synchroniseren. Herbouwd zodra de forge-config wijzigt.
final syncEngineProvider = FutureProvider.family<SyncEngine?, String>((
  ref,
  connectionId,
) async {
  final forge = await ref.watch(gitForgeProvider(connectionId).future);
  if (forge == null) return null;
  return SyncEngine(
    forge: forge,
    mirror: ref.watch(draftMirrorProvider(connectionId)),
    outbox: ref.watch(outboxProvider(connectionId)),
  );
});

/// De deckmappen op [branch], als deknaam → pad. `autoDispose` zodat een
/// gesloten dialoog de cache niet vasthoudt.
typedef GitDeckListKey = ({String connectionId, String branch});

final gitDeckListProvider = FutureProvider.autoDispose
    .family<Map<String, String>, GitDeckListKey>(retry: noAutoRetry, (
      ref,
      key,
    ) async {
      final forge = await ref.watch(gitForgeProvider(key.connectionId).future);
      if (forge == null) {
        throw const GitForgeException(
          GitForgeError.config,
          'Geen git-repository ingesteld',
        );
      }
      return forge.listDecks(key.branch);
    });

/// De release-tags van één deck (§9.4), nieuwste bovenaan. `autoDispose` zodat
/// een gesloten versiekiezer de cache niet vasthoudt.
typedef GitDeckTagsKey = ({String connectionId, String deckName});

final gitDeckTagsProvider = FutureProvider.autoDispose
    .family<List<TagRef>, GitDeckTagsKey>(retry: noAutoRetry, (ref, key) async {
      final forge = await ref.watch(gitForgeProvider(key.connectionId).future);
      if (forge == null) {
        throw const GitForgeException(
          GitForgeError.config,
          'Geen git-repository ingesteld',
        );
      }
      final mine = [
        for (final tag in await forge.listTags())
          if (GitRepoLayout.isReleaseTagFor(tag.name, key.deckName)) tag,
      ]..sort((a, b) => b.name.compareTo(a.name));
      return mine;
    });
