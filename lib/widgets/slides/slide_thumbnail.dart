import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/markdown_validation.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../state/deck_quality_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/slide_clipboard_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'slide_preview.dart';

class SlideThumbnail extends ConsumerWidget {
  final Slide slide;
  final int index;
  final bool isSelected;

  /// De actieve slide binnen een meervoudige selectie (de slide die in de
  /// editor wordt getoond). Krijgt een iets sterkere markering.
  final bool isPrimary;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final int slideCount;
  final TlpLevel tlp;
  final String organization;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onToggleSkip;
  final VoidCallback onCopyImage;
  final VoidCallback onSplit;

  /// Persoonlijke gebruikersnotities (sidecar), los van sprekersnotities.
  final bool hasUserNotes;

  /// Shared font scale when this slide is one page of a split run, so the rail
  /// matches the main preview (see [SlidePreviewWidget.fitScaleOverride]).
  final double? fitScaleOverride;

  const SlideThumbnail({
    super.key,
    required this.slide,
    required this.index,
    required this.isSelected,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleSkip,
    required this.onCopyImage,
    required this.onSplit,
    this.hasUserNotes = false,
    this.isPrimary = true,
    this.projectPath,
    this.themeProfile = const ThemeProfile(),
    this.slideCount = 1,
    this.tlp = TlpLevel.none,
    this.organization = '',
    this.fitScaleOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final skipped = slide.skipped;
    final slideIssues = ref.watch(deckQualityProvider).forSlide(index);
    final showWatermark = ref
        .watch(settingsProvider)
        .classificationWatermarkEnabled;
    final hasQualityErrors = slideIssues.any(
      (i) => i.severity == MarkdownValidationSeverity.error,
    );
    // "In tweeën splitsen" is beschikbaar op elke bulletslide met genoeg bullets
    // om te verdelen — óók bullets-met-afbeelding, waar het tekstvlak maar de
    // halve breedte heeft en een slide dus eerder vol oogt dan de algemene
    // bullettelling-drempel suggereert. De daadwerkelijke knip (op het optimum
    // dat past) gebeurt in DeckNotifier.splitSlide.
    final canSplit = switch (slide.type) {
      SlideType.bullets || SlideType.bulletsImage => slide.bullets.length >= 2,
      SlideType.twoBullets =>
        slide.bullets.length >= 2 || slide.bullets2.length >= 2,
      _ => false,
    };
    final hasQualityWarnings = slideIssues.any(
      (i) => i.severity == MarkdownValidationSeverity.warning,
    );
    final hasActionableQualityIssues = hasQualityErrors || hasQualityWarnings;
    final borderColor = isSelected
        ? AppTheme.accent
        : skipped
        ? const Color(0xFF8A6D3B)
        : const Color(0xFF3A3F4B);
    // Actieve slide krijgt een dikkere rand dan de overige geselecteerde.
    final borderWidth = isSelected ? (isPrimary ? 2.5 : 1.6) : 1.0;

    // Eén beknopt label per kaart voor schermlezers: nummer, titel (of type)
    // en status. De mini-preview eronder is puur visueel en zou anders de
    // volledige slide-inhoud per thumbnail laten voorlezen.
    final title = slide.title.trim();
    final semanticLabel =
        '${l10n.d('Slide')} ${index + 1}/$slideCount: '
        '${title.isNotEmpty ? title : l10n.d(slide.type.label)}'
        '${skipped ? ' (${l10n.d('Overgeslagen')})' : ''}'
        '${hasUserNotes ? ' (${l10n.d('Gebruikersnotities')})' : ''}'
        '${hasActionableQualityIssues ? ' (${l10n.d('Kwaliteitsprobleem')})' : ''}';

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: borderWidth),
            color: isSelected
                ? const Color(0xFF2A2F3B)
                : const Color(0xFF252830),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mini slide preview
              _miniPreview(
                ref,
                l10n,
                skipped: skipped,
                showWatermark: showWatermark,
                hasQualityWarnings: hasQualityWarnings,
                hasQualityErrors: hasQualityErrors,
              ),
              // Footer: slide number, type label, action buttons
              _footer(ref, l10n, skipped: skipped, canSplit: canSplit),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniPreview(
    WidgetRef ref,
    AppLocalizations l10n, {
    required bool skipped,
    required bool showWatermark,
    required bool hasQualityWarnings,
    required bool hasQualityErrors,
  }) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Overgeslagen slides worden gedimd weergegeven.
              Opacity(
                opacity: skipped ? 0.32 : 1,
                child: SlidePreviewWidget(
                  slide: slide,
                  projectPath: projectPath,
                  themeProfile: themeProfile,
                  cockpitColorScheme: ref
                      .watch(settingsProvider)
                      .cockpitColorScheme,
                  slideNumber: index + 1,
                  slideCount: slideCount,
                  fitScaleOverride: fitScaleOverride,
                  tlp: tlp,
                  organization: organization,
                  showClassificationWatermark: showWatermark,
                ),
              ),
              if (skipped)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC8A6D3B),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.visibility_off_outlined,
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          l10n.d('Overgeslagen'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (hasUserNotes)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Tooltip(
                    message: l10n.d('Gebruikersnotities'),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xCC2563EB),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.edit_note_outlined,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (hasQualityWarnings)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Tooltip(
                    message: hasQualityErrors
                        ? l10n.d('Kwaliteitsproblemen (inclusief ernstige)')
                        : l10n.d('Kwaliteitsproblemen'),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Color(
                          hasQualityErrors ? 0xCCD32F2F : 0xCCB45309,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.accessibility_new_outlined,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(
    WidgetRef ref,
    AppLocalizations l10n, {
    required bool skipped,
    required bool canSplit,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.accent : const Color(0xFF4A4F5B),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              l10n.d(slide.type.label),
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Drag handle
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.drag_handle,
                size: 14,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          // Snelle overslaan-toggle
          SizedBox(
            width: 20,
            height: 20,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 14,
              splashRadius: 12,
              tooltip: skipped
                  ? l10n.d('Weer tonen bij presenteren/exporteren')
                  : l10n.d('Overslaan bij presenteren/exporteren'),
              icon: Icon(
                skipped ? Icons.visibility_off : Icons.visibility_outlined,
                color: skipped
                    ? const Color(0xFFD4A24E)
                    : const Color(0xFF64748B),
              ),
              onPressed: onToggleSkip,
            ),
          ),
          // Context menu
          SizedBox(
            width: 20,
            height: 20,
            child: PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
                color: Color(0xFF64748B),
                size: 14,
              ),
              padding: EdgeInsets.zero,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'copy', child: Text(l10n.d('Kopiëren'))),
                PopupMenuItem(
                  value: 'copy_image',
                  child: Text(l10n.d('Kopieer als afbeelding')),
                ),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text(l10n.d('Dupliceren')),
                ),
                if (canSplit)
                  PopupMenuItem(
                    value: 'split',
                    child: Text(l10n.d('In tweeën splitsen')),
                  ),
                PopupMenuItem(
                  value: 'skip',
                  child: Text(
                    skipped
                        ? l10n.d('Niet meer overslaan')
                        : l10n.d('Overslaan'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l10n.d('Verwijderen'),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
              onSelected: (v) {
                if (v == 'copy') {
                  ref.read(slideClipboardProvider.notifier).state = slide;
                }
                if (v == 'copy_image') onCopyImage();
                if (v == 'duplicate') onDuplicate();
                if (v == 'split') onSplit();
                if (v == 'skip') onToggleSkip();
                if (v == 'delete') onDelete();
              },
            ),
          ),
        ],
      ),
    );
  }
}
