part of 'add_slide_dialog.dart';

/// A picker tab: one [SlideCategory] to filter by, or `null` for "all types".
class _PickerTab {
  final SlideCategory? category;
  final String label;
  const _PickerTab(this.category, this.label);
}

/// A category filter as a soft pill: transparent with a hairline border when
/// not chosen, a light accent tint when chosen.
///
/// The default `ChoiceChip` read as a flat grey button and fell outside the
/// tone of the rest of the surface. This shares the accent tints the app
/// already uses for hover and selection (see the template picker in
/// `NewDeckDialog`), so the filters feel like the same surface rather than
/// imported Material chrome.
class _CategoryPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accent;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        hoverColor: accent.withValues(alpha: 0.06),
        focusColor: accent.withValues(alpha: 0.14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : null,
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.45)
                  : AppTheme.slate300,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppTheme.accentFg : AppTheme.slate700,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final SlideType type;
  final String label;

  /// De uitleg bij dit type. Gaat als schermlezer-hint mee op het kaartje zelf,
  /// zodat wie niet kijkt hem hoort op het moment van kiezen — niet pas in het
  /// vak eronder, dat een schermlezer nooit passeert.
  final String help;

  final VoidCallback onTap;
  final bool autofocus;
  final bool selected;

  /// Aangewezen door muis of toetsenbordfocus: het vak onder het rooster toont
  /// dan de uitleg van dit type.
  final VoidCallback onHighlight;

  const _TypeCard({
    super.key,
    required this.type,
    required this.label,
    required this.help,
    required this.onTap,
    required this.onHighlight,
    required this.selected,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      hint: help,
      child: InkWell(
        onTap: onTap,
        autofocus: autofocus,
        onHover: (hovering) {
          if (hovering) onHighlight();
        },
        onFocusChange: (focused) {
          if (!focused) return;
          onHighlight();
          if (selected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Scrollable.ensureVisible(
                context,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              );
            });
          }
        },
        borderRadius: BorderRadius.circular(8),
        focusColor: AppTheme.accent.withValues(alpha: 0.14),
        hoverColor: AppTheme.accent.withValues(alpha: 0.06),
        child: Ink(
          width: 100,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.warningBg : null,
            border: Border.all(
              color: selected ? AppTheme.amber600 : AppTheme.slate300,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A stylised wireframe of the layout, so the card shows what
              // the slide will look like instead of an abstract icon.
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CustomPaint(
                      painter: SlideTypePreviewPainter(type: type),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FittedTypeLabel(label: label),
            ],
          ),
        ),
      ),
    );
  }
}
