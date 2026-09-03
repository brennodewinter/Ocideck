// Part of the app_shell library — see ../app_shell.dart.
// De git-handlers (opslaan, synchroniseren, historie, versies + vergelijken,
// uitbrengen, mergen, vastleggen), afgesplitst van shell_actions.dart zodat dat
// bestand onder de regelratchet blijft. Alle imports staan in de hoofdlibrary;
// de dialogen die deze handlers openen staan in shell_actions_git_dialogs.dart,
// het open-pad in shell_actions.dart.
part of '../app_shell.dart';

/// Schrijf het deck van het huidige tabblad terug naar git als één commit.
/// Vraagt de deknaam (voorin gevuld met de herkomst, zodat terugschrijven één
/// bevestiging is) en een commitboodschap. Anders dan Nextcloud werkt dit óók op
/// web (§4.4).
/// De git-verbinding waar een geopend deck bij hoort.
///
/// Deck-gebonden acties — historie, versies, review, samenvoegen, taggen — mogen
/// niets vragen: de herkomst wéét al bij welke opdrachtgever dit werk hoort, en
/// een keuzedialoog zou de gebruiker de kans geven daar per ongeluk van af te
/// wijken. Is de verbinding intussen verwijderd, dan valt er niets zinnigs te
/// doen (de repo is weg en het token ook) en zegt de app dat.
GitConnection? _originConnection(
  BuildContext context,
  WidgetRef ref,
  GitOrigin origin,
) {
  final connection = ref
      .read(settingsProvider)
      .gitConnectionFor(origin.connectionId, origin.config);
  if (connection == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d('De git-verbinding van dit deck bestaat niet meer.'),
        ),
      ),
    );
  }
  return connection;
}

/// Vertelt de gebruiker hoe de opslag afliep.
///
/// Los van [_saveToGit] omdat het een ander onderwerp is — dat bouwt de opslag
/// op, dit legt de uitkomst uit — en omdat de methodelengteratchet er terecht
/// over viel toen de weigering van #541 erbij kwam.
Future<void> _reportGitSaveResult(
  BuildContext context,
  WidgetRef ref,
  GitSaveResult result, {
  required AppLocalizations l10n,
  required ScaffoldMessengerState messenger,
  required String deckDir,
}) async {
  switch (result.status) {
    case GitSaveStatus.committed:
      final base = '${l10n.d('Opgeslagen in git:')} $deckDir';
      showCopyableSnackBar(
        messenger,
        l10n,
        result.warnings.isEmpty
            ? base
            // De warnings zijn verwijzingen die niet gepoold konden
            // worden — onleesbaar, zonder bruikbare extensie of buiten
            // het project. Media reist gewoon mee; dat "video en audio
            // niet meegaan" stond hier tot 23-07-2026 en was achterhaald.
            : '$base — ${l10n.d('niet elk gekoppeld bestand kon mee (onleesbaar of buiten het project)')}',
      );
    case GitSaveStatus.queued:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.d('Opgeslagen — gaat mee zodra er weer verbinding is.'),
          ),
        ),
      );
    case GitSaveStatus.merged:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.d(
              'Iemand anders had dit deck ook bewerkt — samengevoegd en opgeslagen.',
            ),
          ),
        ),
      );
    case GitSaveStatus.conflict:
      // Samenvoegen lukte deels: het samengevoegde deck staat al in het
      // tabblad met ónze kant voorop. Laat de gebruiker per slide kiezen.
      if (result.conflicts.isNotEmpty && context.mounted) {
        await _resolveMergeConflicts(context, ref, result.conflicts);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.d(
                'De branch is verplaatst; herlaad het deck en sla opnieuw op.',
              ),
            ),
          ),
        );
      }
    case GitSaveStatus.pushFailed:
      // Het werk staat lokaal (duurzaam) — maar publiceren lukte niet, en dat
      // lost zichzelf niet op zoals offline. Stel eerst gerust (opgeslagen), en
      // benoem dan de verhelpbare reden uit de foutsoort. Bewust een fout-
      // snackbar (kopieerbaar), want er is een handeling nodig.
      final reason = result.pushError;
      final detail = reason != null
          ? gitForgeErrorMessage(l10n, reason)
          : l10n.d(
              'Er ging onverwacht iets mis. Kijk in het logboek voor details.',
            );
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Lokaal opgeslagen, maar publiceren naar de forge lukte niet:')} $detail',
      );
    case GitSaveStatus.failed:
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Opslaan mislukt:')} ${result.message ?? ''}',
      );
  }
}

Future<bool> _saveToGit(
  BuildContext context,
  WidgetRef ref, {
  GitConnection? connectionOverride,
}) async {
  final tab = ref.read(tabsProvider).current;
  final deck = tab?.deckNotifier.currentState.deck;
  if (tab == null || deck == null) return false;
  // De "niet alles gaat mee"-waarschuwing en de zegelweigering die hier
  // stonden zijn opgeheven (#541): álle lagen reizen mee, ook het zegel — git
  // is een bestandssysteem, geen enforcer. Wat een zegel betekent bewaakt de
  // app door een verzegeld deck alleen-lezen te maken.
  // Kwam dit deck uit een repo die nog bestaat, dan gaat het daar zonder vragen
  // naartoe terug. Alleen een deck zonder herkomst laat kiezen — of een
  // expliciet gekozen doel, want dat is wat "Opslaan naar…" betekent.
  final origin = tab.gitOrigin;
  // Bewust uitgeschreven en niet als één expressie: de herkomst-tak doet geen
  // await, en dan hoort de analyse dat ook te kunnen zien.
  final GitConnection? connection;
  if (connectionOverride != null) {
    connection = connectionOverride;
  } else if (origin != null) {
    connection = _originConnection(context, ref, origin);
  } else {
    connection = await _pickGitConnection(context, ref);
  }
  if (connection == null || !context.mounted) return false;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return false;
  if (forge == null) {
    _gitNotConfigured(context);
    return false;
  }
  final config = connection.repo;

  final defaultName = origin?.deckName ?? _safeDeckName(deck.title);
  final choice = await _showGitSaveDialog(context, defaultName: defaultName);
  if (choice == null || !context.mounted) return false;
  // Het dialoog valideert de naam al; dit is de vangnet-tak.
  final deckDir = GitRepoLayout.deckDir(choice.name);
  if (deckDir == null) return false;

  // Native git als het er is: een echte lokale commit. Anders het REST-pad.
  final native = await ref.read(nativeGitMirrorProvider(connection.id).future);
  if (!context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final notifier = ref.read(tabsProvider.notifier);
    final gitConnection = connection;
    // Pas hier de melding aan: alles hierboven is dialoog en keuze, en "bezig
    // met opslaan" tonen terwijl de gebruiker nog een commitboodschap typt zou
    // liegen over wat er gebeurt.
    final result = await withSaveProgress(
      ref,
      SaveTarget.git,
      () => native != null
          ? notifier.saveToGitNative(
              native,
              config: config,
              deckDir: deckDir,
              branch: config.defaultBranch,
              message: choice.message,
              connectionId: gitConnection.id,
            )
          : notifier.saveToGit(
              forge,
              config: config,
              deckDir: deckDir,
              branch: config.defaultBranch,
              message: choice.message,
              mirror: ref.read(draftMirrorProvider(gitConnection.id)),
              outbox: ref.read(outboxProvider(gitConnection.id)),
              connectionId: gitConnection.id,
            ),
    );
    if (!context.mounted) return false;
    await _reportGitSaveResult(
      context,
      ref,
      result,
      l10n: l10n,
      messenger: messenger,
      deckDir: deckDir,
    );
    // Een geslaagde opslag is een goed moment om te kijken of er nog iets in de
    // wachtrij stond van een eerdere offline-sessie: leeg die op de koop toe.
    if (result.status == GitSaveStatus.committed && context.mounted) {
      await _flushGitQueue(context, ref, config, connection.id, silent: true);
    }
    // #1948: alleen een echte commit (of een lokaal gelande merge/queue) is
    // "bewaard genoeg om herstel te wissen". pushFailed laat een lokale commit
    // achter — dat is duurzaam, al moet publiceren nog. conflict en failed
    // laten niets achter: venster open, herstel laten staan.
    return switch (result.status) {
      GitSaveStatus.committed ||
      GitSaveStatus.merged ||
      GitSaveStatus.queued ||
      GitSaveStatus.pushFailed => true,
      GitSaveStatus.conflict || GitSaveStatus.failed => false,
    };
  } on GitForgeException catch (e) {
    // De ruwe tekst hoort in het log: dáár wil je "Onverwachte status 418"
    // lezen. De gebruiker krijgt de vertaalde melding per foutsoort.
    logWarning('shell_actions_git: opslaan mislukt', e);
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
    return false;
  } on GitCliException catch (e) {
    // Het native plane faalt lokaal met git's stderr: een achtergebleven
    // index.lock, een volle schijf, een kapotte index, een blijven staan
    // MERGE_HEAD. De commit is dán niet gemaakt (de push-afhandeling zit in
    // _push en gooit niet), dus dit is een echte mislukking — geen "gaat later
    // mee". Zonder deze tak verdween ze stil in runZonedGuarded.
    logWarning('shell_actions_git: native opslaan mislukt', e);
    showErrorSnackBar(
      messenger,
      l10n,
      '${l10n.d('Opslaan mislukt:')} ${userFacingError(l10n, e)}',
    );
    return false;
  } catch (e, s) {
    // Vangnet: een niet-git-fout (een te groot pakket, een leesfout in een
    // lokaal asset) mag niet stil verdwijnen — de spinner stopt, maar de
    // gebruiker zou niet weten waaróm er niets opgeslagen is.
    logError('shell_actions_git: opslaan mislukt', e, s);
    showErrorSnackBar(
      messenger,
      l10n,
      '${l10n.d('Opslaan mislukt:')} ${userFacingError(l10n, e)}',
    );
    return false;
  }
}

/// Laat de gebruiker per botsende slide kiezen welke kant blijft, en wissel die
/// keuze in het samengevoegde deck (§8.6).
///
/// Opslaan gebeurt daarna gewoon met de knop die hij al kent: de basis staat
/// inmiddels op de kop van de ander, dus die opslag landt schoon. Hem hier
/// ongevraagd nóg een commitdialoog voorschotelen zou verwarrender zijn dan één
/// bewuste handeling.
Future<void> _resolveMergeConflicts(
  BuildContext context,
  WidgetRef ref,
  List<SlideConflict> conflicts,
) async {
  final choices = await showDialog<Map<int, Slide?>>(
    context: context,
    builder: (_) => _MergeConflictDialog(conflicts: conflicts),
  );
  if (choices == null || !context.mounted) return;

  final tab = ref.read(tabsProvider).current;
  final deck = tab?.deckNotifier.currentState.deck;
  if (tab == null || deck == null) return;

  final slides = [...deck.slides];
  final drop = <int>[];
  choices.forEach((index, slide) {
    if (index < 0 || index >= slides.length) return;
    if (slide == null) {
      drop.add(index);
    } else {
      slides[index] = slide;
    }
  });
  // Van achter naar voren weghalen, anders schuiven de indices onder je weg.
  drop.sort((a, b) => b.compareTo(a));
  for (final i in drop) {
    slides.removeAt(i);
  }
  tab.deckNotifier.loadDeck(deck.copyWith(slides: slides));

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d('Keuzes toegepast — sla op om ze vast te leggen.'),
      ),
    ),
  );
}

/// Loop de wachtrij van nog niet gepushte decks leeg (§8.5). Handmatig via het
/// menu, of stilletjes ([silent]) na een geslaagde opslag. Meldt de uitkomst
/// alleen als er iets te melden was, of wanneer de gebruiker er zelf om vroeg.
Future<void> _syncGit(BuildContext context, WidgetRef ref) async {
  final connection = await _pickGitConnection(context, ref);
  if (connection == null || !context.mounted) return;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }
  await _flushGitQueue(
    context,
    ref,
    connection.repo,
    connection.id,
    silent: false,
  );
}

Future<void> _flushGitQueue(
  BuildContext context,
  WidgetRef ref,
  GitRepoConfig config,
  String connectionId, {
  required bool silent,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  // Alles wat de lijn op gaat kan gooien: offline vertrekt de netwerk-poort al
  // met een GitForgeException, en het native plane faalt met een
  // GitCliException. Zonder deze wacht verdween dat stil in runZonedGuarded —
  // en dan deed "Synchroniseren" niets zichtbaars. Een stille flush (na opslaan)
  // meldt niets; een handmatige toont altijd iets.
  try {
    // Native: duw de lokale historie omhoog. Er is geen wachtrij — niet-gepushte
    // commits zíjn de wachtrij.
    final native = await ref.read(nativeGitMirrorProvider(connectionId).future);
    if (!context.mounted) return;
    if (native != null) {
      final result = await ref
          .read(tabsProvider.notifier)
          .syncGitNative(native);
      if (!context.mounted || silent) return; // een stille flush meldt niets
      showCopyableSnackBar(messenger, l10n, switch (result.status) {
        GitSaveStatus.committed ||
        GitSaveStatus.merged => l10n.d('Gesynchroniseerd met git.'),
        GitSaveStatus.queued => l10n.d(
          'Nog geen verbinding — het gaat later mee.',
        ),
        GitSaveStatus.conflict => l10n.d(
          'De branch is verzet; je commits staan lokaal klaar.',
        ),
        // Lokaal bewaard, maar publiceren lukte niet en lost zichzelf niet
        // op: toon de verhelpbare reden rechtstreeks (token, certificaat…).
        GitSaveStatus.pushFailed =>
          result.pushError != null
              ? gitForgeErrorMessage(l10n, result.pushError!)
              : l10n.d('Synchroniseren mislukt.'),
        GitSaveStatus.failed => l10n.d('Synchroniseren mislukt.'),
      });
      return;
    }

    final engine = await ref.read(syncEngineProvider(connectionId).future);
    if (engine == null) return;
    if (silent && await ref.read(outboxProvider(connectionId)).isEmpty) return;

    final outcomes = await ref
        .read(tabsProvider.notifier)
        .flushGit(engine, config);
    // Ook bij een stille flush, en ook wanneer we hieronder vroegtijdig
    // terugkeren: de teller moet kloppen, niet de melding volgen.
    ref.invalidate(gitQueueCountProvider);
    if (!context.mounted) return;

    final settled = outcomes.where((o) => o.isSettled).length;
    final stuck = outcomes.length - settled;
    if (silent && settled == 0 && stuck == 0) return;

    final String text;
    if (outcomes.isEmpty) {
      text = l10n.d('Niets in de wachtrij.');
    } else if (stuck == 0) {
      text = '${l10n.d('Gesynchroniseerd:')} $settled';
    } else {
      text =
          '${l10n.d('Gesynchroniseerd:')} $settled — '
          '${l10n.d('nog in de wachtrij:')} $stuck';
    }
    showCopyableSnackBar(messenger, l10n, text);
  } on GitForgeException catch (e) {
    logWarning('shell_actions_git: synchroniseren mislukt', e);
    if (!context.mounted || silent) return;
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
  } on GitCliException catch (e) {
    logWarning('shell_actions_git: native synchroniseren mislukt', e);
    if (!context.mounted || silent) return;
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
  } catch (e, s) {
    logError('shell_actions_git: synchroniseren mislukt', e, s);
    if (!context.mounted || silent) return;
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
  }
}

/// Toon de commit-historie van het huidige, uit-git-geopende deck (§9.5). Alleen
/// bereikbaar op het native plane, waar er echte historie ís.
Future<void> _showGitHistory(BuildContext context, WidgetRef ref) async {
  final origin = ref.read(tabsProvider).current?.gitOrigin;
  if (origin == null) return;
  final connection = _originConnection(context, ref, origin);
  if (connection == null) return;
  final native = await ref.read(nativeGitMirrorProvider(connection.id).future);
  if (!context.mounted || native == null) return;
  final entries = await native.history(origin.deckDir);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _GitHistoryDialog(
      deckName: origin.deckName ?? origin.deckDir,
      entries: entries,
    ),
  );
}

/// Toon de uitgebrachte versies (release-tags) van het huidige deck en open de
/// gekozen versie read-only (§9.4). Werkt op elk plane — het is een
/// forge-listing.
Future<void> _showGitVersions(BuildContext context, WidgetRef ref) async {
  final origin = ref.read(tabsProvider).current?.gitOrigin;
  final deckName = origin?.deckName;
  if (origin == null || deckName == null) return;
  final connection = _originConnection(context, ref, origin);
  if (connection == null) return;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final List<TagRef> tags;
  try {
    tags = await ref.read(
      gitDeckTagsProvider((
        connectionId: connection.id,
        deckName: deckName,
      )).future,
    );
  } on GitForgeException catch (e) {
    logWarning('shell_actions_git: forge-aanroep mislukt', e);
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
    return;
  }
  if (!context.mounted) return;

  final action = await showDialog<_VersionAction>(
    context: context,
    builder: (_) => _GitVersionsDialog(deckName: deckName, tags: tags),
  );
  if (action == null || !context.mounted) return;

  if (action.compare) {
    await _compareVersions(
      context,
      ref,
      forge: forge,
      origin: origin,
      deckName: deckName,
      tags: tags,
    );
    return;
  }
  final chosen = action.open;
  if (chosen == null) return;
  try {
    ref.read(openFailureProvider.notifier).state = null;
    final result = await ref
        .read(tabsProvider.notifier)
        .openVersionFromGit(
          forge,
          config: origin.config,
          deckDir: origin.deckDir,
          tag: chosen.name,
        );
    _reportOpenFailure(
      messenger,
      l10n,
      result,
      reason: ref.read(openFailureProvider),
    );
  } on GitForgeException catch (e) {
    logWarning('shell_actions_git: forge-aanroep mislukt', e);
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
  }
}

/// Vergelijk twee uitgebrachte versies (§9.5): kies er twee, lees ze allebei
/// door de importpoort en toon wat er tussen de twee veranderde.
Future<void> _compareVersions(
  BuildContext context,
  WidgetRef ref, {
  required GitForge forge,
  required GitOrigin origin,
  required String deckName,
  required List<TagRef> tags,
}) async {
  final pair = await _showVersionComparePicker(context, deckName, tags);
  if (pair == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final notifier = ref.read(tabsProvider.notifier);
  try {
    // De oudste van de twee is de "voor"-kant, ongeacht de keuzevolgorde.
    final olderFirst = tags.indexOf(pair.a) > tags.indexOf(pair.b);
    final beforeTag = olderFirst ? pair.a : pair.b;
    final afterTag = olderFirst ? pair.b : pair.a;

    ref.read(openFailureProvider.notifier).state = null;
    final before = await notifier.readVersionDeck(
      forge,
      config: origin.config,
      deckDir: origin.deckDir,
      tag: beforeTag.name,
    );
    final beforeReason = ref.read(openFailureProvider);
    if (!context.mounted) return;
    if (before.deck == null) {
      _reportOpenFailure(messenger, l10n, before.failure, reason: beforeReason);
      return;
    }
    ref.read(openFailureProvider.notifier).state = null;
    final after = await notifier.readVersionDeck(
      forge,
      config: origin.config,
      deckDir: origin.deckDir,
      tag: afterTag.name,
    );
    final afterReason = ref.read(openFailureProvider);
    if (!context.mounted) return;
    if (after.deck == null) {
      _reportOpenFailure(messenger, l10n, after.failure, reason: afterReason);
      return;
    }

    final diff = diffDeckVersions(before.deck!, after.deck!);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _VersionDiffDialog(
        beforeLabel:
            GitRepoLayout.versionOfTag(beforeTag.name, deckName) ??
            beforeTag.name,
        afterLabel:
            GitRepoLayout.versionOfTag(afterTag.name, deckName) ??
            afterTag.name,
        beforeDeck: before.deck!,
        afterDeck: after.deck!,
        diff: diff,
      ),
    );
  } on GitForgeException catch (e) {
    logWarning('shell_actions_git: forge-aanroep mislukt', e);
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
  }
}

/// Breng het concept van het huidige tabblad uit ter review (§9.4): vraag een
/// titel + toelichting en open een pull request van de werkbranch naar de
/// standaardbranch. De classificatiepoort in [TabsNotifierGit.openForReview]
/// weigert fail-closed vóór er iets naar de forge gaat.
Future<void> _openForReview(BuildContext context, WidgetRef ref) async {
  final tab = ref.read(tabsProvider).current;
  final origin = tab?.gitOrigin;
  final deck = tab?.deckNotifier.currentState.deck;
  if (origin == null || deck == null) return;
  final connection = _originConnection(context, ref, origin);
  if (connection == null) return;
  final config = connection.repo;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }

  final deckName = origin.deckName ?? _safeDeckName(deck.title);
  final choice = await _showReviewDialog(context, deckName: deckName);
  if (choice == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final result = await ref
      .read(tabsProvider.notifier)
      .openForReview(
        forge,
        config: config,
        settings: ref.read(settingsProvider),
        title: choice.title,
        body: choice.message,
      );
  if (!context.mounted) return;
  switch (result.status) {
    case ReviewStatus.opened:
      final url = result.pr?.url ?? '';
      showCopyableSnackBar(
        messenger,
        l10n,
        '${l10n.d('Uitgebracht ter review:')} $url',
        duration: const Duration(seconds: 8),
      );
    case ReviewStatus.blocked:
      showErrorSnackBar(
        messenger,
        l10n,
        result.message ??
            l10n.d('Uitbrengen geblokkeerd door het classificatiebeleid.'),
      );
    case ReviewStatus.notOnWorkBranch:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.d(
              'Er is nog geen concept om uit te brengen — sla eerst een wijziging op.',
            ),
          ),
        ),
      );
    case ReviewStatus.failed:
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Uitbrengen mislukt:')} ${result.message ?? ''}',
      );
  }
}

/// Merge het concept van het huidige tabblad (§9.4): vraag bevestiging (met de
/// keuze de concept-branch op te ruimen) en merge de review-PR naar de
/// hoofdbranch. Daarna takt het tabblad terug op main.
Future<void> _mergeConcept(BuildContext context, WidgetRef ref) async {
  final origin = ref.read(tabsProvider).current?.gitOrigin;
  if (origin == null) return;
  final connection = _originConnection(context, ref, origin);
  if (connection == null) return;
  final config = connection.repo;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }

  final prune = await _showMergeDialog(context);
  if (prune == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final result = await ref
      .read(tabsProvider.notifier)
      .mergeConcept(forge, config: config, prune: prune);
  if (!context.mounted) return;
  switch (result.status) {
    case MergeStatus.merged:
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.d('Concept gemerged naar de hoofdbranch.')),
        ),
      );
    case MergeStatus.noPullRequest:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.d('Nog geen review — breng het concept eerst uit ter review.'),
          ),
        ),
      );
    case MergeStatus.notOnWorkBranch:
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.d('Er is geen concept om te mergen.'))),
      );
    case MergeStatus.failed:
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Mergen mislukt:')} ${result.message ?? ''}',
      );
  }
}

/// Leg de huidige versie van dit deck vast als release-tag (§9.4): vraag een
/// versie (`vX`) + boodschap en zet de tag op de kop van de hoofdbranch. Achter
/// de classificatiepoort, die in [TabsNotifierGit.tagRelease] fail-closed weigert.
Future<void> _tagRelease(BuildContext context, WidgetRef ref) async {
  final origin = ref.read(tabsProvider).current?.gitOrigin;
  if (origin == null) return;
  final connection = _originConnection(context, ref, origin);
  if (connection == null) return;
  final config = connection.repo;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }

  final choice = await _showTagDialog(context);
  if (choice == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final result = await ref
      .read(tabsProvider.notifier)
      .tagRelease(
        forge,
        config: config,
        settings: ref.read(settingsProvider),
        version: choice.version,
        message: choice.message,
      );
  if (!context.mounted) return;
  switch (result.status) {
    case ReleaseStatus.tagged:
      showCopyableSnackBar(
        messenger,
        l10n,
        '${l10n.d('Versie vastgelegd:')} ${result.tag?.name}',
      );
    case ReleaseStatus.blocked:
      showErrorSnackBar(
        messenger,
        l10n,
        result.message ??
            l10n.d('Vastleggen geblokkeerd door het classificatiebeleid.'),
      );
    case ReleaseStatus.invalidVersion:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.d('Ongeldige versie — gebruik vX, bijvoorbeeld v1.0.'),
          ),
        ),
      );
    case ReleaseStatus.noDeck:
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.d('Geen deck om vast te leggen.'))),
      );
    case ReleaseStatus.failed:
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Vastleggen mislukt:')} ${result.message ?? ''}',
      );
  }
}

/// Toon wat er in de gedeelde afbeeldingenpool zit en wie wat gebruikt (§9.3).
///
/// Bewust een expliciete handeling: de index leest élk deck en élke uitgebrachte
/// versie, dus dat bouw je niet per toetsaanslag opnieuw.
Future<void> _showAssetUsage(BuildContext context, WidgetRef ref) async {
  // Repo-breed: dit gaat over álle decks in één repository, dus welke dat is
  // moet vaststaan voor er iets gebeurt. De kiezer meldt zelf wanneer er nog
  // geen repository is — een menu-item dat stil terugvalt lijkt kapot.
  final connection = await _pickGitConnection(context, ref);
  if (connection == null || !context.mounted) return;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }

  final config = connection.repo;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final AssetIndexSnapshot snapshot;
  try {
    // Mét de uitgebrachte versies: anders lijkt een afbeelding die alleen nog
    // in een oude release zit ten onrechte ongebruikt.
    snapshot = await AssetIndex(
      forge: forge,
      branch: config.defaultBranch,
    ).build(includeReleases: true);
  } on GitForgeException catch (e) {
    logWarning('shell_actions_git: forge-aanroep mislukt', e);
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
    return;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) => AssetUsageDialog(snapshot: snapshot),
  );
}

/// Scan de gedeelde assetpool lokaal op aanwijzingen rond gebruiksrechten en
/// laat een beheerder die per signaal afdoen. De scan verstuurt geen beelden
/// naar derden; alleen de reeds ingestelde forge wordt gelezen en geschreven.
Future<void> _showAssetRights(BuildContext context, WidgetRef ref) async {
  if (!ref.read(assetRightsModuleEnabledProvider)) return;
  final connection = await _pickGitConnection(context, ref);
  if (connection == null || !context.mounted) return;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final index = RepoAssetRightsIndex(
    forge: forge,
    branch: connection.repo.defaultBranch,
  );
  try {
    final snapshot = await index.scanAndPersist();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AssetRightsDialog(index: index, initial: snapshot),
    );
  } on GitForgeException catch (e) {
    if (!context.mounted) return;
    showErrorSnackBar(messenger, l10n, userFacingError(l10n, e));
  }
}

/// Zoek over alle decks in de repo en open de gekozen vindplaats.
Future<void> _searchDecks(BuildContext context, WidgetRef ref) async {
  // Zie _showAssetUsage: repo-breed, dus eerst de verbinding vaststellen.
  final connection = await _pickGitConnection(context, ref);
  if (connection == null || !context.mounted) return;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }

  final config = connection.repo;

  // Kies de goedkoopste versneller die kan. Native `git grep` over een lokale
  // clone is volledig en forge-onafhankelijk; kan dat niet (web, of nog geen
  // clone), dan de server-codezoekopdracht van GitHub/GitLab — geïndexeerd, dus
  // best-effort. Kan geen van beide, dan blijft de shortlister null en valt
  // DeckSearch terug op de volledige scan, die overal werkt.
  final mirror = await ref.read(nativeGitMirrorProvider(connection.id).future);
  if (!context.mounted) return;
  final DeckShortlister? shortlister = mirror != null
      ? NativeGrepShortlister(mirror)
      : forge is CodeSearchCapable
      ? ServerCodeSearchShortlister(forge)
      : null;

  final deckDir = await GitSearchDialog.show(
    context,
    DeckSearch(
      forge: forge,
      branch: config.defaultBranch,
      shortlister: shortlister,
    ),
  );
  if (deckDir == null || !context.mounted) return;
  // Langs het gewone openpad: dezelfde gate, dezelfde native/REST-keuze.
  await _openFromGit(context, ref, deckDir: deckDir);
}

/// Maak een geldige deknaam (§6) uit een deck-titel, of een nette terugval.
String _safeDeckName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '')
      .replaceAll('..', '-');
  return GitRepoLayout.isValidDeckName(cleaned) ? cleaned : 'presentatie';
}

/// Voeg de bijlage met gebruikte hulpmiddelen in als tabel-slide (MIAUW 4.8.2).
///
/// Bewust een slide en geen afgeleide weergave: de eis vraagt een bijlage ín het
/// rapport, en alleen wat als slide bestaat komt in de PDF en de PPTX terecht.
/// De tester houdt de regie — hij voegt hem in, kan hem daarna bewerken, en
/// bevestigt zelf dat 4.8.2 daarmee gedekt is. OciDeck vinkt die eis niet af,
/// want na het invoegen kan de slide nog van alles worden.
///
/// De kopteksten staan in de taal van het **rapport**, niet van de interface:
/// een Nederlandse tester die voor een internationale klant schrijft, levert
/// anders een Engelse bijlage met Nederlandse kolomkoppen.
Future<void> _insertToolsAppendix(BuildContext context, WidgetRef ref) async {
  final deck = ref.read(deckProvider).deck;
  if (deck == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  if (deck.toolsUsed.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          l10n.d(
            'Nog geen hulpmiddelen vastgelegd — vul ze in bij Presentatie-info.',
          ),
        ),
      ),
    );
    return;
  }

  String reportText(String source) =>
      AppLocalizations.sourceFor(deck.language, source);

  ref.read(deckProvider.notifier).insertSlides([
    Slide.create(SlideType.table).copyWith(
      title: reportText('Gebruikte hulpmiddelen'),
      tableRows: toolsAppendixRows(
        deck.toolsUsed,
        nameHeader: reportText('Hulpmiddel'),
        descriptionHeader: reportText('Beschrijving'),
        versionHeader: reportText('Versie'),
        referenceHeader: reportText('Referentie'),
      ),
    ),
  ]);

  final incomplete = deck.toolsUsed.where((t) => t.isIncomplete).length;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        incomplete == 0
            ? l10n.d('Bijlage met hulpmiddelen toegevoegd.')
            // Niet blokkeren, wel melden: de eis vraagt beschrijving, versie én
            // referentie, en een half ingevulde rij haalt dat niet.
            : '${l10n.d('Bijlage toegevoegd, maar niet elk hulpmiddel heeft beschrijving, versie én referentie:')} $incomplete',
      ),
    ),
  );
}
