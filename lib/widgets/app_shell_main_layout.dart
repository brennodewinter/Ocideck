// Part of the app_shell library — see app_shell.dart.
// Split out for navigability (the main editor/preview layout); all imports
// live in the main library file. Top-level widgets relocate verbatim.
part of 'app_shell.dart';

class _MainLayout extends ConsumerStatefulWidget {
  final ExportService exportService;

  const _MainLayout({required this.exportService});

  @override
  ConsumerState<_MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<_MainLayout> {
  static const _minSlideRailWidth = 210.0;
  static const _defaultSlideRailWidth = 320.0;
  static const _minEditorWidth = 420.0;

  double _slideRailWidth = _defaultSlideRailWidth;

  // Laatst berekende exportstatus, zodat het commandopalet (geopend via een
  // sneltoets/menu, buiten build) de export-gate kan respecteren zonder een
  // provider te watchen in een callback.
  bool _canExport = false;

  @override
  Widget build(BuildContext context) {
    final deckState = ref.watch(deckProvider);
    final deck = deckState.deck!;
    final editor = ref.watch(editorProvider);
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;
    final deckNotifier = ref.read(deckProvider.notifier);

    final isMarkdownMode = editor.mode == EditorMode.markdown;

    final classificationDecision =
        ClassificationEnforcementPolicy.fromAppSettings(
          settings,
        ).evaluate(deck.tlp);
    final (:readiness, :quality) = _exportReadiness(
      deckState,
      settings,
      classificationDecision,
    );
    final (:canExport, :exportTooltip) = _exportGate(
      deckState,
      readiness,
      quality,
      l10n,
    );
    _canExport = canExport;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyS &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          _saveDeck();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: CallbackShortcuts(
        bindings: _shortcutBindings(deckNotifier),
        child: Scaffold(
          appBar: _appBar(
            deck,
            deckState,
            editor,
            l10n,
            isMarkdownMode,
            classificationDecision,
          ),
          bottomNavigationBar: _DeckStatusBar(
            deck: deck,
            deckState: deckState,
            exportDirectory: settings.exportDirectory,
            onSave: _saveDeck,
            onExport: canExport ? _exportDeck : null,
            exportTooltip: exportTooltip,
            readiness: readiness,
            quality: quality,
            remoteOrigin: deckState.remoteOrigin,
          ),
          body: Builder(
            builder: (ctx) {
              if (deckState.error != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(deckState.error!),
                      backgroundColor: Colors.red[700],
                      action: SnackBarAction(
                        label: ctx.l10n.d('OK'),
                        textColor: Colors.white,
                        onPressed: () =>
                            ref.read(deckProvider.notifier).clearError(),
                      ),
                    ),
                  );
                  ref.read(deckProvider.notifier).clearError();
                });
              }

              // The available width comes from MediaQuery, NOT a
              // LayoutBuilder: a LayoutBuilder rebuilds this subtree during
              // the layout phase, and when the slide list's keyed
              // ReorderableListView items get reparented in that pass their
              // overlay children are activated outside an active layout —
              // "A _RenderLayoutBuilder was mutated in performLayout". The
              // body row spans the window, so the window width is equivalent.
              final bodyWidth = MediaQuery.sizeOf(ctx).width;
              final maxRailWidth = (bodyWidth - _minEditorWidth)
                  .clamp(_minSlideRailWidth, bodyWidth)
                  .toDouble();
              final railWidth = _slideRailWidth
                  .clamp(_minSlideRailWidth, maxRailWidth)
                  .toDouble();
              if (railWidth != _slideRailWidth) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _slideRailWidth = railWidth);
                });
              }

              final workspace = Row(
                children: [
                  SizedBox(
                    width: railWidth,
                    child: SlideListPanel(railWidth: railWidth),
                  ),
                  _ResizableDivider(
                    onDrag: (delta) {
                      setState(() {
                        _slideRailWidth = (_slideRailWidth + delta)
                            .clamp(_minSlideRailWidth, maxRailWidth)
                            .toDouble();
                      });
                    },
                  ),
                  const Expanded(child: EditorPanel()),
                ],
              );
              if (!deck.finalized) return workspace;
              // Read-only lock (§8 A1): een afgerond deck blijft zichtbaar en
              // exporteerbaar, maar niet bewerkbaar. De banner maakt dat
              // duidelijk; de harde grendel zit in DeckNotifier._mutate.
              return Column(
                children: [
                  _finalizedBanner(context, l10n),
                  Expanded(child: workspace),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Read-only-banner voor een afgerond & verzegeld deck (§8 A1). Slank, boven
  /// de werkruimte; bekijken/exporteren blijft mogelijk, bewerken niet.
  Widget _finalizedBanner(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Material(
      color: AppTheme.amber600.withValues(alpha: 0.14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 16, color: AppTheme.amber600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.d(
                  'Deze presentatie is afgerond en verzegeld en kan niet worden bewerkt.',
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sneltoetsen van het hoofdscherm (opslaan, undo/redo, zoeken).
  Map<ShortcutActivator, VoidCallback> _shortcutBindings(
    DeckNotifier deckNotifier,
  ) {
    return {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveDeck,
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveDeck,
      // Ongedaan maken / opnieuw. Vuren alleen wanneer de focus niet in een
      // tekstveld zit (dat handelt z'n eigen undo af), dus geen conflict.
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          _undo(deckNotifier),
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
          _undo(deckNotifier),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): () =>
          _redo(deckNotifier),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        meta: true,
        shift: true,
      ): () =>
          _redo(deckNotifier),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
          _redo(deckNotifier),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openFind,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
      const SingleActivator(LogicalKeyboardKey.keyH, control: true):
          _openFindReplace,
      const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
          _openFindReplace,
      // Commandopalet: doorzoekbare lijst van alle acties.
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          _openCommandPalette,
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
          _openCommandPalette,
    };
  }

  /// De samengevatte exportstatus plus de onderliggende kwaliteitsmeldingen.
  /// Dezelfde samenvoeging als het kwaliteitspaneel: sync-analyse plus de
  /// asynchrone titel-afbeeldingcontrastcheck, zodat statusbalk en paneel
  /// dezelfde tellingen tonen.
  ///
  /// De privacy-gate telt mee in de *status*, niet in het kwaliteitsresultaat.
  /// Dat onderscheid is opzet. De statusbalk hoort elke gate te kennen die de
  /// export tegenhoudt — hij zei "Klaar voor export" terwijl de privacy-gate op
  /// blokkeren stond, en dat is de gevaarlijkste vorm van stilte die dit product
  /// kent. Maar de privacybevindingen bij `quality` optellen zou ze langs de
  /// kwaliteits-gate sturen, en dan krijgt de gebruiker bij het exporteren twéé
  /// dialogen over dezelfde bevindingen: die van de privacy-gate en die van de
  /// kwaliteits-gate. Eén gate, één dialoog, één status.
  ({ExportReadiness readiness, SlideQualityResult quality}) _exportReadiness(
    DeckState deckState,
    AppSettings settings,
    ExportDecision classificationDecision,
  ) {
    final syncQuality = ref.watch(deckQualityProvider);
    final imageIssues =
        ref.watch(imageContrastIssuesProvider).value ??
        const <SlideQualityIssue>[];
    final quality = imageIssues.isEmpty
        ? syncQuality
        : SlideQualityResult([...syncQuality.issues, ...imageIssues]);
    final readiness = evaluateExportReadiness(
      needsSave:
          !isWebPlatform && (deckState.filePath == null || deckState.isDirty),
      classificationDecision: classificationDecision,
      qualityDecision: QualityExportPolicy.fromAppSettings(
        warningsEnabled: settings.qualityWarningsOnExport,
        blockOnErrors: settings.qualityBlockExportOnErrors,
      ).evaluate(quality),
      privacyDecision: PrivacyExportPolicy(
        gate: settings.privacyExportGate,
      ).evaluate(ref.watch(privacyExportSummaryProvider)),
      privacyChecksEnabled: settings.privacyChecksEnabled,
    );
    return (readiness: readiness, quality: quality);
  }

  /// Of exporteren nu kan, plus de tooltip die uitlegt waarom (niet).
  /// "Eerst opslaan" bestaat om exports naast het deck-bestand te leggen; op
  /// web is er geen bestandssysteem en wordt de export een download, dus daar
  /// kan elk geopend deck direct geëxporteerd worden.
  ({bool canExport, String exportTooltip}) _exportGate(
    DeckState deckState,
    ExportReadiness readiness,
    SlideQualityResult quality,
    AppLocalizations l10n,
  ) {
    final exportTooltip = switch (readiness.status) {
      ExportReadinessStatus.needsSave =>
        deckState.filePath == null
            ? l10n.t('exportNeedsSave')
            : l10n.t('exportNeedsClean'),
      ExportReadinessStatus.blockedByClassification =>
        readiness.blockReason ?? l10n.t('exportReady'),
      ExportReadinessStatus.blockedByQuality ||
      ExportReadinessStatus.qualityWarnings => formatQualityExportReason(
        l10n,
        quality,
      ),
      ExportReadinessStatus.blockedByPrivacy => l10n.d(
        'Maak per slide een keuze (accepteren, waarschuwen of weglaten) voordat je exporteert. Dit is zo ingesteld bij Beveiliging.',
      ),
      ExportReadinessStatus.privacyWarnings => l10n.d(
        'Kies per slide wat er moet gebeuren, of exporteer bewust zoals het is.',
      ),
      ExportReadinessStatus.ready => l10n.t('exportReady'),
      ExportReadinessStatus.readyPrivacyUnchecked => l10n.d(
        'Er is niet gekeken naar persoonsgegevens, bijzondere gegevens en geheimen: de privacycontrole staat uit bij Beveiliging.',
      ),
    };
    return (canExport: readiness.canOpenExport, exportTooltip: exportTooltip);
  }

  PreferredSizeWidget _appBar(
    Deck deck,
    DeckState deckState,
    EditorState editor,
    AppLocalizations l10n,
    bool isMarkdownMode,
    ExportDecision classificationDecision,
  ) {
    final deckNotifier = ref.read(deckProvider.notifier);
    return AppBar(
      title: Row(
        children: [
          const Icon(Icons.slideshow_outlined, size: 22),
          const SizedBox(width: 10),
          Flexible(child: Text(deck.title, overflow: TextOverflow.ellipsis)),
          if (deckState.isDirty) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.orangeAccent,
                shape: BoxShape.circle,
              ),
            ),
          ],
          const SizedBox(width: 16),
          _TlpChip(
            tlp: deck.tlp,
            warnUnset:
                !classificationDecision.allowed && deck.tlp == TlpLevel.none,
            onSelected: (level) => deckNotifier.updateInfo(tlp: level),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: l10n.t('presentationProperties'),
            child: IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: _openProperties,
            ),
          ),
        ],
      ),
      actions: _appBarActions(deckState, editor, l10n, isMarkdownMode),
    );
  }

  List<Widget> _appBarActions(
    DeckState deckState,
    EditorState editor,
    AppLocalizations l10n,
    bool isMarkdownMode,
  ) {
    final deckNotifier = ref.read(deckProvider.notifier);
    return [
      // ── Bewerken ────────────────────────────────────────────────
      Tooltip(
        message: l10n.t('undo'),
        child: IconButton(
          icon: const Icon(Icons.undo, size: 18),
          onPressed: deckState.canUndo ? () => _undo(deckNotifier) : null,
        ),
      ),
      Tooltip(
        message: l10n.t('redo'),
        child: IconButton(
          icon: const Icon(Icons.redo, size: 18),
          onPressed: deckState.canRedo ? () => _redo(deckNotifier) : null,
        ),
      ),
      const _ActionsDivider(),
      // ── Inhoud ──────────────────────────────────────────────────
      Tooltip(
        message: l10n.t('imageLibrary'),
        child: IconButton(
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          onPressed: _openImageCarousel,
        ),
      ),
      const _ActionsDivider(),
      // ── Presenteren & uitvoer ───────────────────────────────────
      Tooltip(
        message: l10n.t('presentFullscreen'),
        child: IconButton(
          icon: const Icon(Icons.play_circle_outline, size: 20),
          onPressed: _presentDeck,
        ),
      ),
      Tooltip(
        message: isMarkdownMode ? l10n.t('visualMode') : l10n.t('markdownMode'),
        child: IconButton(
          icon: Icon(isMarkdownMode ? Icons.view_quilt : Icons.code, size: 18),
          onPressed: _toggleMarkdownMode,
        ),
      ),
      // Uitgeschakeld zolang er een opslag loopt: de knop deed er tot nu toe
      // niets aan af dat een tweede poging stil werd genegeerd, en zag er dus
      // uit alsof er niets gebeurde.
      Tooltip(
        message: l10n.t('saveShortcut'),
        child: IconButton(
          icon: const Icon(Icons.save_outlined, size: 18),
          onPressed: ref.watch(saveProgressProvider) == null ? _saveDeck : null,
        ),
      ),
      const _ActionsDivider(),
      // ── Overig (minder vaak gebruikt) ───────────────────────────
      PopupMenuButton<String>(
        tooltip: l10n.t('more'),
        icon: const Icon(Icons.more_vert, size: 20),
        position: PopupMenuPosition.under,
        onSelected: (v) {
          switch (v) {
            case 'command_palette':
              _openCommandPalette();
            case 'open':
              _openWithSearch(context, ref);
            case 'open_remote':
              _openFromConnection(context, ref);
            case 'save_remote':
              _saveToConnection(context, ref);
            case 'sync_git':
              _syncGit(context, ref);
            case 'history_git':
              _showGitHistory(context, ref);
            case 'tools_appendix':
              _insertToolsAppendix(context, ref);
            case 'search_git':
              _searchDecks(context, ref);
            case 'assets_git':
              _showAssetUsage(context, ref);
            case 'versions_git':
              _showGitVersions(context, ref);
            case 'review_git':
              _openForReview(context, ref);
            case 'merge_git':
              _mergeConcept(context, ref);
            case 'tag_git':
              _tagRelease(context, ref);
            case 'export_package':
              _exportPackage(context, ref);
            case 'import_package':
              _importPackage();
            case 'import_url':
              _importUrl();
            case 'find':
              _openFindReplace();
            case 'clear_checklists':
              _clearAllChecklists();
            case 'full_preview':
              _openFullDeckPreview();
            case 'finalize':
              _finalizeAndSeal();
            case 'settings':
              SettingsDialog.show(context);
          }
        },
        itemBuilder: (_) => _moreMenuItems(l10n),
      ),
      const SizedBox(width: 8),
    ];
  }

  /// De items van het "⋮"-overloopmenu. Losgetrokken uit [_appBarActions] om
  /// die methode binnen de lengtegrens te houden.
  /// Ongedaan maken, mét de selectie erachteraan.
  ///
  /// Het deck krimpt bij ongedaan maken, maar de selectie in het editorpaneel
  /// bleef staan waar hij stond. De panelen klemmen dat voor de wéérgave, dus
  /// het viel niet op — tot een actie de rauwe index gebruikte en er een slide
  /// op de verkeerde plek belandde. [EditorNotifier.clampIndex] bestond
  /// hiervoor en werd nergens aangeroepen; dit is die plek.
  void _undo(DeckNotifier deckNotifier) {
    deckNotifier.undo();
    _clampSelection(deckNotifier);
  }

  void _redo(DeckNotifier deckNotifier) {
    deckNotifier.redo();
    _clampSelection(deckNotifier);
  }

  void _clampSelection(DeckNotifier deckNotifier) {
    final count = deckNotifier.currentState.deck?.slides.length ?? 0;
    ref.read(editorProvider.notifier).clampIndex(count - 1);
  }

  Future<void> _saveDeck() async {
    await saveDeckWithDestination(
      context,
      ref,
      ref.read(deckProvider.notifier),
    );
  }

  /// Zoeken. In markdown-modus vraagt de editor zijn eigen zoekbalk op; in de
  /// gewone editor is er geen zoekbalk, dus opent hetzelfde venster als
  /// [_openFindReplace] — met het vervangen ingeklapt.
  ///
  /// Voorheen deed Ctrl/Cmd+F in de gewone editor niets: de sneltoets stond wél
  /// geregistreerd, dus de toets werd opgegeten en er gebeurde vervolgens niks.
  /// Deckbreed zoeken was daardoor alleen te bereiken via de vervang-sneltoets.
  void _openFind() {
    final editorNotifier = ref.read(editorProvider.notifier);
    final deckNotifier = ref.read(deckProvider.notifier);
    final isMarkdownMode = ref.read(editorProvider).mode == EditorMode.markdown;
    if (isMarkdownMode) {
      editorNotifier.requestMarkdownFind(showReplace: false);
      return;
    }
    FindReplaceDialog.show(
      context,
      countMatches: (q, cs) => deckNotifier.countMatches(q, caseSensitive: cs),
      replaceAll: (q, r, cs) =>
          deckNotifier.replaceAll(q, r, caseSensitive: cs),
    );
  }

  void _openFindReplace() {
    final editorNotifier = ref.read(editorProvider.notifier);
    final deckNotifier = ref.read(deckProvider.notifier);
    final isMarkdownMode = ref.read(editorProvider).mode == EditorMode.markdown;
    if (isMarkdownMode) {
      editorNotifier.requestMarkdownFind(showReplace: true);
      return;
    }
    FindReplaceDialog.show(
      context,
      countMatches: (q, cs) => deckNotifier.countMatches(q, caseSensitive: cs),
      replaceAll: (q, r, cs) =>
          deckNotifier.replaceAll(q, r, caseSensitive: cs),
    );
  }

  Future<void> _clearAllChecklists() async {
    final deckNotifier = ref.read(deckProvider.notifier);
    final l10n = context.l10n;
    final count = deckNotifier.checkedChecklistCount;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d('Er zijn geen aangevinkte checklist-items om te legen.'),
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          title: Text(l10n.d('Alle checkboxen legen?')),
          content: Text(
            '${l10n.d('Hiermee worden alle')} $count '
            '${l10n.d('aangevinkte checklist-items in de hele presentatie uitgevinkt. Dit kun je ongedaan maken met Ctrl/Cmd+Z.')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.d('Alles legen')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    deckNotifier.clearAllChecklists();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$count ${l10n.d('checklist-items uitgevinkt.')}'),
      ),
    );
  }

  Future<void> _openImageCarousel() async {
    final deckNotifier = ref.read(deckProvider.notifier);
    final editor = ref.read(editorProvider);
    final deck = ref.read(deckProvider).deck!;
    final settings = ref.read(settingsProvider);
    final l10n = context.l10n;
    final idx = editor.selectedIndex.clamp(0, deck.slides.length - 1);
    final slide = deck.slides[idx];
    final initialPath = _resolveImagePath(slide.imagePath, deck.projectPath);
    final result = await ImageCarouselPicker.show(
      context,
      searchPaths: _imageSearchPaths(deck.projectPath, settings.libraryPaths),
      initialPath: initialPath,
      captionService: ref.read(captionServiceProvider),
      descriptionService: ref.read(descriptionServiceProvider),
      usageOf: (absolutePath) => _imageUsages(ref, absolutePath),
      onReplaceUsages: (from, to) => _replaceImageUsages(ref, from, to),
      openDeckFiles: [
        for (final tab in ref.read(tabsProvider).tabs)
          ?tab.deckNotifier.currentState.filePath,
      ],
    );
    if (result == null) return;
    // De bibliotheek doorzoekt ook mappen buiten de presentatie; zo'n keuze
    // moet mee het deck in, anders stuurt de gebruiker straks een gat door.
    final pickedPath = await ref
        .read(imageServiceProvider)
        .importIntoDeck(result.path, projectPath: deck.projectPath);

    final updated = switch (slide.type) {
      SlideType.title ||
      SlideType.image ||
      SlideType.quote ||
      SlideType.question ||
      SlideType.bulletsImage => slide.copyWith(
        imagePath: pickedPath,
        imageCaption: result.caption,
      ),
      SlideType.twoImages => slide.copyWith(
        imagePath: slide.imagePath.isEmpty ? pickedPath : slide.imagePath,
        imagePath2: slide.imagePath.isEmpty ? slide.imagePath2 : pickedPath,
        imageCaption: slide.imagePath.isEmpty
            ? result.caption
            : slide.imageCaption,
        imageCaption2: slide.imagePath.isEmpty
            ? slide.imageCaption2
            : result.caption,
      ),
      SlideType.bullets => slide.copyWith(
        type: SlideType.bulletsImage,
        imagePath: pickedPath,
        imageCaption: result.caption,
        imageSize: slide.imageSize > 0 ? slide.imageSize : 40,
      ),
      _ => null,
    };

    if (updated == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d(
              'Deze slide kan geen afbeelding ontvangen. Kies eerst een afbeeldingsslide.',
            ),
          ),
        ),
      );
      return;
    }

    deckNotifier.updateSlide(idx, updated);
  }

  void _presentDeck() => presentDeck(context, ref);

  Future<void> _exportDeck() async {
    final deckState = ref.read(deckProvider);
    final deck = deckState.deck!;
    final l10n = context.l10n;
    final slides = _slidesForPresentationOrExport(deck);
    if (slides.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(emptyAudienceReason(l10n, deck, forExport: true)),
        ),
      );
      return;
    }
    // The export gate runs on the synchronous analyzer, but the title-image
    // contrast check is asynchronous. Fold its findings in so the gate and
    // the quality panel agree (the panel keeps the provider warm, so this is
    // usually already resolved).
    final syncQuality = ref.read(slideQualityAnalyzerProvider).analyze(deck);
    var quality = syncQuality;
    try {
      final imageIssues = await ref.read(imageContrastIssuesProvider.future);
      if (imageIssues.isNotEmpty) {
        quality = SlideQualityResult([...syncQuality.issues, ...imageIssues]);
      }
    } catch (e) {
      // Fall back to the sync result if the async pass fails.
      logWarning('export: async image-contrast pass failed', e);
    }
    if (!mounted) return;
    final privacySettings = ref.read(settingsProvider);
    final disabledRules = privacySettings.privacyDisabledRules;
    final ownIdentity = OwnIdentity.fromLines(
      privacySettings.privacyOwnIdentity,
    );
    final markdownService = ref.read(markdownServiceProvider);

    // De fabriek. Het exportdialoog kiest het doelgroepprofiel, maar mág de bron
    // niet hebben — dat is de projectiegrens. Deze closure sluit hier om de bron
    // heen en levert per profiel alleen AudienceDecks op.
    ExportBundle bundleFor(
      PrivacyExportProfile profile, {
      bool includeDetail = true,
    }) {
      // De beknopte versie laat de verdiepingsslides weg. Filteren gebeurt vóór
      // de paginering: een overlopende bevinding die in drie slides uiteenvalt
      // erft zijn verdiepingsvlag, en die drie horen samen te blijven.
      final chosen = includeDetail
          ? slides
          : slides.where((s) => !s.isDetail).toList();

      // Render-time pagination: an overflowing finding is exported as several
      // full-size slides instead of one shrunken one. The deck itself is
      // unchanged — this only affects what the export enumerates.
      // De projectiegrens. Vanaf hier raakt geen enkel exportpad de bron nog
      // aan: de rasterizer, de markdown voor de HTML-export, de PPTX-notities
      // en de documentmetadata worden allemaal uit dit ene object afgeleid.
      final source = deck.copyWith(slides: expandFindingsForRender(chosen));
      final audience = PrivacyProjection.forAudience(
        source,
        disabledRules: disabledRules,
        ownIdentity: ownIdentity,
        profile: profile,
      );
      return ExportBundle(
        audience: audience,
        // Inline chart data so the HTML export can render charts standalone,
        // even when a chart links an external CSV. Gegenereerd uit het
        // geprojecteerde deck: de HTML-export zet deze markdown letterlijk in het
        // bestand.
        markdown: markdownService.generateDeck(
          audience.deck,
          inlineChartData: true,
          forExport: true,
        ),
        manifest: RedactionManifestService(
          disabledRules: disabledRules,
          ownIdentity: ownIdentity,
        ).build(source, profile: profile),
        // De gate telt op de ONGEFILTERDE scan: de provider onderdrukt bevindingen
        // op slides die de auteur al heeft afgehandeld — precies wat je in het
        // paneel wilt, en precies wat je in deze samenvatting niet wilt.
        privacySummary: summarisePrivacyForExport(
          source,
          PrivacyScanner(
            disabledRules: disabledRules,
            ownIdentity: ownIdentity,
          ).scan(source),
        ),
      );
    }

    final hasPrivacyFindings = !bundleFor(
      PrivacyExportProfile.full,
    ).privacySummary.isEmpty;

    // De diepgangkeuze verschijnt alleen als er iets te kiezen valt: minstens
    // één verdiepingsslide én minstens één gewone, zodat de beknopte versie
    // nooit een leeg deck oplevert. Zelfde patroon als [hasPrivacyFindings].
    final hasDepthChoice =
        slides.any((s) => s.isDetail) && slides.any((s) => !s.isDetail);

    await ExportDialog.show(
      context,
      // Op web heeft een deck geen bestandspad; de deck-titel bepaalt dan de
      // naam van het te downloaden bestand.
      deckPath: deckState.filePath ?? '${_safeRemoteName(deck.title)}.md',
      bundleFor: bundleFor,
      hasPrivacyFindings: hasPrivacyFindings,
      hasDepthChoice: hasDepthChoice,
      cockpitColorScheme: ref.read(settingsProvider).cockpitColorScheme,
      exportService: widget.exportService,
      enforcementPolicy: ClassificationEnforcementPolicy.fromAppSettings(
        ref.read(settingsProvider),
      ),
      qualityResult: quality,
      qualityPolicy: QualityExportPolicy.fromAppSettings(
        warningsEnabled: ref.read(settingsProvider).qualityWarningsOnExport,
        blockOnErrors: ref.read(settingsProvider).qualityBlockExportOnErrors,
      ),
      exportDirectory: ref.read(settingsProvider).exportDirectory,
      // Inline chart data so the HTML export can render charts standalone,
      // even when a chart links an external CSV. Gegenereerd uit het
      // geprojecteerde deck: de HTML-export zet deze markdown letterlijk in het
      // bestand, dus wat hier niet geredigeerd is, staat straks één Ctrl+U
      // verderop leesbaar in de broncode.
      showClassificationWatermark: ref
          .read(settingsProvider)
          .classificationWatermarkEnabled,
      privacyPolicy: PrivacyExportPolicy(
        gate: ref.read(settingsProvider).privacyExportGate,
      ),
      privacyChecksEnabled: ref.read(settingsProvider).privacyChecksEnabled,
      // Noteer een geslaagde export bij het recente bestand, zodat de
      // welkomstlijst "laatst geëxporteerd als …" kan tonen. Alleen zinvol
      // met een echt bestandspad (op web is een deck een download).
      onExported: deckState.filePath == null
          ? null
          : (formatLabel) => ref
                .read(settingsProvider.notifier)
                .recordRecentFileExport(deckState.filePath!, formatLabel),
    );
  }

  void _toggleMarkdownMode() {
    final editorNotifier = ref.read(editorProvider.notifier);
    final deckNotifier = ref.read(deckProvider.notifier);
    final isMarkdownMode = ref.read(editorProvider).mode == EditorMode.markdown;
    if (isMarkdownMode) {
      editorNotifier.setMode(EditorMode.visual);
    } else {
      editorNotifier.setMode(
        EditorMode.markdown,
        initialMarkdown: deckNotifier.generateMarkdown(),
      );
    }
  }

  void _openFullDeckPreview() {
    final deck = ref.read(deckProvider).deck!;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            FullDeckPreview(deck: deck, themeProfile: deck.themeProfile),
      ),
    );
  }

  Future<void> _newInTab() async {
    final choice = await NewDeckDialog.show(context);
    if (choice == null) return;
    await ref
        .read(settingsProvider.notifier)
        .selectThemeProfile(choice.profileName);
    ref
        .read(tabsProvider.notifier)
        .newDeckInNewTab(choice.title, template: choice.template);
  }

  /// Documentintegriteit (§8 A1): toon de afrond-dialoog, verzegel het deck en
  /// sla het meteen op zodat het zegel op schijf staat.
  Future<void> _finalizeAndSeal() async {
    final deck = ref.read(deckProvider).deck;
    if (deck == null || deck.finalized) return;
    // AI_ASSIST §16.3: block sealing while AI-drafted text is unreviewed, and
    // say which slides so the user can clear them first.
    final blocking = ref.read(deckProvider.notifier).slidesBlockingSeal;
    if (blocking.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10n.d('Verzegelen kan pas als alle AI-concepten zijn nagekeken. Nog te controleren op dia:')} ${blocking.join(', ')}',
          ),
        ),
      );
      return;
    }
    final result = await FinalizeSealDialog.show(
      context,
      standardsUsed: ref.read(deckProvider).deck?.standardsUsed ?? const [],
    );
    if (result == null || !mounted) return;
    ref
        .read(deckProvider.notifier)
        .finalizeAndSeal(signature: result.signature);
    await _saveDeck();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.d('Presentatie afgerond en verzegeld.')),
      ),
    );
  }

  Future<void> _openProperties() => editPresentationInfo(context, ref);

  Future<void> _importPackage() async {
    // Web: hetzelfde bytes-pad als "Openen..." — de picker levert inhoud en
    // openDeckFromBytes pakt het pakket in het geheugen uit.
    if (isWebPlatform) {
      return _openWithBytesPicker(context, ref);
    }
    final settings = ref.read(settingsProvider);
    final l10n = context.l10n;
    final fileService = ref.read(fileServiceProvider);
    final path = await fileService.pickPackageFile(
      initialDirectory: settings.homeDirectory,
    );
    if (path == null) return;
    final failure = await ref
        .read(tabsProvider.notifier)
        .importPackageFile(path, homeDir: settings.homeDirectory);
    if (failure != null && mounted) {
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        l10n,
        '${l10n.d('Kon dit pakket niet importeren.')} '
        '${importFailureMessage(l10n, failure)}',
      );
    }
  }

  Future<void> _importUrl() => _importFromUrl(context, ref);

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.slate600),
          const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

// ── AppBar helpers ────────────────────────────────────────────────────────────
