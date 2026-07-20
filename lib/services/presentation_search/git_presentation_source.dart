import 'dart:convert';

import '../../models/git_settings.dart';
import '../../utils/log.dart';
import '../file_service.dart';
import '../git/asset_pool.dart';
import '../git/git_forge.dart';
import '../git/repo_asset_resolver.dart';
import 'presentation_source.dart';

/// Doorzoekt alle decks van één git-repository op de standaardbranch.
///
/// Leest elke `deck.md` via de forge (REST), laat hem door dezelfde
/// veiligheidspoort als het gewone openen ([FileService.openDeckFromContent]:
/// scan → marp-sniff → parse) en vervangt `repo:`-afbeeldingen door in-geheugen
/// `mem:`-verwijzingen ([resolveRepoAssetsToMem]), zodat de finder previews kan
/// tonen en slides met beeld kan toevoegen. Een onleesbaar of geweigerd deck
/// wordt overgeslagen, niet fataal.
class GitPresentationSource implements PresentationSource {
  GitPresentationSource({
    required this.forge,
    required this.config,
    required this.fileService,
    required this.label,
    this.maxDecks = 200,
  });

  final GitForge forge;
  final GitRepoConfig config;
  final FileService fileService;

  @override
  final String label;

  /// Bovengrens op het aantal decks dat één repo-scan inleest, als rem op een
  /// uitschieter. Overschrijding wordt gelogd, niet stil afgekapt.
  final int maxDecks;

  @override
  Future<List<ScannedPresentation>> scan() async {
    final branch = config.defaultBranch;
    final decks = await forge.listDecks(branch);
    final pool = AssetPool(forge: forge, branch: branch);
    final out = <ScannedPresentation>[];
    var count = 0;
    for (final entry in decks.entries) {
      if (count >= maxDecks) {
        logWarning(
          'GitPresentationSource: scan afgekapt op $maxDecks decks ($label)',
        );
        break;
      }
      count++;
      final scanned = await _readDeck(entry.value, branch, pool);
      if (scanned != null) out.add(scanned);
    }
    return out;
  }

  Future<ScannedPresentation?> _readDeck(
    String deckDir,
    String branch,
    AssetPool pool,
  ) async {
    try {
      final bytes = await forge.readBlob(branch, '$deckDir/deck.md');
      if (bytes.length > FileService.maxDeckMarkdownBytes) return null;
      final String raw;
      try {
        raw = utf8.decode(bytes);
      } on FormatException catch (e) {
        logWarning('GitPresentationSource: deck.md is geen geldige UTF-8', e);
        return null;
      }
      final deckName = GitRepoLayout.deckNameOf(deckDir) ?? deckDir;
      final sourceName = '${config.slug} · $deckName';
      final parsed = fileService.openDeckFromContent(
        raw,
        sourceName: sourceName,
      );
      final deck = parsed.deck;
      if (deck == null) return null;
      final withAssets = await resolveRepoAssetsToMem(
        deck,
        pool,
        sourceName: sourceName,
      );
      return ScannedPresentation(
        path: 'git:${config.slug}/$deckDir',
        fileName: '$deckName/deck.md',
        deck: withAssets,
        content: raw,
      );
    } on GitForgeException catch (e) {
      logWarning('GitPresentationSource: deck onleesbaar ($deckDir)', e);
      return null;
    }
  }
}
