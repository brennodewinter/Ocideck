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

/// Waarschuwt vóór de commit dat niet alles meereist, en vraagt of het door mag
/// gaan. Geeft `true` bij "er valt niets te melden" of een bevestiging.
///
/// Bewust blokkerend en bewust vooraf. Achteraf melden dat de tekeningen niet
/// mee zijn is geen melding maar een condoleance: de gebruiker denkt dan al dat
/// zijn werk in de repo staat. Zelfde vorm als [_confirmWebAssetLoss], dat op
/// web hetzelfde doet voor een kale `.md`-download.
Future<bool> _confirmGitOmissions(BuildContext context, Deck deck) async {
  final missing = gitDeckOmissions(deck);
  if (missing.isEmpty) return true;
  final l10n = context.l10n;
  final lines = <String>[
    if (missing.annotatedSlides > 0)
      '${l10n.d('Tekeningen op slides')}: ${missing.annotatedSlides} ${l10n.d('slides')}',
    if (missing.noteSlides > 0)
      '${l10n.d('Gebruikersnotities')}: ${missing.noteSlides} ${l10n.d('slides')}',
    if (missing.sealed) l10n.d('Zegel en handtekening'),
  ];
  final choice = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.d('Niet alles gaat mee naar git')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ctx.l10n.d(
              'Deze onderdelen komen niet in de commit terecht en staan straks niet in de repository:',
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines) Text('• $line'),
          const SizedBox(height: 8),
          Text(
            ctx.l10n.d(
              'Ze blijven in dit venster staan. Sla de presentatie ook als bestand of als .ocideck-pakket op om ze te bewaren.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.d('Annuleren')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.l10n.d('Toch opslaan')),
        ),
      ],
    ),
  );
  return choice == true;
}

Future<void> _saveToGit(
  BuildContext context,
  WidgetRef ref, {
  GitConnection? connectionOverride,
}) async {
  final tab = ref.read(tabsProvider).current;
  final deck = tab?.deckNotifier.currentState.deck;
  if (tab == null || deck == null) return;
  // Vóór alles: wat blijft er achter? Eerst laten kiezen, dan pas verbinden.
  if (!await _confirmGitOmissions(context, deck)) return;
  if (!context.mounted) return;
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
  if (connection == null || !context.mounted) return;
  final forge = await ref.read(gitForgeProvider(connection.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }
  final config = connection.repo;

  final defaultName = origin?.deckName ?? _safeDeckName(deck.title);
  final choice = await _showGitSaveDialog(context, defaultName: defaultName);
  if (choice == null || !context.mounted) return;
  // Het dialoog valideert de naam al; dit is de vangnet-tak.
  final deckDir = GitRepoLayout.deckDir(choice.name);
  if (deckDir == null) return;

  // Native git als het er is: een echte lokale commit. Anders het REST-pad.
  final native = await ref.read(nativeGitMirrorProvider(connection.id).future);
  if (!context.mounted) return;

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
    if (!context.mounted) return;
    switch (result.status) {
      case GitSaveStatus.committed:
        final base = '${l10n.d('Opgeslagen in git:')} $deckDir';
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.warnings.isEmpty
                  ? base
                  : '$base — ${l10n.d('video en audio gaan (nog) niet mee naar git')}',
            ),
          ),
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
      case GitSaveStatus.failed:
        showErrorSnackBar(
          messenger,
          l10n,
          '${l10n.d('Opslaan mislukt:')} ${result.message ?? ''}',
        );
    }
    // Een geslaagde opslag is een goed moment om te kijken of er nog iets in de
    // wachtrij stond van een eerdere offline-sessie: leeg die op de koop toe.
    if (result.status == GitSaveStatus.committed && context.mounted) {
      await _flushGitQueue(context, ref, config, connection.id, silent: true);
    }
  } on GitForgeException catch (e) {
    // De ruwe tekst hoort in het log: dáár wil je "Onverwachte status 418"
    // lezen. De gebruiker krijgt de vertaalde melding per foutsoort.
    logWarning('shell_actions_git: opslaan mislukt', e);
    messenger.showSnackBar(SnackBar(content: Text(userFacingError(l10n, e))));
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

  // Native: duw de lokale historie omhoog. Er is geen wachtrij — niet-gepushte
  // commits zíjn de wachtrij.
  final native = await ref.read(nativeGitMirrorProvider(connectionId).future);
  if (!context.mounted) return;
  if (native != null) {
    final result = await ref.read(tabsProvider.notifier).syncGitNative(native);
    if (!context.mounted || silent) return; // een stille flush meldt niets
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result.status) {
          GitSaveStatus.committed ||
          GitSaveStatus.merged => l10n.d('Gesynchroniseerd met git.'),
          GitSaveStatus.queued => l10n.d(
            'Nog geen verbinding — het gaat later mee.',
          ),
          GitSaveStatus.conflict => l10n.d(
            'De branch is verzet; je commits staan lokaal klaar.',
          ),
          GitSaveStatus.failed => l10n.d('Synchroniseren mislukt.'),
        }),
      ),
    );
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
  messenger.showSnackBar(SnackBar(content: Text(text)));
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
    messenger.showSnackBar(SnackBar(content: Text(userFacingError(l10n, e))));
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
    final result = await ref
        .read(tabsProvider.notifier)
        .openVersionFromGit(
          forge,
          config: origin.config,
          deckDir: origin.deckDir,
          tag: chosen.name,
        );
    _reportOpenFailure(messenger, l10n, result);
  } on GitForgeException catch (e) {
    logWarning('shell_actions_git: forge-aanroep mislukt', e);
    messenger.showSnackBar(SnackBar(content: Text(userFacingError(l10n, e))));
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

    final before = await notifier.readVersionDeck(
      forge,
      config: origin.config,
      deckDir: origin.deckDir,
      tag: beforeTag.name,
    );
    final after = await notifier.readVersionDeck(
      forge,
      config: origin.config,
      deckDir: origin.deckDir,
      tag: afterTag.name,
    );
    if (!context.mounted) return;
    if (before.deck == null || after.deck == null) {
      _reportOpenFailure(
        messenger,
        l10n,
        before.deck == null ? before.failure : after.failure,
      );
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
    messenger.showSnackBar(SnackBar(content: Text(userFacingError(l10n, e))));
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
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.d('Uitgebracht ter review:')} $url'),
          duration: const Duration(seconds: 8),
          action: url.isEmpty
              ? null
              : SnackBarAction(
                  label: l10n.d('Kopieer link'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: url)),
                ),
        ),
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
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.d('Versie vastgelegd:')} ${result.tag?.name}'),
        ),
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
    messenger.showSnackBar(SnackBar(content: Text(userFacingError(l10n, e))));
    return;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) => AssetUsageDialog(snapshot: snapshot),
  );
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
