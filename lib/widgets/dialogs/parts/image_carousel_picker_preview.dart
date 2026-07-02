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
        color: const Color(0xFF080D14),
        child: _selected == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.touch_app_outlined,
                      size: 40,
                      color: Color(0xFF30363D),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.d('Selecteer een\nafbeelding'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6E7681),
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
                        child: Image.file(
                          File(_selected!),
                          fit: BoxFit.contain,
                          // Cap decode resolution: the preview pane is narrow,
                          // so full-resolution decodes would waste memory.
                          cacheWidth: 720,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Color(0xFF30363D),
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
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF21262D), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.basename(_selected!),
              style: const TextStyle(
                color: Color(0xFFCDD9E5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              _formatPath(_selected!),
              style: const TextStyle(color: Color(0xFF6E7681), fontSize: 10.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            _FileSize(path: _selected!),
            const SizedBox(height: 12),
            TextField(
              controller: _captionController,
              minLines: 1,
              maxLines: 3,
              onChanged: (value) => _caption = value,
              style: const TextStyle(color: Color(0xFFCDD9E5), fontSize: 12),
              decoration: InputDecoration(
                hintText: l10n.d('Caption / bronvermelding'),
                hintStyle: const TextStyle(
                  color: Color(0xFF6E7681),
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.copyright_outlined,
                  color: Color(0xFF6E7681),
                  size: 16,
                ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.blue500),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              minLines: 1,
              maxLines: 3,
              onChanged: (value) => _descriptions[_selected!] = value.trim(),
              style: const TextStyle(color: Color(0xFFCDD9E5), fontSize: 12),
              decoration: InputDecoration(
                hintText: l10n.d('Beschrijving (doorzoekbaar)'),
                hintStyle: const TextStyle(
                  color: Color(0xFF6E7681),
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.sell_outlined,
                  color: Color(0xFF6E7681),
                  size: 16,
                ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.blue500),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
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
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF8B949E),
                    disabledForegroundColor: const Color(0xFF22C55E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(l10n.d('Verwijderen')),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE5746E),
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

  Widget _buildFooter() {
    final l10n = context.l10n;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF21262D))),
      ),
      child: Row(
        children: [
          // Bladeren knop
          OutlinedButton.icon(
            onPressed: _browse,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(l10n.d('Bladeren…')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B949E),
              side: const BorderSide(color: Color(0xFF30363D)),
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
                        color: Color(0xFF8B949E),
                      ),
                    )
                  : const Icon(Icons.layers_clear_outlined, size: 16),
              label: Text(l10n.d('Duplicaten opruimen')),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8B949E),
                side: const BorderSide(color: Color(0xFF30363D)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Hint
          Text(
            l10n.d('↑↓←→ navigeren  ·  Enter kiezen  ·  Dubbelklik selecteert'),
            style: const TextStyle(color: Color(0xFF484F58), fontSize: 11),
          ),
          const Spacer(),
          // Annuleren
          TextButton(
            onPressed: () => _close(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B949E),
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
              backgroundColor: const Color(0xFF238636),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF21262D),
              disabledForegroundColor: const Color(0xFF484F58),
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
