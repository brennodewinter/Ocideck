// Part of the image_carousel_picker library — see ../image_carousel_picker.dart.
// Split out for navigability (scan, filter, dedupe, selection & clipboard actions); all imports live in the main library
// file. Instance methods relocate verbatim into an extension on
// _ImageCarouselPickerState — same library, same members, no behaviour change.
part of '../image_carousel_picker.dart';

extension _CarouselActions on _ImageCarouselPickerState {
  Future<void> _loadImages() async {
    // Begrensd, gebatcht en annuleerbaar via een aparte service (#1049): een
    // grote of gemounte bibliotheek zou anders de interface lang blokkeren. Bij
    // sluiten van de dialoog stopt de scan doordat `mounted` false wordt.
    final result = await ImageLibraryScanner.scan(
      [...widget.searchPaths, ..._extraRoots],
      isCancelled: () => !mounted,
      extensions: _ImageCarouselPickerState._exts,
    );
    if (!mounted) return;
    final sorted = result.paths;

    final descriptions = await widget.descriptionService.loadFor(sorted);

    if (!mounted) return;
    _rebuild(() {
      _images = sorted;
      _descriptions = descriptions;
      _loading = false;
      _rootsUnreachable =
          result.unreachableRoots.isNotEmpty && sorted.isEmpty;
      _selected =
          widget.initialPath ?? (sorted.isNotEmpty ? sorted.first : null);
      _applyFilter();
    });
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
    // Een afgekapte bibliotheek zou anders stil doen alsof dit alles is.
    if (result.truncated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d(
              'De afbeeldingenbibliotheek is te groot; alleen de nieuwste afbeeldingen worden getoond.',
            ),
          ),
        ),
      );
    }
    // Een mislukte scan (bijv. onbereikbare netwerkmap) zou anders stil een
    // lege of onvolledige bibliotheek tonen.
    if (result.failed && mounted) {
      final unreachable = result.unreachableRoots;
      final message = unreachable.isNotEmpty && result.paths.isEmpty
          ? context.l10n.d(
              'De bibliotheekmap is niet bereikbaar. Kies een map hieronder of pas Opslag aan onder ⋮ → Instellingen.',
            )
          : context.l10n.d(
              'Kon een of meer mappen van de bibliotheek niet lezen; de lijst kan onvolledig zijn.',
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Recompute [_filtered] from [_images] and the current query. Matches on
  /// file name and stored description (case-insensitive, all terms must hit)
  /// and ranks the hits on relevance so dat een korte zoekterm als "kl" de
  /// KLM-afbeelding meteen bovenaan toont in plaats van verzopen tussen alle
  /// andere "kl"-woorden. Bij gelijke score blijft de datumvolgorde van
  /// [_images] (nieuwste eerst) behouden.
  void _applyFilter() {
    final base = _untaggedOnly
        ? [
            for (final path in _images)
              if ((_descriptions[path] ?? '').trim().isEmpty) path,
          ]
        : _images;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = base;
      return;
    }
    final terms = q
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final hits = <({String path, int score, int order})>[];
    for (var i = 0; i < base.length; i++) {
      final score = _relevance(base[i], terms);
      if (score > 0) hits.add((path: base[i], score: score, order: i));
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });
    _filtered = [for (final h in hits) h.path];
  }

  /// Relevantiescore voor één afbeelding tegen alle zoektermen. Geeft 0 terug
  /// zodra één term nergens voorkomt (dan valt de afbeelding uit het filter).
  /// Hoger = relevanter; per term telt de sterkste match mee.
  int _relevance(String path, List<String> terms) {
    final name = p.basenameWithoutExtension(path).toLowerCase();
    final desc = (_descriptions[path] ?? '').toLowerCase();
    final splitter = RegExp(r'[^a-z0-9]+');
    final nameWords = name.split(splitter).where((w) => w.isNotEmpty);
    final descWords = desc.split(splitter).where((w) => w.isNotEmpty);

    var total = 0;
    for (final t in terms) {
      var best = 0;
      if (name == t) {
        best = 1000; // bestandsnaam is exact de zoekterm
      } else if (nameWords.contains(t)) {
        best = 600; // heel woord in de naam ("klm")
      } else if (nameWords.any((w) => w.startsWith(t))) {
        best = 400; // woord in de naam begint met de term ("kl" → "klm")
      } else if (name.contains(t)) {
        best = 200; // term zit ergens in de naam
      }
      if (best < 600) {
        if (descWords.contains(t)) {
          best = best < 500 ? 500 : best; // heel woord in de beschrijving
        } else if (descWords.any((w) => w.startsWith(t))) {
          best = best < 300 ? 300 : best; // woord-prefix in de beschrijving
        } else if (desc.contains(t)) {
          best = best < 100 ? 100 : best; // substring in de beschrijving
        }
      }
      if (best == 0) return 0; // deze term matcht nergens → wegfilteren
      total += best;
    }
    return total;
  }

  void _onSearchChanged(String value) {
    _rebuild(() {
      _query = value;
      _applyFilter();
    });
    // De indexen zijn verschoven; coverflow opnieuw uitlijnen na de rebuild.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncCoverToSelection(),
    );
  }

  /// Zet het "alleen zonder tags"-filter aan of uit, zodat snel te zien is
  /// welke afbeeldingen nog geen beschrijving/tags hebben.
  void _toggleUntaggedOnly() {
    _rebuild(() {
      _untaggedOnly = !_untaggedOnly;
      _applyFilter();
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncCoverToSelection(),
    );
  }

  /// Whether the optional AI backend is on — gates the "auto-tag untagged" action.
  bool get _aiTaggingAvailable {
    final ai = ref.read(settingsProvider).aiSettings;
    return ai.enabled && ai.isConfigured;
  }

  /// Auto-tag every *untagged* library image with AI-generated searchable keyword
  /// tags (AI_ASSIST §6), so it becomes findable. Only fills empty descriptions —
  /// never overwrites an existing (human or earlier) tag. Progress shows on the
  /// button; an undo snackbar clears exactly what this run tagged.
  Future<void> _autoTagUntagged() async {
    await _persistDescription();
    if (!mounted) return;
    final l10n = context.l10n;
    final untagged = [
      for (final path in _images)
        if ((_descriptions[path] ?? '').trim().isEmpty) path,
    ];
    if (untagged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.d('Alle afbeeldingen hebben al tags.'))),
      );
      return;
    }
    // Eerst vragen, en zeggen hoevéél en waarheen. Dit was een kale
    // icoonknop: één klik stuurde élke ongetagde afbeelding uit de bibliotheek
    // — schermafdrukken van beheerpanelen, klantsystemen, gezichten — serieel
    // naar een derde partij. De knop ernaast, die alleen lokale tekst wíst,
    // vraagt wél om bevestiging.
    //
    // Dezelfde dialoog als bij het losse alt-tekstveld, zodat er één plek is
    // waar staat wat er werkelijk weggaat — inclusief de regel dat OciDeck in
    // een afbeelding níéts weglakt. Het gezichtsaantal blijft hier op nul: dat
    // per beeld bepalen zou de hele bibliotheek moeten decoderen vóór de vraag,
    // en dan wacht de gebruiker minuten op een dialoog.
    final settings = ref.read(settingsProvider).aiSettings;
    final go = await confirmAiImageOutbound(
      context,
      title: l10n.d('Afbeeldingen door AI laten taggen?'),
      settings: settings,
      imageCount: untagged.length,
    );
    if (!go || !mounted) return;
    final tagger = ImageAltAiService(
      AiClientService(
        settings: settings,
        hasOutboundConsent: ref.read(consentProvider).hasAccepted,
        apiKey: await SecretStore().readAiApiKey(settings.baseUrl),
      ),
    );
    final imageService = ImageService();
    final langName =
        AppLocalizations.languageNames[l10n.languageCode] ?? 'English';
    final tagged = <String>[];
    _rebuild(() => _autoTagging = true);
    for (var i = 0; i < untagged.length; i++) {
      if (!mounted) break;
      _rebuild(
        () => _autoTagPhase =
            '${l10n.d('Afbeeldingen taggen…')} ${i + 1}/${untagged.length}',
      );
      try {
        final bytes = await imageService.readSlideImageBytes(untagged[i]);
        if (bytes == null) continue;
        final tags = await tagger.suggestTags(
          imageBytes: bytes,
          languageName: langName,
        );
        if (tags.isEmpty) continue;
        await widget.descriptionService.saveDescription(untagged[i], tags);
        _descriptions[untagged[i]] = tags;
        tagged.add(untagged[i]);
      } catch (e, s) {
        logError('ImageCarouselPicker._autoTagUntagged', e, s);
      }
    }
    if (!mounted) return;
    _rebuild(() {
      _autoTagging = false;
      _autoTagPhase = null;
      _applyFilter();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${tagged.length} ${l10n.d('afbeeldingen getagd door AI.')}',
        ),
        action: tagged.isEmpty
            ? null
            : SnackBarAction(
                label: l10n.d('Ongedaan maken'),
                onPressed: () => _undoAutoTag(tagged),
              ),
      ),
    );
  }

  /// Undo the last auto-tag run: clear the descriptions it wrote (a safety net
  /// for a bad bulk run — it only touches images this run tagged).
  Future<void> _undoAutoTag(List<String> paths) async {
    for (final path in paths) {
      await widget.descriptionService.removeDescription(path);
      _descriptions.remove(path);
    }
    if (mounted) _rebuild(_applyFilter);
  }

  /// Zoek byte-identieke afbeeldingen (md5), laat de gebruiker bevestigen en
  /// ruim ze op: per groep blijft één bestand staan, tags/beschrijvingen en
  /// opmerkingen/captions worden samengevoegd en slides die een verwijderde
  /// kopie gebruikten gaan naar het behouden bestand wijzen — zowel in open
  /// presentaties als in .md-bestanden op schijf binnen de zoekmappen.
  Future<void> _dedupe() async {
    await _persistDescription();
    if (!mounted) return;
    final l10n = context.l10n;
    _rebuild(() {
      _deduping = true;
      _dedupePhase = l10n.d('Afbeeldingen vergelijken…');
    });
    final dedup = ImageDedupService();
    final refs = ImageReferenceService();
    final groups = await dedup.findDuplicateGroups(
      _images,
      onProgress: (done, total) {
        if (!mounted || total == 0) return;
        _rebuild(
          () => _dedupePhase =
              '${l10n.d('Afbeeldingen vergelijken…')} '
              '$done/$total',
        );
      },
    );
    if (!mounted) return;
    if (groups.isEmpty) {
      _rebuild(() {
        _deduping = false;
        _dedupePhase = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.d('Geen dubbele afbeeldingen gevonden.')),
        ),
      );
      return;
    }

    // Ook presentaties op schijf tellen mee: zo blijft bij voorkeur het
    // bestand staan waar de meeste slides (open of niet) naar wijzen. Open
    // decks worden via usageOf geteld en hier overgeslagen.
    _rebuild(() => _dedupePhase = l10n.d('Presentaties scannen…'));
    final deckFiles = await refs.findDeckFiles(widget.searchPaths);
    final diskCounts = await refs.countReferences(
      _withoutOpenDecks(deckFiles),
      [for (final group in groups) ...group],
    );
    if (!mounted) return;

    final plan = <({String keeper, List<String> remove})>[
      for (final group in groups)
        () {
          final keeper = dedup.chooseKeeper(
            group,
            usageCountOf: (path) =>
                (widget.usageOf?.call(path).length ?? 0) +
                (diskCounts[p.normalize(path)] ?? 0),
          );
          return (
            keeper: keeper,
            remove: [
              for (final path in group)
                if (path != keeper) path,
            ],
          );
        }(),
    ];

    final confirmed = await _showDedupeDialog(plan);
    if (!mounted) return;
    if (confirmed != true) {
      _rebuild(() {
        _deduping = false;
        _dedupePhase = null;
      });
      return;
    }
    _rebuild(() => _dedupePhase = l10n.d('Opruimen…'));

    final (removed, updatedDeckFiles) = await _applyDedupePlan(
      plan,
      dedup: dedup,
      refs: refs,
      deckFiles: deckFiles,
    );

    if (!mounted) return;
    final removedSet = {for (final entry in plan) ...entry.remove};
    _rebuild(() {
      _images = [
        for (final path in _images)
          if (!removedSet.contains(path)) path,
      ];
      _descEditing = null;
      if (_selected != null && removedSet.contains(_selected)) {
        _selected = plan
            .firstWhere((entry) => entry.remove.contains(_selected))
            .keeper;
      }
      _deduping = false;
      _dedupePhase = null;
      _applyFilter();
    });
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
    if (!mounted) return;
    final removedText = removed == 1
        ? l10n.d('1 dubbele afbeelding verwijderd.')
        : '$removed ${l10n.d('dubbele afbeeldingen verwijderd.')}';
    final filesText = updatedDeckFiles.isEmpty
        ? ''
        : updatedDeckFiles.length == 1
        ? '  ·  ${l10n.d('1 presentatiebestand bijgewerkt.')}'
        : '  ·  ${updatedDeckFiles.length} ${l10n.d('presentatiebestanden bijgewerkt.')}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$removedText$filesText')));
  }

  /// Voer het bevestigde opruimplan uit: metadata samenvoegen op de keeper,
  /// verwijzingen (open én op schijf) omzetten en de kopieën wissen. Geeft
  /// (aantal verwijderd, bijgewerkte deckbestanden) terug.
  Future<(int, Set<String>)> _applyDedupePlan(
    List<({String keeper, List<String> remove})> plan, {
    required ImageDedupService dedup,
    required ImageReferenceService refs,
    required List<String> deckFiles,
  }) async {
    var removed = 0;
    final updatedDeckFiles = <String>{};
    // Eén replacement-map over het hele plan: iedere te verwijderen kopie → haar
    // keeper. Zo hoeft elk deckbestand maar één keer gelezen en geschreven te
    // worden, ongeacht hoeveel kopieën er verdwijnen (#1052).
    final replacements = <String, String>{};
    for (final entry in plan) {
      // Keeper eerst, zodat zijn eigen tekst vooraan blijft staan.
      final ordered = [entry.keeper, ...entry.remove];
      final captions = <String?>[
        for (final path in ordered)
          await widget.captionService.getCaption(path),
      ];
      final mergedCaption = dedup.mergeMetadata(captions);
      final mergedDescription = dedup.mergeMetadata([
        for (final path in ordered) _descriptions[path],
      ], separator: ', ');
      if (mergedCaption.isNotEmpty) {
        await widget.captionService.saveCaption(entry.keeper, mergedCaption);
      }
      if (mergedDescription.isNotEmpty) {
        _descriptions[entry.keeper] = mergedDescription;
        await widget.descriptionService.saveDescription(
          entry.keeper,
          mergedDescription,
        );
      }
      for (final path in entry.remove) {
        replacements[path] = entry.keeper;
        // Open decks in het geheugen meteen mee laten wijzen.
        await widget.onReplaceUsages?.call(path, entry.keeper);
        try {
          final file = File(path);
          if (file.existsSync()) await file.delete();
        } catch (e) {
          logWarning('_ImageCarouselPickerState._dedupe: delete file', e);
        }
        await widget.captionService.saveCaption(path, '');
        await widget.descriptionService.removeDescription(path);
        _descriptions.remove(path);
        removed++;
      }
    }
    // Ook niet-geopende presentaties op schijf laten meewijzen — nu één pass per
    // deckbestand, met alle vervangingen tegelijk.
    for (final deckFile in deckFiles) {
      if (await refs.replaceReferencesMulti(deckFile, replacements)) {
        updatedDeckFiles.add(deckFile);
      }
    }
    return (removed, updatedDeckFiles);
  }

  Future<bool?> _showDedupeDialog(
    List<({String keeper, List<String> remove})> plan,
  ) {
    final removeCount = plan.fold(0, (sum, e) => sum + e.remove.length);
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          backgroundColor: ImagePickerPalette.surface1,
          title: Row(
            children: [
              const Icon(
                Icons.layers_clear_outlined,
                color: AppTheme.blue400,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${l10n.d('Dubbele afbeeldingen opruimen?')} ($removeCount)',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.d(
                    'Van elke groep blijft één bestand staan. Tags en opmerkingen worden samengevoegd en slides die een kopie gebruiken verwijzen daarna naar het behouden bestand — ook in presentaties die nu niet geopend zijn.',
                  ),
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in plan) ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                size: 14,
                                color: ImagePickerPalette.success,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  p.basename(entry.keeper),
                                  style: const TextStyle(
                                    color: ImagePickerPalette.text,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          for (final path in entry.remove)
                            Padding(
                              padding: const EdgeInsets.only(left: 20, top: 2),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.delete_outline,
                                    size: 13,
                                    color: ImagePickerPalette.dangerSoft,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      p.basename(path),
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: _muted),
              child: Text(l10n.t('cancel')),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.layers_clear_outlined, size: 16),
              label: Text(l10n.d('Opruimen')),
              style: ElevatedButton.styleFrom(
                backgroundColor: ImagePickerPalette.successStrong,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirm() async {
    // In beheermodus is er niets om te kiezen: Enter en dubbelklik mogen de
    // dialoog dan niet met een (zinloos) resultaat sluiten.
    if (widget.manageOnly) return;
    if (_selected == null) return;
    await _persistDescription();
    await widget.captionService.saveCaption(_selected!, _caption);
    if (mounted) {
      Navigator.pop(context, ImagePickResult(_selected!, _caption.trim()));
    }
  }

  /// Persist the description currently in the editor, then close the dialog.
  Future<void> _close([ImagePickResult? result]) async {
    await _persistDescription();
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _persistDescription() async {
    final path = _descEditing;
    if (path == null) return;
    final text = _descriptionController.text.trim();
    _descriptions[path] = text;
    await widget.descriptionService.saveDescription(path, text);
  }

  void _loadDescriptionForSelection() {
    final path = _selected;
    _descEditing = path;
    _descriptionController.text = path == null
        ? ''
        : (_descriptions[path] ?? '');
  }

  Future<void> _browse() async {
    // Las hier `.path` uit een eigen FilePicker-aanroep; op web is dat een
    // blob:-URL die nergens heen wijst, terwijl de app een mem:-sleutel
    // verwacht. ImageService kent die route al, mét grens en inhoudscontrole
    // (#526).
    final path = (await ImageService().pickImageDetailed()).path;
    if (path == null || !mounted) return;
    final caption = await widget.captionService.getCaption(path) ?? '';
    if (!mounted) return;
    await _close(ImagePickResult(path, caption));
  }

  /// Voeg een map toe als zoekwortel: scant opnieuw en bewaart hem als
  /// lokale verbinding in Instellingen, zodat de volgende keer dezelfde
  /// beelden er staan (bijv. wanneer `/Volumes/…` offline is).
  Future<void> _addLibraryFolder() async {
    final l10n = context.l10n;
    // Zelfde poort als elders: op web bestaat getDirectoryPath niet.
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.d('Kies een map met afbeeldingen'),
    );
    if (picked == null || !mounted) return;
    if (_extraRoots.contains(picked) || widget.searchPaths.contains(picked)) {
      return;
    }
    _rebuild(() {
      _extraRoots.add(picked);
      _loading = true;
      _images = [];
      _filtered = [];
    });
    await ref
        .read(settingsProvider.notifier)
        .addLibrary(p.basename(picked), picked);
    if (!mounted) return;
    await _loadImages();
  }

  Future<void> _select(String path) async {
    await _persistDescription();
    if (!mounted) return;
    _rebuild(() => _selected = path);
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
  }

  Future<void> _loadCaptionForSelection() async {
    final path = _selected;
    final caption = path == null
        ? ''
        : (await widget.captionService.getCaption(path) ?? '');
    if (!mounted || path != _selected) return;
    _rebuild(() {
      _caption = caption;
      _captionController.text = caption;
    });
  }

  void _moveSelection(int delta) {
    if (_filtered.isEmpty) return;
    final current = _selected == null ? -1 : _filtered.indexOf(_selected!);
    final next = (current + delta).clamp(0, _filtered.length - 1);
    if (_viewMode == _ViewMode.cover && _pageController?.hasClients == true) {
      // De PageView is leidend: animeren triggert onPageChanged → _select.
      _pageController!.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _select(_filtered[next]);
    _scrollToIndex(next);
  }

  /// Wissel tussen raster- en coverflow-weergave. Maakt (of ruimt) de
  /// PageController op en zet de flow op de huidige selectie.
  void _setViewMode(_ViewMode mode) {
    if (mode == _viewMode) return;
    _rebuild(() {
      _viewMode = mode;
      _pageController?.dispose();
      if (mode == _ViewMode.cover) {
        final idx = _selected == null ? 0 : _filtered.indexOf(_selected!);
        _pageController = PageController(
          initialPage: idx < 0 ? 0 : idx,
          viewportFraction: 0.62,
        );
      } else {
        _pageController = null;
      }
    });
  }

  /// Zet de coverflow zonder animatie op de huidige selectie. Nodig nadat het
  /// filter de lijst (en dus de indexen) heeft veranderd.
  void _syncCoverToSelection() {
    if (_viewMode != _ViewMode.cover) return;
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final idx = _selected == null ? 0 : _filtered.indexOf(_selected!);
    controller.jumpToPage(idx < 0 ? 0 : idx);
  }

  /// Kopieer de geselecteerde afbeelding naar het klembord (om elders te
  /// plakken) met korte "Gekopieerd"-feedback op de knop.
  Future<void> _copySelectedToClipboard() async {
    final path = _selected;
    if (path == null) return;
    final ok = await ImageService().copyImageToClipboard(path);
    if (!mounted) return;
    if (ok) {
      _rebuild(() => _justCopied = true);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _rebuild(() => _justCopied = false);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.d('Kopiëren naar klembord mislukt.')),
        ),
      );
    }
  }

  /// Filter de deckbestanden op schijf die niet in een tab geopend zijn
  /// (open decks zijn al gedekt door [ImageCarouselPicker.usageOf]).
  List<String> _withoutOpenDecks(List<String> deckFiles) {
    final open = {for (final f in widget.openDeckFiles) p.normalize(f)};
    return [
      for (final f in deckFiles)
        if (!open.contains(p.normalize(f))) f,
    ];
  }
}
