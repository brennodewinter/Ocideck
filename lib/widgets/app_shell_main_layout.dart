// Main editor/preview layout; imports and private scope live in app_shell.dart.
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

  /// De menubalk-doorgeefluik, in [initState] opgehaald zodat [dispose] hem nog
  /// kan leegmaken — `ref` mag daar niet meer.
  StateController<ShellDeckCommands?>? _commands;

  @override
  void initState() {
    super.initState();
    _commands = ref.read(shellDeckCommandsProvider.notifier);
  }

  /// Voor welk tabblad er als laatste is gepubliceerd. Wisselt de gebruiker van
  /// tabblad, dan moet de menubalk opnieuw gevuld worden, ook als de aan/uit-
  /// standen toevallig gelijk zijn.
  DeckNotifier? _publishedFor;

  /// Wat deze werkruimte als laatste publiceerde, zodat [dispose] alleen zijn
  /// eigen bijdrage opruimt.
  ShellDeckCommands? _published;

  @override
  void dispose() {
    // Deze werkruimte gaat dicht: haal de handelingen weg, zodat het menu niets
    // meer aanbiedt dat nergens meer op slaat. Alleen als er sindsdien geen
    // ander tabblad heeft gepubliceerd — die is dan de nieuwe eigenaar. De
    // notifier komt uit [initState]: `ref` is in dispose niet meer bruikbaar.
    final commands = _commands;
    final mine = _published;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // `mounted`: bij het afsluiten van de app is de container al opgeruimd
      // voordat deze callback aan de beurt is.
      if (commands != null &&
          commands.mounted &&
          mine != null &&
          identical(commands.state, mine)) {
        commands.state = null;
      }
    });
    super.dispose();
  }

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
    listenCollabAuthorityChange(ref, context, l10n); // handover melding (§5.3)
    listenMatrixCollab(ref, context, l10n); // realtime uitkomst-melding (§6.5)

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
    _publishMenuCommands(deckState, canExport);

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
        bindings: _shortcutBindings(this, deckNotifier),
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
            onJumpToFindings: () => _jumpToFirstFinding(quality),
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
              // Op smal web kan het venster onder rail-plus-editor komen; de
              // rail valt dan weg (#1881) — anders gooit clamp ArgumentError.
              final showRail =
                  bodyWidth >= _minSlideRailWidth + _minEditorWidth;
              final maxRailWidth = showRail
                  ? (bodyWidth - _minEditorWidth)
                        .clamp(_minSlideRailWidth, bodyWidth)
                        .toDouble()
                  : 0.0;
              final railWidth = showRail
                  ? _slideRailWidth
                        .clamp(_minSlideRailWidth, maxRailWidth)
                        .toDouble()
                  : 0.0;
              if (railWidth != _slideRailWidth) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _slideRailWidth = railWidth);
                });
              }

              // The chat rail rides alongside the editor while a realtime Matrix
              // session runs and the user has opened it (§6); non-modal, so
              // editing continues. `collabChatRail` is empty otherwise.
              final workspace = Row(
                children: [
                  if (showRail) ...[
                    SizedBox(
                      width: railWidth,
                      child: SlideListPanel(
                        railWidth: railWidth,
                        onPresentFromHere: (i) =>
                            _presentFromSlide(context, ref, i),
                      ),
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
                  ],
                  const Expanded(child: EditorPanel()),
                  ...collabChatRail(ref),
                  ...callRail(ref),
                ],
              );
              // Banners stack above the workspace: the collab verification
              // prompt (self-hiding — see CollabVerifyBanner) and the read-only
              // finalized lock.
              return Column(
                children: [
                  const CollabVerifyBanner(),
                  if (deck.finalized) _finalizedBanner(context, l10n),
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
    final logoIssues =
        ref.watch(themeLogoIssuesProvider).value ?? const <SlideQualityIssue>[];
    final asyncIssues = [...imageIssues, ...logoIssues];
    final quality = asyncIssues.isEmpty
        ? syncQuality
        : SlideQualityResult([...syncQuality.issues, ...asyncIssues]);
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
          _PresentationPropertiesButton(onPressed: _openProperties),
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
      // De sneltoets stond tot #803 ín de vertaalde tekst gebakken, terwijl het
      // commandopalet hem als losse literal droeg. Twee patronen naast elkaar
      // betekende in het Duits twee spellingen in één app (Strg naast Ctrl);
      // labelWithShortcut is nu de enige weg.
      IconButton(
        tooltip: labelWithShortcut(l10n, 'Ongedaan maken', 'Z'),
        icon: const Icon(Icons.undo, size: 18),
        onPressed: deckState.canUndo ? () => _undo(deckNotifier) : null,
      ),
      IconButton(
        tooltip: labelWithShortcut(l10n, 'Opnieuw', 'Z', shift: true),
        icon: const Icon(Icons.redo, size: 18),
        onPressed: deckState.canRedo ? () => _redo(deckNotifier) : null,
      ),
      const _ActionsDivider(),
      // ── Inhoud ──────────────────────────────────────────────────
      IconButton(
        tooltip: l10n.t('imageLibrary'),
        icon: const Icon(Icons.photo_library_outlined, size: 18),
        onPressed: _openImageCarousel,
      ),
      const _ActionsDivider(),
      // ── Presenteren & uitvoer ───────────────────────────────────
      IconButton(
        tooltip: l10n.t('presentFullscreen'),
        icon: const Icon(Icons.play_circle_outline, size: 20),
        onPressed: _presentDeck,
      ),
      IconButton(
        tooltip: isMarkdownMode ? l10n.t('visualMode') : l10n.t('markdownMode'),
        icon: Icon(isMarkdownMode ? Icons.view_quilt : Icons.code, size: 18),
        onPressed: _toggleMarkdownMode,
      ),
      // Uitgeschakeld zolang er een opslag loopt: de knop deed er tot nu toe
      // niets aan af dat een tweede poging stil werd genegeerd, en zag er dus
      // uit alsof er niets gebeurde.
      IconButton(
        tooltip: labelWithShortcut(l10n, 'Opslaan', 'S'),
        icon: const Icon(Icons.save_outlined, size: 18),
        onPressed: ref.watch(saveProgressProvider) == null ? _saveDeck : null,
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
            case 'rights_git':
              _showAssetRights(context, ref);
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
            case 'import_openkat':
            case 'openkat_add_server':
            case 'openkat_server_report':
              dispatchOpenKatShellAction(context, ref, v);
            case 'import_presentation':
              importPresentation(context, ref);
            case 'find':
              _openFindReplace();
            case 'clear_checklists':
              _clearAllChecklists();
            case 'full_preview':
              _openFullDeckPreview();
            case 'convert_to_document':
              convertDeckToDocument(context, ref);
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
          ?tab.deckNotifierOrNull?.currentState.filePath,
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

  /// De startknop presenteert vanaf de dia waar je stond (#846): wie op dia 12
  /// werkt en op afspelen drukt, wil daar beginnen. De verwachting is de
  /// zichtbare dia, niet altijd het begin — dat verraste in de praktijk juist
  /// méér dan het beschermde (#846 draait de #607-keuze terug). "Presenteer
  /// vanaf hier" in het diamenu blijft voor wie een andere dia wil kiezen
  /// zonder er eerst naartoe te navigeren; "alleen afspelen" begint bij dia 1.
  void _presentDeck() => presentDeck(context, ref);

  /// Spring naar de eerste slide met een openstaande kwaliteits- of
  /// privacybevinding. Kwaliteit gaat vóór privacy (net als in de export-gate),
  /// en binnen elke soort naar de laagste slide-index.
  ///
  /// De statusbalk-chip opent niet meer de exportdialoog bij deze statussen —
  /// de werkplek waar je de keuze per bevinding maakt zit bij de slide, niet
  /// in de export (#1963).
  void _jumpToFirstFinding(SlideQualityResult quality) {
    // Kwaliteit: de eerste slide met een actieerbare bevinding.
    int? qualitySlide;
    for (final i in quality.actionableIssues) {
      if (i.slideIndex < 0) continue;
      if (qualitySlide == null || i.slideIndex < qualitySlide) {
        qualitySlide = i.slideIndex;
      }
    }

    if (qualitySlide != null) {
      ref.read(editorProvider.notifier).select(qualitySlide);
      return;
    }

    // Privacy: de eerste slide met een zekere, onopgeloste bevinding.
    int? privacySlide;
    for (final f in ref.read(privacyScanProvider).certain) {
      if (f.slideIndex < 0) continue;
      if (privacySlide == null || f.slideIndex < privacySlide) {
        privacySlide = f.slideIndex;
      }
    }

    if (privacySlide != null) {
      ref.read(editorProvider.notifier).select(privacySlide);
    }
  }

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
      final logoIssues = await ref.read(themeLogoIssuesProvider.future);
      final asyncIssues = [...imageIssues, ...logoIssues];
      if (asyncIssues.isNotEmpty) {
        quality = SlideQualityResult([...syncQuality.issues, ...asyncIssues]);
      }
    } catch (e) {
      // Fall back to the sync result if the async pass fails.
      logWarning('export: async image-contrast pass failed', e);
    }
    if (!mounted) return;
    final privacySettings = ref.read(settingsProvider);
    final disabledRules = privacySettings.privacyDisabledRules;
    final regions = privacySettings.privacyRegions;
    final ownIdentity = OwnIdentity.fromLines(
      privacySettings.privacyOwnIdentity,
    );
    final markdownService = ref.read(markdownServiceProvider);

    final bundleFor = _exportBundleFactory(
      deck: deck,
      slides: slides,
      disabledRules: disabledRules,
      ownIdentity: ownIdentity,
      regions: regions,
      markdownService: markdownService,
    );

    // Uit de gememoiseerde provider, niet uit een hele bundel: deze bool kostte
    // drie scans plus een manifest met verse salts, en al het andere daarvan
    // werd weggegooid (#613).
    final hasPrivacyFindings = !ref.read(privacyExportSummaryProvider).isEmpty;

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

  Future<void> _toggleMarkdownMode() async {
    final editorNotifier = ref.read(editorProvider.notifier);
    final deckNotifier = ref.read(deckProvider.notifier);
    final editor = ref.read(editorProvider);
    final isMarkdownMode = editor.mode == EditorMode.markdown;
    if (isMarkdownMode) {
      if (editor.hasMarkdownDraft) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.l10n.d('Niet-toegepaste wijzigingen')),
            content: Text(
              ctx.l10n.d(
                'Je wijzigingen zijn nog niet toegepast. Wil je ze verwerpen?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.d('Doorgaan met bewerken')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.d('Wijzigingen verwerpen')),
              ),
            ],
          ),
        );
        if (discard != true || !mounted) return;
      }
      editorNotifier.setMode(EditorMode.visual);
    } else {
      editorNotifier.setMode(
        EditorMode.markdown,
        initialMarkdown: deckNotifier.generateMarkdown(),
      );
    }
  }

  void _openFullDeckPreview() => openFullDeckPreview(context, ref);

  Future<void> _newInTab() =>
      _createDeckFromDialog(context, ref, inNewTab: true);

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

  /// Sign the finalised deck's provenance — delegates to the top-level
  /// [runProvenanceSigning] (kept off `_MainLayoutState` for the class-size
  /// ratchet), passing this widget's save path.
  Future<void> _signProvenance() =>
      runProvenanceSigning(context, ref, save: _saveDeck);

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
}

/// Of exporteren nu kan, plus de tooltip die uitlegt waarom (niet).
/// "Eerst opslaan" bestaat om exports naast het deck-bestand te leggen; op
/// web is er geen bestandssysteem en wordt de export een download, dus daar
/// kan elk geopend deck direct geëxporteerd worden.
///
/// Top-level en niet op de State: de functie leest niets van de State — alles
/// wat ze nodig heeft komt als parameter binnen — en de klasse zit tegen haar
/// plafond ([classSizeBaseline] in tool/check_conventions.dart). Zelfde
/// afweging als `_createDeckFromDialog` hieronder.
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
      exportBlockMessage(l10n, readiness.classificationDecision) ?? '',
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

// ── AppBar helpers ────────────────────────────────────────────────────────────

/// Gedeeld door het startscherm en het tabbladmenu: kiezer tonen, profiel
/// zetten, het sjabloondocument voor de interfacetaal laden en het deck openen.
///
/// Top-level en niet op de State: beide aanroepplekken doen exact hetzelfde,
/// en de klasse zit tegen haar plafond.
Future<void> _createDeckFromDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool inNewTab,
}) async {
  // Vóór de dialoog vastpakken: na een await mag de context niet meer mee.
  final languageCode = context.l10n.languageCode;
  final choice = await NewDeckDialog.show(context);
  if (choice == null) return;
  if (!context.mounted) return;
  var y01 = ImprovementY01Metric.empty;
  if (choice.template.improvementFramework.isNotEmpty) {
    final enteredY01 = await ImprovementProjectSetupDialog.show(context);
    if (enteredY01 == null) return;
    if (!context.mounted) return;
    y01 = enteredY01;
  }
  // Profielkeuze is globaal (het actieve profiel bepaalt de stijl van elk
  // deck); eerst selecteren, dan aanmaken zodat het nieuwe deck hem erft.
  await ref
      .read(settingsProvider.notifier)
      .selectThemeProfile(choice.profileName);
  var slides = await TemplateContentService().loadSlides(
    choice.template.id,
    languageCode: languageCode,
    deckTitle: choice.title,
  );
  slides = applyImprovementY01ToSlides(slides, y01);
  final improvementFramework = choice.template.improvementFramework;
  final tabs = ref.read(tabsProvider.notifier);
  if (inNewTab) {
    tabs.newDeckInNewTab(
      choice.title,
      slides: slides,
      improvementFramework: improvementFramework,
      improvementY01Metric: y01,
    );
  } else {
    tabs.newDeckInCurrentTab(
      choice.title,
      slides: slides,
      improvementFramework: improvementFramework,
      improvementY01Metric: y01,
    );
  }
}

/// De exportfabriek: sluit om de bron heen en levert per doelgroepprofiel
/// alleen een [ExportBundle] op. Het exportdialoog kiest het profiel maar mág
/// de bron niet hebben — dat is de projectiegrens.
///
/// Top-level en geen methode: hij raakt geen enkel veld van de state, en
/// `_MainLayoutState` zit tegen zijn plafond (`classSizeBaseline`).
ExportBundle Function(PrivacyExportProfile, {bool includeDetail})
_exportBundleFactory({
  required Deck deck,
  required List<Slide> slides,
  required Set<String> disabledRules,
  required OwnIdentity ownIdentity,
  required Set<String> regions,
  required MarkdownService markdownService,
}) =>
    (PrivacyExportProfile profile, {bool includeDetail = true}) =>
        buildExportBundle(
          deck,
          slides,
          profile: profile,
          includeDetail: includeDetail,
          // Een presentatie-export rasteriseert en somt dia's op, dus hier
          // wordt de dia-paginering wél uitgeklapt (#1589).
          expandPages: true,
          disabledRules: disabledRules,
          ownIdentity: ownIdentity,
          regions: regions,
          markdownService: markdownService,
        );
