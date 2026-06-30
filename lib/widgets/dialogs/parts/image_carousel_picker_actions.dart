// Part of the image_carousel_picker library — see ../image_carousel_picker.dart.
// Split out for navigability (scan, filter, dedupe, selection & clipboard actions); all imports live in the main library
// file. Instance methods relocate verbatim into an extension on
// _ImageCarouselPickerState — same library, same members, no behaviour change.
part of '../image_carousel_picker.dart';

extension _CarouselActions on _ImageCarouselPickerState {
  Future<void> _loadImages() async {
    final found = <String>{};

    for (final path in widget.searchPaths) {
      if (path.isEmpty) continue;
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      try {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            final ext = p.extension(e.path).toLowerCase();
            if (_ImageCarouselPickerState._exts.contains(ext)) {
              found.add(e.path);
            }
          }
        }
      } catch (e) {
        logWarning('_ImageCarouselPickerState._loadImages: directory scan', e);
      }
    }

    // Stat each file exactly once (instead of repeatedly inside the sort
    // comparator) so large libraries stay responsive.
    final withTimes = <(String, DateTime)>[];
    for (final path in found) {
      DateTime modified;
      try {
        modified = File(path).statSync().modified;
      } catch (e) {
        logWarning('_ImageCarouselPickerState._loadImages: statSync', e);
        modified = DateTime.fromMillisecondsSinceEpoch(0);
      }
      withTimes.add((path, modified));
    }
    withTimes.sort((a, b) => b.$2.compareTo(a.$2));
    final sorted = [for (final e in withTimes) e.$1];

    final descriptions = await widget.descriptionService.loadFor(sorted);

    if (!mounted) return;
    _rebuild(() {
      _images = sorted;
      _descriptions = descriptions;
      _loading = false;
      _selected =
          widget.initialPath ?? (sorted.isNotEmpty ? sorted.first : null);
      _applyFilter();
    });
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
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

  /// Zoek byte-identieke afbeeldingen (md5), laat de gebruiker bevestigen en
  /// ruim ze op: per groep blijft één bestand staan, tags/beschrijvingen en
  /// opmerkingen/captions worden samengevoegd en slides die een verwijderde
  /// kopie gebruikten gaan naar het behouden bestand wijzen — zowel in open
  /// presentaties als in .md-bestanden op schijf binnen de zoekmappen.
  Future<void> _dedupe() async {
    await _persistDescription();
    if (!mounted) return;
    _rebuild(() => _deduping = true);
    final dedup = ImageDedupService();
    final refs = ImageReferenceService();
    final groups = await dedup.findDuplicateGroups(_images);
    if (!mounted) return;
    if (groups.isEmpty) {
      _rebuild(() => _deduping = false);
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
      _rebuild(() => _deduping = false);
      return;
    }

    var removed = 0;
    final updatedDeckFiles = <String>{};
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
        await widget.onReplaceUsages?.call(path, entry.keeper);
        // Ook niet-geopende presentaties op schijf laten meewijzen.
        for (final deckFile in deckFiles) {
          final updated = await refs.replaceReferences(
            deckFile,
            path,
            entry.keeper,
          );
          if (updated) updatedDeckFiles.add(deckFile);
        }
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
      _applyFilter();
    });
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
    if (!mounted) return;
    final l10n = context.l10n;
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

  Future<bool?> _showDedupeDialog(
    List<({String keeper, List<String> remove})> plan,
  ) {
    final removeCount = plan.fold(0, (sum, e) => sum + e.remove.length);
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: Row(
            children: [
              const Icon(
                Icons.layers_clear_outlined,
                color: Color(0xFF60A5FA),
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
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 13,
                  ),
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
                                color: Color(0xFF22C55E),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  p.basename(entry.keeper),
                                  style: const TextStyle(
                                    color: Color(0xFFCDD9E5),
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
                                    color: Color(0xFFE5746E),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      p.basename(path),
                                      style: const TextStyle(
                                        color: Color(0xFF8B949E),
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
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8B949E),
              ),
              child: Text(l10n.t('cancel')),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.layers_clear_outlined, size: 16),
              label: Text(l10n.d('Opruimen')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirm() async {
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
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: context.l10n.d('Kies een afbeelding'),
    );
    if (result?.files.single.path != null && mounted) {
      final path = result!.files.single.path!;
      final caption = await widget.captionService.getCaption(path) ?? '';
      await _close(ImagePickResult(path, caption));
    }
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
