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

  @override
  Widget build(BuildContext context) {
    final deckState = ref.watch(deckProvider);
    final deck = deckState.deck!;
    final editor = ref.watch(editorProvider);
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;
    final deckNotifier = ref.read(deckProvider.notifier);

    final isMarkdownMode = editor.mode == EditorMode.markdown;

    final canExport = deckState.filePath != null && !deckState.isDirty;
    final enforcement = ClassificationEnforcementPolicy.fromAppSettings(
      ref.watch(settingsProvider),
    );
    final classificationDecision = enforcement.evaluate(deck.tlp);
    final exportTooltip = deckState.filePath == null
        ? l10n.t('exportNeedsSave')
        : deckState.isDirty
        ? l10n.t('exportNeedsClean')
        : !classificationDecision.allowed
        ? classificationDecision.reason!
        : l10n.t('exportReady');

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
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _saveDeck,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveDeck,
          // Ongedaan maken / opnieuw. Vuren alleen wanneer de focus niet in een
          // tekstveld zit (dat handelt z'n eigen undo af), dus geen conflict.
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              deckNotifier.undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
              deckNotifier.undo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): deckNotifier.redo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): deckNotifier.redo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true):
              deckNotifier.redo,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openFind,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
              _openFindReplace,
          const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
              _openFindReplace,
        },
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
                        label: 'OK',
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

              return Row(
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
            },
          ),
        ),
      ),
    );
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
    final settings = ref.read(settingsProvider);
    return [
      // ── Bewerken ────────────────────────────────────────────────
      Tooltip(
        message: l10n.t('undo'),
        child: IconButton(
          icon: const Icon(Icons.undo, size: 18),
          onPressed: deckState.canUndo ? deckNotifier.undo : null,
        ),
      ),
      Tooltip(
        message: l10n.t('redo'),
        child: IconButton(
          icon: const Icon(Icons.redo, size: 18),
          onPressed: deckState.canRedo ? deckNotifier.redo : null,
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
      Tooltip(
        message: l10n.t('saveShortcut'),
        child: IconButton(
          icon: const Icon(Icons.save_outlined, size: 18),
          onPressed: _saveDeck,
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
            case 'new_tab':
              _newInTab();
            case 'open':
              _openWithSearch(context, ref, settings.homeDirectory);
            case 'open_nextcloud':
              _openFromNextcloud(context, ref);
            case 'save_nextcloud':
              _saveToNextcloud(context, ref);
            case 'export_package':
              _exportPackage();
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
            case 'properties':
              _openProperties();
            case 'settings':
              SettingsDialog.show(context);
          }
        },
        itemBuilder: (_) => [
          _menuItem(
            'new_tab',
            Icons.add_circle_outline,
            l10n.t('newPresentationTab'),
          ),
          _menuItem('open', Icons.folder_open_outlined, l10n.t('openEllipsis')),
          const PopupMenuDivider(),
          _menuItem(
            'export_package',
            Icons.inventory_2_outlined,
            l10n.t('exportPackage'),
          ),
          _menuItem(
            'import_package',
            Icons.unarchive_outlined,
            l10n.t('importPackage'),
          ),
          _menuItem('import_url', Icons.link, l10n.t('importUrl')),
          const PopupMenuDivider(),
          _menuItem(
            'open_nextcloud',
            Icons.cloud_download_outlined,
            l10n.d('Openen vanaf Nextcloud'),
          ),
          _menuItem(
            'save_nextcloud',
            Icons.cloud_upload_outlined,
            l10n.d('Opslaan naar Nextcloud'),
          ),
          const PopupMenuDivider(),
          _menuItem('find', Icons.find_replace, l10n.t('findReplace')),
          _menuItem(
            'clear_checklists',
            Icons.check_box_outline_blank,
            l10n.d('Alle checkboxen legen'),
          ),
          _menuItem(
            'full_preview',
            Icons.preview_outlined,
            l10n.t('fullDeckPreview'),
          ),
          const PopupMenuDivider(),
          // Style profiles are chosen via the "STIJL" pulldown in the
          // editor toolbar; no need to duplicate them here.
          _menuItem('settings', Icons.settings_outlined, l10n.t('settings')),
        ],
      ),
      const SizedBox(width: 8),
    ];
  }

  Future<void> _saveDeck() async {
    final settings = ref.read(settingsProvider);
    final deckNotifier = ref.read(deckProvider.notifier);
    await deckNotifier.save(initialDirectory: settings.homeDirectory);
  }

  void _openFind() {
    final editorNotifier = ref.read(editorProvider.notifier);
    final isMarkdownMode = ref.read(editorProvider).mode == EditorMode.markdown;
    if (isMarkdownMode) {
      editorNotifier.requestMarkdownFind(showReplace: false);
    }
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
      searchPaths: _imageSearchPaths(deck.projectPath, settings.homeDirectory),
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

    final updated = switch (slide.type) {
      SlideType.title ||
      SlideType.image ||
      SlideType.quote ||
      SlideType.question ||
      SlideType.bulletsImage => slide.copyWith(
        imagePath: result.path,
        imageCaption: result.caption,
      ),
      SlideType.twoImages => slide.copyWith(
        imagePath: slide.imagePath.isEmpty ? result.path : slide.imagePath,
        imagePath2: slide.imagePath.isEmpty ? slide.imagePath2 : result.path,
        imageCaption: slide.imagePath.isEmpty
            ? result.caption
            : slide.imageCaption,
        imageCaption2: slide.imagePath.isEmpty
            ? slide.imageCaption2
            : result.caption,
      ),
      SlideType.bullets => slide.copyWith(
        type: SlideType.bulletsImage,
        imagePath: result.path,
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

  void _presentDeck() {
    final deckNotifier = ref.read(deckProvider.notifier);
    final deck = ref.read(deckProvider).deck!;
    final editor = ref.read(editorProvider);
    final l10n = context.l10n;
    // Overgeslagen slides weglaten en de selectie naar de eerstvolgende
    // zichtbare slide vertalen.
    final visible = <int>[
      for (var i = 0; i < deck.slides.length; i++)
        if (!deck.slides[i].skipped &&
            slideVisibleAtTlp(deck.slides[i], deck.tlp))
          i,
    ];
    final slides = _slidesForPresentationOrExport(deck);
    if (slides.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d('Alle slides zijn overgeslagen — niets om te tonen.'),
          ),
        ),
      );
      return;
    }
    var initial = visible.indexWhere((i) => i >= editor.selectedIndex);
    if (initial < 0) initial = visible.length - 1;
    if (initial < 0) initial = 0;
    FullscreenPresenter.present(
      context,
      slides: slides,
      projectPath: deck.projectPath,
      themeProfile: deck.themeProfile,
      cockpitColorScheme: ref.read(settingsProvider).cockpitColorScheme,
      initialIndex: initial,
      tlp: deck.tlp,
      organization: deck.organization,
      showClassificationWatermark: ref
          .read(settingsProvider)
          .classificationWatermarkEnabled,
      allowRemoteMedia: ref.read(settingsProvider).allowRemoteMedia,
      showRehearsalSummary: deck.showRehearsalSummary,
      targetDuration: () {
        final secs = deck.presentationTargetSeconds;
        return secs > 0 ? Duration(seconds: secs) : null;
      }(),
      annotations: deck.annotations,
      onAnnotationsChanged: deckNotifier.setAnnotations,
      initialUserNotes: deck.userNotes,
      onUserNotesChanged: deckNotifier.setUserNotes,
      onSlideChanged: (updated) {
        final index = deckNotifier.currentState.deck?.slides.indexWhere(
          (slide) => slide.id == updated.id,
        );
        if (index != null && index >= 0) {
          deckNotifier.updateSlide(index, updated);
        }
      },
    );
  }

  Future<void> _exportDeck() async {
    final deckState = ref.read(deckProvider);
    final deck = deckState.deck!;
    final l10n = context.l10n;
    final slides = _slidesForPresentationOrExport(deck);
    if (slides.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d('Alle slides zijn overgeslagen — niets om te exporteren.'),
          ),
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
    await ExportDialog.show(
      context,
      deckPath: deckState.filePath!,
      slides: slides,
      themeProfile: deck.themeProfile,
      cockpitColorScheme: ref.read(settingsProvider).cockpitColorScheme,
      projectPath: deck.projectPath,
      exportService: widget.exportService,
      tlp: deck.tlp,
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
      // even when a chart links an external CSV.
      markdown: ref
          .read(markdownServiceProvider)
          .generateDeck(
            deck.copyWith(slides: slides),
            inlineChartData: true,
            forExport: true,
          ),
      organization: deck.organization,
      showClassificationWatermark: ref
          .read(settingsProvider)
          .classificationWatermarkEnabled,
      documentMetadata: ExportDocumentMetadata(
        title: deck.title,
        author: deck.author,
        organization: deck.organization,
        description: deck.description,
        keywords: deck.keywords,
        tlp: deck.tlp,
      ),
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
    final title = await NewDeckDialog.show(context);
    if (title != null) {
      ref.read(tabsProvider.notifier).newDeckInNewTab(title);
    }
  }

  Future<void> _openProperties() async {
    final deckNotifier = ref.read(deckProvider.notifier);
    final deck = ref.read(deckProvider).deck!;
    final info = await PresentationInfoDialog.show(context, deck);
    if (info == null) return;
    deckNotifier.updateInfo(
      title: info.title,
      author: info.author,
      organization: info.organization,
      version: info.version,
      date: info.date,
      description: info.description,
      keywords: info.keywords,
      presentationTargetSeconds: info.presentationTargetSeconds,
      showRehearsalSummary: info.showRehearsalSummary,
    );
  }

  Future<void> _exportPackage() async {
    final deck = ref.read(deckProvider).deck!;
    final l10n = context.l10n;
    final fileService = ref.read(fileServiceProvider);
    final dest = await fileService.pickPackageDestination(deck);
    if (dest == null) return;
    try {
      await fileService.exportPackage(deck, dest);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.d('Pakket geëxporteerd naar:')}\n$dest'),
        ),
      );
    } catch (e) {
      logError('AppShell: pakketexport mislukt', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.d('Export mislukt:')} ${userFacingError(l10n, e)}',
          ),
        ),
      );
    }
  }

  Future<void> _importPackage() async {
    final settings = ref.read(settingsProvider);
    final l10n = context.l10n;
    final fileService = ref.read(fileServiceProvider);
    final path = await fileService.pickPackageFile(
      initialDirectory: settings.homeDirectory,
    );
    if (path == null) return;
    final ok = await ref
        .read(tabsProvider.notifier)
        .importPackageFile(path, homeDir: settings.homeDirectory);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.d('Kon dit pakket niet importeren.'))),
      );
    }
  }

  Future<void> _importUrl() => _importFromUrl(context, ref);

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF475569)),
          const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

// ── AppBar helpers ────────────────────────────────────────────────────────────
