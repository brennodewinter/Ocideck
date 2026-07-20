part of 'tabs_provider.dart';

/// Het review- en uitbrengpad van de git-opslag (§9.4): een concept ter review
/// aanbieden, het samenvoegen, en er een versie van uitbrengen. Apart bestand
/// omdat `tabs_provider_git.dart` tegen de regelratchet aan zit; dezelfde
/// library, dus het open- en opslaanpad blijft bereikbaar.
extension TabsNotifierGitReview on TabsNotifier {
  /// Breng het concept van het huidige tabblad uit ter review (§9.4): open een
  /// pull request van de werkbranch naar de standaardbranch.
  ///
  /// Eerst de classificatiepoort, fail-closed en vóór élke netwerk-bijwerking —
  /// net als [ExportService.export] (export_service.dart:142), maar op de máx
  /// effective TLP van het hele deck ([deckReleaseTlp]), want een release is
  /// duurzaam en geadverteerd: één TLP:RED-slide in een TLP:none-deck hoort hem
  /// tegen te houden. Pas als de poort groen geeft gaat er iets naar de forge.
  ///
  /// Vereist dat het tabblad op een werkbranch staat (een lopende ronde) en dat
  /// die branch al op de forge staat — een gewone opslag pusht hem. Staat hij er
  /// nog niet (offline gecommit), dan komt dat als [ReviewStatus.failed] terug;
  /// synchroniseer dan eerst.
  Future<ReviewResult> openForReview(
    GitForge forge, {
    required GitRepoConfig config,
    required AppSettings settings,
    required String title,
    required String body,
  }) async {
    final tab = currentState.current;
    final origin = tab?.gitOrigin;
    final deck = tab?.deckNotifier.currentState.deck;
    if (origin == null || deck == null || !origin.matchesRepo(config)) {
      return const ReviewResult(status: ReviewStatus.notOnWorkBranch);
    }
    // Een review hoort bij een concept-ronde, niet bij de standaardbranch zelf.
    if (origin.branch == config.defaultBranch) {
      return const ReviewResult(status: ReviewStatus.notOnWorkBranch);
    }

    final decision = ClassificationEnforcementPolicy.fromAppSettings(
      settings,
    ).evaluate(deckReleaseTlp(deck));
    if (!decision.allowed) {
      return ReviewResult(
        status: ReviewStatus.blocked,
        message: decision.reason,
      );
    }

    try {
      final pr = await forge.openPullRequest(
        head: origin.branch,
        base: config.defaultBranch,
        title: title,
        body: body,
      );
      return ReviewResult(status: ReviewStatus.opened, pr: pr);
    } on GitForgeException catch (e) {
      logWarning('openForReview: PR openen mislukt', e);
      return ReviewResult(status: ReviewStatus.failed, message: e.message);
    }
  }

  /// Merge het concept van het huidige tabblad: vind de open pull request van de
  /// werkbranch, merge hem naar de standaardbranch, en — als [prune] — laat de
  /// forge de gemergede branch opruimen (§9.4). Daarna takt het tabblad terug op
  /// de standaardbranch: het concept ís nu de gepubliceerde versie, en een
  /// volgende opslag begint een nieuwe ronde.
  Future<MergeResult> mergeConcept(
    GitForge forge, {
    required GitRepoConfig config,
    bool prune = true,
  }) async {
    final tab = currentState.current;
    final origin = tab?.gitOrigin;
    if (origin == null || !origin.matchesRepo(config)) {
      return const MergeResult(status: MergeStatus.notOnWorkBranch);
    }
    if (origin.branch == config.defaultBranch) {
      return const MergeResult(status: MergeStatus.notOnWorkBranch);
    }

    try {
      final pr = await forge.pullRequestForBranch(origin.branch);
      if (pr == null) {
        return const MergeResult(status: MergeStatus.noPullRequest);
      }
      await forge.mergePullRequest(pr.number, deleteBranch: prune);
      // Het concept is nu deel van de standaardbranch: takt daar weer op vast.
      final head = await forge.headSha(config.defaultBranch);
      tab!.gitOrigin = GitOrigin(
        config: config,
        branch: config.defaultBranch,
        deckDir: origin.deckDir,
        baseSha: head,
        connectionId: origin.connectionId,
      );
      refreshTabs();
      return const MergeResult(status: MergeStatus.merged);
    } on GitForgeException catch (e) {
      logWarning('mergeConcept: mergen mislukt', e);
      return MergeResult(status: MergeStatus.failed, message: e.message);
    }
  }

  /// Leg de huidige versie van dit deck vast als release-tag `decks/<naam>/vX`
  /// op de kop van de standaardbranch (§9.4/D9). Achter dezelfde fail-closed
  /// classificatiepoort als [openForReview] (op de máx effective TLP): een tag is
  /// een blijvende, geadverteerde verwijzing en mag een deck niet voorbij zijn
  /// plafond publiceren.
  Future<ReleaseResult> tagRelease(
    GitForge forge, {
    required GitRepoConfig config,
    required AppSettings settings,
    required String version,
    required String message,
  }) async {
    final tab = currentState.current;
    final origin = tab?.gitOrigin;
    final deck = tab?.deckNotifier.currentState.deck;
    if (origin == null || deck == null || !origin.matchesRepo(config)) {
      return const ReleaseResult(status: ReleaseStatus.noDeck);
    }
    final deckName = origin.deckName;
    final tagName = deckName == null
        ? null
        : GitRepoLayout.releaseTag(deckName, version);
    if (tagName == null) {
      return const ReleaseResult(status: ReleaseStatus.invalidVersion);
    }

    final decision = ClassificationEnforcementPolicy.fromAppSettings(
      settings,
    ).evaluate(deckReleaseTlp(deck));
    if (!decision.allowed) {
      return ReleaseResult(
        status: ReleaseStatus.blocked,
        message: decision.reason,
      );
    }

    try {
      final tag = await forge.createTag(
        tagName,
        target: config.defaultBranch,
        message: message,
      );
      return ReleaseResult(status: ReleaseStatus.tagged, tag: tag);
    } on GitForgeException catch (e) {
      logWarning('tagRelease: tag maken mislukt', e);
      return ReleaseResult(status: ReleaseStatus.failed, message: e.message);
    }
  }
}

/// Hoe een [TabsNotifierGit.openForReview] afliep.
enum ReviewStatus {
  /// De pull request is geopend; [ReviewResult.pr] draagt het nummer + de link.
  opened,

  /// De classificatiepoort weigerde: het deck mag niet uitgebracht worden.
  /// [ReviewResult.message] draagt de uitlegbare reden.
  blocked,

  /// Er was geen concept om uit te brengen (geen tabblad, of het staat niet op
  /// een werkbranch).
  notOnWorkBranch,

  /// De forge deed het niet (netwerk, auth, of de branch staat er nog niet).
  failed,
}

class ReviewResult {
  final ReviewStatus status;

  /// De geopende pull request bij [ReviewStatus.opened].
  final PullRequestRef? pr;

  /// Uitlegbare tekst bij [ReviewStatus.blocked] en [ReviewStatus.failed].
  final String? message;

  const ReviewResult({required this.status, this.pr, this.message});
}

/// Hoe een [TabsNotifierGit.mergeConcept] afliep.
enum MergeStatus {
  /// Gemerged naar de standaardbranch; het tabblad takt daar nu op vast.
  merged,

  /// Er stond geen open pull request open voor deze werkbranch — nog niet
  /// uitgebracht ter review.
  noPullRequest,

  /// Er was geen concept om te mergen (geen tabblad, of het staat niet op een
  /// werkbranch).
  notOnWorkBranch,

  /// De forge deed het niet — bv. de PR kan (nog) niet gemerged worden.
  failed,
}

class MergeResult {
  final MergeStatus status;

  /// Uitlegbare tekst bij [MergeStatus.failed].
  final String? message;

  const MergeResult({required this.status, this.message});
}

/// Hoe een [TabsNotifierGit.tagRelease] afliep.
enum ReleaseStatus {
  /// De release-tag is gezet; [ReleaseResult.tag] draagt hem.
  tagged,

  /// De classificatiepoort weigerde: dit deck mag niet vastgelegd worden.
  /// [ReleaseResult.message] draagt de reden.
  blocked,

  /// De versie was geen geldige `vX` (of de deknaam deugde niet).
  invalidVersion,

  /// Er was geen deck om vast te leggen.
  noDeck,

  /// De forge deed het niet (netwerk, auth, of de tag bestond al).
  failed,
}

class ReleaseResult {
  final ReleaseStatus status;

  /// De gezette release-tag bij [ReleaseStatus.tagged].
  final TagRef? tag;

  /// Uitlegbare tekst bij [ReleaseStatus.blocked] en [ReleaseStatus.failed].
  final String? message;

  const ReleaseResult({required this.status, this.tag, this.message});
}
