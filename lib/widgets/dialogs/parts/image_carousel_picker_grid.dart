// Part of the image_carousel_picker library — see ../image_carousel_picker.dart.
// Split out for navigability (grid, thumbnails & cover flow); all imports live in the main library
// file. Instance methods relocate verbatim into an extension on
// _ImageCarouselPickerState — same library, same members, no behaviour change.
part of '../image_carousel_picker.dart';

extension _CarouselGrid on _ImageCarouselPickerState {
  Widget _buildGrid() {
    if (_filtered.isEmpty) return _buildEmptyState();

    return Expanded(
      flex: 13,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: ImagePickerPalette.surface2)),
        ),
        child: GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 4 / 3,
          ),
          itemCount: _filtered.length,
          itemBuilder: (_, i) => _buildThumbnail(i),
        ),
      ),
    );
  }

  Widget _buildThumbnail(int index) {
    final path = _filtered[index];
    final isSelected = path == _selected;
    final isHovered = index == _hoveredIndex;
    final name = p.basenameWithoutExtension(path);

    return MouseRegion(
      onEnter: (_) => _rebuild(() => _hoveredIndex = index),
      onExit: (_) => _rebuild(() => _hoveredIndex = -1),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _select(path),
        onDoubleTap: () async {
          await _select(path);
          await _confirm();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: Matrix4.identity()
            ..scaleByDouble(
              isHovered && !isSelected ? 1.03 : 1.0,
              isHovered && !isSelected ? 1.03 : 1.0,
              1,
              1,
            ),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppTheme.blue500
                  : isHovered
                  ? ImagePickerPalette.accent
                  : ImagePickerPalette.surface2,
              width: isSelected
                  ? 2.5
                  : isHovered
                  ? 1.5
                  : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.blue500.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Thumbnail
                Image(
                  image: boundedFileImage(File(path), 360),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: ImagePickerPalette.surface1,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: ImagePickerPalette.border,
                      size: 32,
                    ),
                  ),
                ),
                // Hover-glans overlay
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: isHovered && !isSelected ? 0.12 : 0,
                  child: Container(color: Colors.white),
                ),
                // Naam onderaan
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: isHovered || isSelected ? 1 : 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.82),
                          ],
                        ),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                // Selectie-vinkje
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppTheme.blue500,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: ImagePickerPalette.accentStrong,
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Coverflow ───────────────────────────────────────────────────────────

  Widget _buildCover() {
    if (_filtered.isEmpty) return _buildEmptyState();

    final controller = _pageController;
    final selectedIndex = _selected == null
        ? -1
        : _filtered.indexOf(_selected!);

    return Expanded(
      flex: 13,
      child: Container(
        decoration: BoxDecoration(
          // Subtiele verticale gloed voor de "podium"-look.
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.1,
            colors: [ImagePickerPalette.overlay, ImagePickerPalette.bgDeep],
          ),
          border: Border(right: BorderSide(color: ImagePickerPalette.surface2)),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (controller != null)
                    PageView.builder(
                      controller: controller,
                      itemCount: _filtered.length,
                      onPageChanged: (i) {
                        if (i >= 0 && i < _filtered.length) {
                          _select(_filtered[i]);
                        }
                      },
                      itemBuilder: (_, i) => _buildCoverCard(i, controller),
                    ),
                  // Navigatiepijlen links/rechts.
                  Positioned(
                    left: 12,
                    child: _coverArrow(
                      Icons.chevron_left_rounded,
                      selectedIndex > 0,
                      () => _moveSelection(-1),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    child: _coverArrow(
                      Icons.chevron_right_rounded,
                      selectedIndex >= 0 &&
                          selectedIndex < _filtered.length - 1,
                      () => _moveSelection(1),
                    ),
                  ),
                ],
              ),
            ),
            _buildCoverStrip(selectedIndex),
          ],
        ),
      ),
    );
  }

  /// Eén kaart in de flow. De schaal, perspectiefdraaiing en transparantie
  /// hangen af van de afstand tot het midden van de viewport.
  Widget _buildCoverCard(int index, PageController controller) {
    final path = _filtered[index];
    final isSelected = path == _selected;
    final name = p.basenameWithoutExtension(path);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Hoever staat deze kaart van het midden? (0 = gecentreerd)
        double page;
        if (controller.hasClients && controller.position.haveDimensions) {
          page = controller.page ?? controller.initialPage.toDouble();
        } else {
          page = controller.initialPage.toDouble();
        }
        final delta = (page - index).clamp(-1.5, 1.5);
        final dist = delta.abs();
        final centered = (1 - dist.clamp(0.0, 1.0));

        final scale = 0.74 + 0.26 * centered;
        final opacity = 0.35 + 0.65 * centered;
        final rotateY = delta * 0.55; // radialen, perspectief

        return Center(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0014) // perspectief
                ..rotateY(-rotateY)
                ..scaleByDouble(scale, scale, 1, 1),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            // Klik op een buur centreert die; klik op het midden bevestigt.
            onTap: () {
              if (isSelected) {
                _confirm();
              } else {
                final target = _filtered.indexOf(path);
                if (target >= 0 && controller.hasClients) {
                  controller.animateToPage(
                    target,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                  );
                }
              }
            },
            onDoubleTap: () async {
              await _select(path);
              await _confirm();
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.blue500
                      : ImagePickerPalette.surface2,
                  width: isSelected ? 2.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AppTheme.blue500.withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.55),
                    blurRadius: isSelected ? 40 : 24,
                    spreadRadius: isSelected ? 2 : 0,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: boundedFileImage(File(path), 1000),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: ImagePickerPalette.surface1,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: ImagePickerPalette.border,
                          size: 48,
                        ),
                      ),
                    ),
                    // Naamlabel onderaan de centrale kaart.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: isSelected ? 1 : 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 30, 16, 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.78),
                              ],
                            ),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverArrow(IconData icon, bool enabled, VoidCallback onTap) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.0,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Material(
          color: ImagePickerPalette.surface1.withValues(alpha: 0.85),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ImagePickerPalette.border),
              ),
              child: Icon(icon, color: ImagePickerPalette.text, size: 24),
            ),
          ),
        ),
      ),
    );
  }

  /// Positie-indicator onder de flow ("3 / 28") plus een dunne voortgangsbalk.
  Widget _buildCoverStrip(int selectedIndex) {
    final total = _filtered.length;
    final pos = selectedIndex < 0 ? 0 : selectedIndex;
    final progress = total <= 1 ? 1.0 : pos / (total - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(height: 3, color: ImagePickerPalette.surface2),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.blue500, AppTheme.blue400],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${pos + 1} / $total',
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
