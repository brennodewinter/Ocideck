// Part of the image_carousel_picker library — see ../image_carousel_picker.dart.
// Split out for navigability (rename flow); all imports live in the main library
// file. Instance methods relocate verbatim into an extension on
// _ImageCarouselPickerState — same library, same members, no behaviour change.
part of '../image_carousel_picker.dart';

extension _CarouselRename on _ImageCarouselPickerState {
  /// Hernoemt de geselecteerde afbeelding: opent een dialoog die de stam laat
  /// bewerken (extensie vast), verplaatst het bestand, wijst verwijzingen in
  /// open decks en op schijf mee, en migreert caption/beschrijving. Het
  /// blauwdruk is de dedup-flow — alleen verplaatst hier één bestand naar zijn
  /// eigen nieuwe naam in plaats van weg te gaan.
  Future<void> _renameSelected() async {
    final path = _selected;
    if (path == null) return;
    final l10n = context.l10n;
    final oldStem = p.basenameWithoutExtension(path);
    final ext = p.extension(path);

    final newName = await _showRenameDialog(oldStem: oldStem, ext: ext);
    if (newName == null || !mounted) return;

    final service = ImageRenameService();
    final deckFiles = await ImageReferenceService().findDeckFiles(
      widget.searchPaths,
    );
    if (!mounted) return;
    final result = await service.rename(
      oldPath: path,
      newStem: newName,
      deckFiles: _withoutOpenDecks(deckFiles),
      captionService: widget.captionService,
      descriptionService: widget.descriptionService,
    );
    if (!mounted) return;

    if (result.failure != null || result.newPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d(
              'Kon de afbeelding niet hernoemen. Bestaat er al een bestand met die naam?',
            ),
          ),
        ),
      );
      return;
    }

    // Open decks meewijzen — dezelfde callback als bij dedup.
    await widget.onReplaceUsages?.call(path, result.newPath!);

    if (!mounted) return;
    _rebuild(() {
      final idx = _images.indexOf(path);
      if (idx >= 0) _images[idx] = result.newPath!;
      // Beschrijving meeverhuizen in de in-memory map; de sidecar op schijf
      // is al gemigreerd door de service.
      final desc = _descriptions.remove(path);
      if (desc != null) _descriptions[result.newPath!] = desc;
      _selected = result.newPath;
      _descEditing = result.newPath;
      _applyFilter();
    });
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();

    if (!mounted) return;
    final filesText = result.updatedDeckFiles.isEmpty
        ? ''
        : result.updatedDeckFiles.length == 1
        ? '  ·  ${l10n.d('1 presentatiebestand bijgewerkt.')}'
        : '  ·  ${result.updatedDeckFiles.length} ${l10n.d('presentatiebestanden bijgewerkt.')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${l10n.d('Hernoemd naar')} ${p.basename(result.newPath!)}$filesText',
        ),
      ),
    );
  }

  Future<String?> _showRenameDialog({
    required String oldStem,
    required String ext,
  }) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: oldStem)
      ..selection = TextSelection(baseOffset: 0, extentOffset: oldStem.length);

    String? errorText() {
      final validation = ImageRenameService.validateStem(
        controller.text,
        oldStem,
      );
      if (validation == RenameValidation.invalidName) {
        return l10n.d('De naam mag geen mappen of bijzondere tekens bevatten.');
      }
      return null;
    }

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            final validation = ImageRenameService.validateStem(
              controller.text,
              oldStem,
            );
            final canConfirm = validation == RenameValidation.ok;
            return AlertDialog(
              backgroundColor: ImagePickerPalette.surface1,
              title: Row(
                children: [
                  Icon(Icons.edit_outlined, color: AppTheme.blue400, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    l10n.d('Naam wijzigen'),
                    style: TextStyle(
                      color: ImagePickerPalette.text,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.d(
                      'De extensie blijft vast — het bestandsformaat verandert niet door de naam.',
                    ),
                    style: TextStyle(color: _muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          style: TextStyle(
                            color: ImagePickerPalette.text,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: ImagePickerPalette.bg,
                            errorText: errorText(),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: ImagePickerPalette.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: ImagePickerPalette.border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: AppTheme.blue500,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: canConfirm
                              ? (_) =>
                                    Navigator.pop(ctx, controller.text.trim())
                              : null,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          ext,
                          style: TextStyle(
                            color: ImagePickerPalette.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  style: TextButton.styleFrom(foregroundColor: _muted),
                  child: Text(l10n.t('cancel')),
                ),
                ElevatedButton.icon(
                  onPressed: canConfirm
                      ? () => Navigator.pop(ctx, controller.text.trim())
                      : null,
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(l10n.d('Hernoemen')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.blue500,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
