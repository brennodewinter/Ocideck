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
            style: const TextStyle(
              color: ImagePickerPalette.textMuted,
              fontSize: 14,
            ),
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
      decoration: const BoxDecoration(
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
            l10n.d('Afbeelding kiezen'),
            style: const TextStyle(
              color: Colors.white,
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
              style: const TextStyle(
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
          const SizedBox(width: 12),
          _buildViewToggle(),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(
              Icons.close,
              color: ImagePickerPalette.textDim,
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
        style: const TextStyle(color: ImagePickerPalette.text, fontSize: 13),
        decoration: InputDecoration(
          hintText: l10n.d('Zoek op naam of beschrijving…'),
          hintStyle: const TextStyle(
            color: ImagePickerPalette.textDim,
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: ImagePickerPalette.textDim,
            size: 18,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.d('Zoekopdracht wissen'),
                  icon: const Icon(
                    Icons.clear,
                    color: ImagePickerPalette.textDim,
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
            borderSide: const BorderSide(color: ImagePickerPalette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: ImagePickerPalette.border),
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
                : ImagePickerPalette.textDim,
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
              color: active ? AppTheme.blue400 : ImagePickerPalette.textDim,
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
              const Icon(
                Icons.verified_outlined,
                size: 56,
                color: ImagePickerPalette.success,
              ),
              const SizedBox(height: 20),
              Text(
                l10n.d('Alle afbeeldingen hebben tags.'),
                style: const TextStyle(
                  color: ImagePickerPalette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.d('Zet het filter uit om alles weer te zien.'),
                style: const TextStyle(
                  color: ImagePickerPalette.textDim,
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
              child: const Icon(
                Icons.image_search_outlined,
                size: 56,
                color: ImagePickerPalette.border,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              filtering
                  ? '${l10n.d('Geen resultaten voor')} "${_query.trim()}"'
                  : l10n.d('Geen afbeeldingen gevonden'),
              style: const TextStyle(
                color: ImagePickerPalette.text,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filtering
                  ? l10n.d('Pas je zoekterm aan of voeg een beschrijving toe.')
                  : l10n.d(
                      'Gebruik "Bladeren" om afbeeldingen van elke locatie te kiezen.',
                    ),
              style: const TextStyle(
                color: ImagePickerPalette.textDim,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
