// Part of the image_carousel_picker library — see ../image_carousel_picker.dart.
// Split out for navigability (delete flow & scroll-to-index); all imports live in the main library
// file. Instance methods relocate verbatim into an extension on
// _ImageCarouselPickerState — same library, same members, no behaviour change.
part of '../image_carousel_picker.dart';

extension _CarouselDelete on _ImageCarouselPickerState {
  Future<void> _deleteSelected() async {
    final path = _selected;
    if (path == null) return;
    final usages = [...widget.usageOf?.call(path) ?? const <String>[]];
    var slideCount = usages.length;
    // Ook niet-geopende presentaties op schijf meenemen in de waarschuwing.
    final refs = ImageReferenceService();
    final onDisk = await refs.referencingFiles(
      _withoutOpenDecks(await refs.findDeckFiles(widget.searchPaths)),
      path,
    );
    if (!mounted) return;
    final notOpen = context.l10n.d('niet geopend');
    for (final entry in onDisk.entries) {
      slideCount += entry.value;
      usages.add(
        entry.value == 1
            ? '${p.basename(entry.key)} · $notOpen'
            : '${p.basename(entry.key)} · ${entry.value}× · $notOpen',
      );
    }
    final confirmed = await _showDeleteDialog(path, usages, slideCount);
    if (confirmed != true) return;

    var deleted = false;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
      deleted = true;
    } catch (e) {
      logWarning('ImageCarouselPicker: kon afbeelding niet verwijderen', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.d(
                'Kon de afbeelding niet verwijderen. Controleer of het bestand niet in gebruik is en of je schrijfrechten hebt.',
              ),
            ),
          ),
        );
      }
    }
    // Only drop the sidecar metadata and the carousel entry once the file is
    // actually gone; otherwise the image would disappear from the UI while it
    // still exists on disk, having silently lost its caption/description.
    if (!deleted) return;
    await widget.captionService.saveCaption(path, '');
    await widget.descriptionService.removeDescription(path);

    if (!mounted) return;
    final idx = _images.indexOf(path);
    _rebuild(() {
      _images = List.of(_images)..remove(path);
      _descriptions.remove(path);
      _descEditing = null;
      if (_selected == path) {
        _selected = _images.isEmpty
            ? null
            : _images[idx.clamp(0, _images.length - 1)];
      }
      _applyFilter();
    });
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
  }

  Future<bool?> _showDeleteDialog(
    String path,
    List<String> usages,
    int slideCount,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          backgroundColor: ImagePickerPalette.surface1,
          title: Row(
            children: [
              Icon(
                usages.isEmpty
                    ? Icons.delete_outline
                    : Icons.warning_amber_rounded,
                color: usages.isEmpty
                    ? ImagePickerPalette.danger
                    : ImagePickerPalette.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.d('Afbeelding verwijderen?'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.basename(path),
                style: const TextStyle(
                  color: ImagePickerPalette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (usages.isEmpty)
                Text(
                  l10n.d(
                    'Het bestand wordt permanent van schijf verwijderd. Deze actie kan niet ongedaan worden gemaakt.',
                  ),
                  style: const TextStyle(color: _muted, fontSize: 13),
                )
              else ...[
                Text(
                  '${l10n.d('Let op: deze afbeelding wordt nog gebruikt in')} $slideCount ${slideCount == 1 ? l10n.d("slide") : l10n.t("slides")}:',
                  style: const TextStyle(
                    color: ImagePickerPalette.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final u in usages)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '•  $u',
                              style: const TextStyle(
                                color: ImagePickerPalette.text,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.d(
                    'Verwijderen maakt die slides leeg. Dit kan niet ongedaan worden gemaakt.',
                  ),
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: _muted),
              child: Text(l10n.t('cancel')),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(l10n.d('Verwijderen')),
              style: ElevatedButton.styleFrom(
                backgroundColor: ImagePickerPalette.dangerStrong,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  void _scrollToIndex(int index) {
    // Approximate thumbnail height for 3-column grid
    const cols = 3;
    const thumbH = 160.0;
    const spacing = 12.0;
    final row = index ~/ cols;
    final offset = row * (thumbH + spacing);
    _gridScrollController.animateTo(
      offset.clamp(0.0, _gridScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
}
