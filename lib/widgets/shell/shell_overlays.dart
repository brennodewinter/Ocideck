// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Visuele hint terwijl bestanden boven het venster zweven.
class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: AppTheme.navy.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.blue400, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.file_download_outlined,
                  size: 40,
                  color: AppTheme.accentFg,
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.d('Laat los om toe te voegen'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.d(
                    'Afbeeldingen → nieuwe slides · .md / .ocideck → openen',
                  ),
                  style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tab bar ───────────────────────────────────────────────────────────────────

class _ResizableDivider extends StatefulWidget {
  final ValueChanged<double> onDrag;

  const _ResizableDivider({required this.onDrag});

  @override
  State<_ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<_ResizableDivider> {
  static const double _keyboardStep = 24;

  bool _hovered = false;
  bool _dragging = false;
  bool _focused = false;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onDrag(-_keyboardStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onDrag(_keyboardStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = _hovered || _dragging || _focused;
    // Keyboard-operable (WCAG 2.1.1): the divider is focusable, arrow keys
    // move it, and focus is shown with the same highlight as hovering
    // (WCAG 2.4.7). Screen readers see it as an adjustable element.
    return Focus(
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Semantics(
        slider: true,
        label: l10n.d('Breedte van het slidepaneel'),
        hint: l10n.d('Pijltjestoetsen passen de breedte aan'),
        onIncrease: () => widget.onDrag(_keyboardStep),
        onDecrease: () => widget.onDrag(-_keyboardStep),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragEnd: (_) => setState(() => _dragging = false),
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            onHorizontalDragUpdate: (details) =>
                widget.onDrag(details.delta.dx),
            child: Tooltip(
              message: l10n.d(
                'Sleep om de slide-preview breder of smaller te maken',
              ),
              child: SizedBox(
                width: 9,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: active ? 3 : 1,
                    color: active
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
