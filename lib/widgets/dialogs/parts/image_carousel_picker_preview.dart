// Part of the image_carousel_picker library — see ../image_carousel_picker.dart.
// Split out for navigability (preview pane & footer); all imports live in the main library
// file. Instance methods relocate verbatim into an extension on
// _ImageCarouselPickerState — same library, same members, no behaviour change.
part of '../image_carousel_picker.dart';

extension _CarouselPreview on _ImageCarouselPickerState {
  Widget _buildPreview() {
    final l10n = context.l10n;
    return SizedBox(
      width: 300,
      child: Container(
        color: ImagePickerPalette.bgDeepest,
        child: _selected == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.touch_app_outlined,
                      size: 40,
                      color: ImagePickerPalette.border,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.d('Selecteer een\nafbeelding'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ImagePickerPalette.textMuted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // Grote preview
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image(
                          image: boundedFileImage(File(_selected!), 720),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: ImagePickerPalette.border,
                                  size: 48,
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                  // Bestandsinfo
                  _fileInfoPanel(l10n),
                ],
              ),
      ),
    );
  }

  Widget _fileInfoPanel(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ImagePickerPalette.surface1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ImagePickerPalette.surface2, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.basename(_selected!),
              style: const TextStyle(
                color: ImagePickerPalette.text,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              _formatPath(_selected!),
              style: const TextStyle(
                color: ImagePickerPalette.textMuted,
                fontSize: 10.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            _FileSize(path: _selected!),
            const SizedBox(height: 12),
            _metaField(
              controller: _captionController,
              hint: l10n.d('Caption / bronvermelding'),
              icon: Icons.copyright_outlined,
              onChanged: (value) => _caption = value,
            ),
            const SizedBox(height: 8),
            _metaField(
              controller: _descriptionController,
              hint: l10n.d('Beschrijving (doorzoekbaar)'),
              icon: Icons.sell_outlined,
              onChanged: (value) => _descriptions[_selected!] = value.trim(),
            ),
            const SizedBox(height: 10),
            // Wrap i.p.v. Row: op de smalle previewkolom stapelen de knoppen
            // netjes onder elkaar in plaats van de Row te laten overlopen.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _justCopied ? null : _copySelectedToClipboard,
                  icon: Icon(
                    _justCopied ? Icons.check : Icons.content_copy_outlined,
                    size: 16,
                  ),
                  label: Text(
                    _justCopied ? l10n.d('Gekopieerd') : l10n.d('Kopiëren'),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _justCopied
                        ? ImagePickerPalette.success
                        : ImagePickerPalette.textMuted,
                    disabledForegroundColor: ImagePickerPalette.success,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(l10n.d('Verwijderen')),
                  style: TextButton.styleFrom(
                    foregroundColor: ImagePickerPalette.dangerSoft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Een metadata-tekstveld (caption/beschrijving) in de donkere previewstijl.
  /// De twee velden verschilden alleen in controller, hint, icoon en handler.
  Widget _metaField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: 3,
      onChanged: onChanged,
      style: const TextStyle(color: ImagePickerPalette.text, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: ImagePickerPalette.textMuted,
          fontSize: 12,
        ),
        prefixIcon: Icon(icon, color: ImagePickerPalette.iconDim, size: 16),
        isDense: true,
        filled: true,
        fillColor: ImagePickerPalette.bg,
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
    );
  }

  Widget _buildFooter() {
    final l10n = context.l10n;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ImagePickerPalette.surface2)),
      ),
      child: Row(
        children: [
          // Bladeren knop
          OutlinedButton.icon(
            onPressed: _browse,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(l10n.d('Bladeren…')),
            style: OutlinedButton.styleFrom(
              foregroundColor: ImagePickerPalette.textMuted,
              side: const BorderSide(color: ImagePickerPalette.border),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          // Duplicaten opruimen (md5)
          Tooltip(
            message: l10n.d(
              'Zoek byte-identieke afbeeldingen (md5), voeg tags en opmerkingen samen en verwijder de kopieën',
            ),
            child: OutlinedButton.icon(
              onPressed: _deduping || _images.length < 2 ? null : _dedupe,
              icon: _deduping
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ImagePickerPalette.textMuted,
                      ),
                    )
                  : const Icon(Icons.layers_clear_outlined, size: 16),
              label: Text(
                _deduping && _dedupePhase != null
                    ? _dedupePhase!
                    : l10n.d('Duplicaten opruimen'),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ImagePickerPalette.textMuted,
                side: const BorderSide(color: ImagePickerPalette.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Hint — mag inkorten op smalle vensters zodat de Row niet overloopt.
          Flexible(
            child: Text(
              l10n.d(
                '↑↓←→ navigeren  ·  Enter kiezen  ·  Dubbelklik selecteert',
              ),
              style: const TextStyle(
                color: ImagePickerPalette.borderStrong,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          // Annuleren
          TextButton(
            onPressed: () => _close(),
            style: TextButton.styleFrom(
              foregroundColor: ImagePickerPalette.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(l10n.t('cancel')),
          ),
          const SizedBox(width: 10),
          // Kiezen
          ElevatedButton.icon(
            onPressed: _selected != null ? () => _confirm() : null,
            icon: const Icon(Icons.check_circle_outline, size: 17),
            label: Text(l10n.d('Kiezen')),
            style: ElevatedButton.styleFrom(
              backgroundColor: ImagePickerPalette.successStrong,
              foregroundColor: Colors.white,
              disabledBackgroundColor: ImagePickerPalette.surface2,
              disabledForegroundColor: ImagePickerPalette.borderStrong,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPath(String path) {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }
}
