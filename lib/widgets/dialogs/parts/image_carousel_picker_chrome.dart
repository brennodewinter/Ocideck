// Part of the image_carousel_picker library — see ../image_carousel_picker.dart.
// Split out for navigability (loading, header, search, toggles & empty state); all imports live in the main library
// file. Instance methods relocate verbatim into an extension on
// _ImageCarouselPickerState — same library, same members, no behaviour change.
part of '../image_carousel_picker.dart';

extension _CarouselChrome on _ImageCarouselPickerState {
  Widget _buildLoading() {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppTheme.blue500),
          const SizedBox(height: 16),
          Text(
            l10n.d('Afbeeldingen laden…'),
            style: TextStyle(color: ImagePickerPalette.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = context.l10n;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ImagePickerPalette.surface2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ImagePickerPalette.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: AppTheme.blue400,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            widget.manageOnly
                ? l10n.d('Afbeeldingen beheren')
                : l10n.d('Afbeelding kiezen'),
            style: TextStyle(
              color: ImagePickerPalette.text,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ImagePickerPalette.surface2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _query.trim().isEmpty && !_untaggedOnly
                  ? '${_images.length}'
                  : '${_filtered.length} / ${_images.length}',
              style: TextStyle(
                color: ImagePickerPalette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildSearchField()),
          const SizedBox(width: 12),
          _buildUntaggedToggle(),
          if (_aiTaggingAvailable) ...[
            const SizedBox(width: 12),
            _buildAutoTagButton(),
          ],
          const SizedBox(width: 12),
          _buildViewToggle(),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(
              Icons.close,
              color: ImagePickerPalette.iconDim,
              size: 20,
            ),
            onPressed: () => _close(),
            tooltip: l10n.d('Sluiten (Esc)'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final l10n = context.l10n;
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(color: ImagePickerPalette.text, fontSize: 13),
        decoration: InputDecoration(
          hintText: l10n.d('Zoek op naam of beschrijving…'),
          hintStyle: TextStyle(
            color: ImagePickerPalette.textMuted,
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: ImagePickerPalette.iconDim,
            size: 18,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.d('Zoekopdracht wissen'),
                  icon: Icon(
                    Icons.clear,
                    color: ImagePickerPalette.iconDim,
                    size: 16,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: ImagePickerPalette.bg,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ImagePickerPalette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ImagePickerPalette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.blue500),
          ),
        ),
      ),
    );
  }

  /// Aan/uit-knop voor het filter "alleen afbeeldingen zonder tags". Handig om
  /// AI-knop om alle nog ongetagde afbeeldingen automatisch van zoek-tags te
  /// voorzien (AI_ASSIST §6). Tijdens het taggen toont 'ie de voortgang; alleen
  /// zichtbaar als de AI-backend aanstaat.
  Widget _buildAutoTagButton() {
    final l10n = context.l10n;
    if (_autoTagging) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            _autoTagPhase ?? l10n.d('Afbeeldingen taggen…'),
            style: TextStyle(color: ImagePickerPalette.textMuted, fontSize: 12),
          ),
        ],
      );
    }
    return IconButton(
      icon: Icon(
        Icons.auto_awesome_outlined,
        color: ImagePickerPalette.iconDim,
        size: 20,
      ),
      onPressed: _autoTagUntagged,
      tooltip: l10n.d('Ongetagde afbeeldingen taggen met AI'),
    );
  }

  /// te zien welke afbeeldingen nog een beschrijving/tags nodig hebben.
  Widget _buildUntaggedToggle() {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.d('Alleen afbeeldingen zonder tags tonen'),
      child: GestureDetector(
        onTap: _toggleUntaggedOnly,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _untaggedOnly
                ? ImagePickerPalette.surfaceAlt
                : ImagePickerPalette.bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _untaggedOnly
                  ? AppTheme.blue500
                  : ImagePickerPalette.border,
            ),
          ),
          child: Icon(
            Icons.label_off_outlined,
            size: 17,
            color: _untaggedOnly
                ? AppTheme.blue400
                : ImagePickerPalette.iconDim,
          ),
        ),
      ),
    );
  }

  /// Segmented control om tussen raster- en coverflow-weergave te wisselen.
  Widget _buildViewToggle() {
    final l10n = context.l10n;
    Widget seg(_ViewMode mode, IconData icon, String tip) {
      final active = _viewMode == mode;
      return Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => _setViewMode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? ImagePickerPalette.surfaceAlt
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              icon,
              size: 17,
              color: active ? AppTheme.blue400 : ImagePickerPalette.iconDim,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ImagePickerPalette.bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: ImagePickerPalette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(_ViewMode.grid, Icons.grid_view_rounded, l10n.d('Raster')),
          const SizedBox(width: 3),
          seg(
            _ViewMode.cover,
            Icons.view_carousel_rounded,
            l10n.d('Coverflow'),
          ),
        ],
      ),
    );
  }

  /// Lege staat — gedeeld door raster- en coverflow-weergave.
  Widget _buildEmptyState() {
    final l10n = context.l10n;
    if (_untaggedOnly && _query.trim().isEmpty) {
      return Expanded(
        flex: 13,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_outlined,
                size: 56,
                color: ImagePickerPalette.success,
              ),
              const SizedBox(height: 20),
              Text(
                l10n.d('Alle afbeeldingen hebben tags.'),
                style: TextStyle(
                  color: ImagePickerPalette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.d('Zet het filter uit om alles weer te zien.'),
                style: TextStyle(
                  color: ImagePickerPalette.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final filtering = _query.trim().isNotEmpty;
    return Expanded(
      flex: 13,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: ImagePickerPalette.surface1,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.image_search_outlined,
                size: 56,
                color: ImagePickerPalette.border,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              filtering
                  ? '${l10n.d('Geen resultaten voor')} "${_query.trim()}"'
                  : _rootsUnreachable
                  ? l10n.d('Bibliotheekmap niet bereikbaar')
                  : l10n.d('Geen afbeeldingen gevonden'),
              style: TextStyle(
                color: ImagePickerPalette.text,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filtering
                  ? l10n.d('Pas je zoekterm aan of voeg een beschrijving toe.')
                  : _rootsUnreachable
                  ? l10n.d(
                      'De map uit Instellingen is offline of verplaatst. Kies hier een map met afbeeldingen.',
                    )
                  : widget.manageOnly
                  ? l10n.d(
                      'Er staan nog geen afbeeldingen in je bibliotheekmappen.',
                    )
                  : l10n.d(
                      'Voeg een map toe of gebruik "Bladeren" voor één bestand.',
                    ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ImagePickerPalette.textMuted,
                fontSize: 13,
              ),
            ),
            if (!filtering) ...[
              const SizedBox(height: 20),
              // De lege bibliotheek vraagt om twee handelingen: een afbeelding
              // erin zetten (beheermodus) of een extra zoekwortel kiezen.
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (widget.manageOnly && supportsLocalProjectFolders)
                    FilledButton.icon(
                      onPressed: _addImageFromFile,
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 18,
                      ),
                      label: Text(l10n.d('Afbeelding toevoegen…')),
                    ),
                  FilledButton.icon(
                    onPressed: _addLibraryFolder,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: Text(l10n.d('Map toevoegen…')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// De bevestigingsdialoog voor `_dedupe` in de actions-part: somt per groep
/// op welke kopieën weggaan en welk bestand blijft staan.
///
/// Top-level zoals [_metaField]: hij gebruikt geen instantietoestand — context
/// en het plan komen mee als parameters — dus hij hoort niet op de State en
/// telt niet mee voor de klassegrootte-ratchet.
Future<bool?> _showDedupeDialog(
  BuildContext context,
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
                style: TextStyle(color: ImagePickerPalette.text, fontSize: 16),
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
                style: TextStyle(color: _muted, fontSize: 13),
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
                            Icon(
                              Icons.check_circle_outline,
                              size: 14,
                              color: ImagePickerPalette.success,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                p.basename(entry.keeper),
                                style: TextStyle(
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
                                Icon(
                                  Icons.delete_outline,
                                  size: 13,
                                  color: ImagePickerPalette.dangerSoft,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    p.basename(path),
                                    style: TextStyle(
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
