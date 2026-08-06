// Part of the add_slide_dialog library — see add_slide_dialog.dart. Split out
// for the file-size ratchet: the category filter pill lives here so the main
// file stays under its ceiling, the same way the preview wireframes live in
// add_slide_dialog_painter.dart.
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
