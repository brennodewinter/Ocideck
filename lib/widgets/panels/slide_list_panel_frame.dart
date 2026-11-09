// Part of the slide_list_panel library — see slide_list_panel.dart.
// Split out for navigability (the focus/engagement frame around the rail);
// all imports live in the main library file.
part of 'slide_list_panel.dart';

/// Het kader om de sliderail: de [Focus] die pijltjes en Delete afhandelt,
/// de [Listener] die echte aanraking registreert, en de accentrand die de
/// toetsenbordfocus toont (#2730, #2839).
///
/// Alleen het omhulsel woont hier; welke toets wat doet en wanneer de rail
/// als "aangeraakt" geldt, blijft in [_SlideListPanelState].
class _SlideRailFrame extends StatelessWidget {
  final FocusNode focusNode;
  final bool focused;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final ValueChanged<bool> onFocusChange;
  final PointerDownEventListener onPointerDown;
  final VoidCallback onTap;
  final Widget header;
  final Widget slideList;
  final Widget footer;

  const _SlideRailFrame({
    required this.focusNode,
    required this.focused,
    required this.onKeyEvent,
    required this.onFocusChange,
    required this.onPointerDown,
    required this.onTap,
    required this.header,
    required this.slideList,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: onKeyEvent,
      onFocusChange: onFocusChange,
      // Pointer-down in plaats van onTap: álles in de rail (miniatuur, knop,
      // zoekveld, lege ruimte) telt als echte aanraking, ook als een
      // binnenliggende gesture de tap wint.
      child: Listener(
        onPointerDown: onPointerDown,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).extension<AppPalette>()!.panel,
              border: Border.all(
                color: focused
                    ? Theme.of(context).colorScheme.secondary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(child: slideList),
                footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
