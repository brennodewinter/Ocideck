// The editor/preview workspace row plus the banners above it, split out of
// app_shell's _MainLayoutState (#2603): the narrow-width math lives beside
// the row it sizes, and the shell files stay under their size ceilings.
// The parent keeps the slide-rail width in its State so a rebuild can't
// silently reset a manual resize.

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_snackbar.dart';
import '../collab_verify_banner.dart';
import '../panels/call_panel.dart';
import '../panels/call_recording_controls.dart';
import '../panels/collab_chat_panel.dart';
import '../panels/editor_panel.dart';
import '../panels/recording_indicator.dart';
import '../panels/slide_list_panel.dart';

/// Standaardbreedte van de sliderail; de actuele waarde leeft in de
/// `_MainLayoutState`, zodat een handmatige resize een rebuild overleeft.
const double defaultSlideRailWidth = 320.0;

class WorkspaceBody extends ConsumerWidget {
  const WorkspaceBody({
    super.key,
    required this.slideRailWidth,
    required this.onSlideRailResize,
    required this.onPresentFromSlide,
    required this.onOpenOverview,
  });

  /// Huidige sliderailbreedte uit de shell-state; [onSlideRailResize]
  /// schrijft een nieuwe waarde terug — bij een drag én bij de clamp die
  /// een smaller venster afdwingt.
  final double slideRailWidth;
  final ValueChanged<double> onSlideRailResize;
  final ValueChanged<int> onPresentFromSlide;
  final VoidCallback onOpenOverview;

  static const _minSlideRailWidth = 210.0;
  static const _minEditorWidth = 420.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deckState = ref.watch(deckProvider);
    final deck = deckState.deck!;
    final l10n = context.l10n;

    if (deckState.error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showActionSnackBar(
          ScaffoldMessenger.of(context),
          deckState.error!,
          context.l10n.d('OK'),
          () => ref.read(deckProvider.notifier).clearError(),
          duration: const Duration(seconds: 10),
          backgroundColor: Colors.red[700],
          actionTextColor: Colors.white,
        );
        ref.read(deckProvider.notifier).clearError();
      });
    }

    // The available width comes from MediaQuery, NOT a LayoutBuilder: a
    // LayoutBuilder rebuilds this subtree during the layout phase, and
    // when the slide list's keyed ReorderableListView items get
    // reparented in that pass their overlay children are activated
    // outside an active layout — "A _RenderLayoutBuilder was mutated in
    // performLayout". The body row spans the window, so the window width
    // is equivalent.
    final bodyWidth = MediaQuery.sizeOf(context).width;
    // De rechterrails hebben een vaste breedte; zonder deze aftrek kreeg
    // de editor naast een actieve call of chatsessie minder dan zijn
    // minimum en liep de inhoud over (#2603).
    final sideWidth = collabChatRailWidth(ref) + callRailWidth(ref);
    final mainWidth = bodyWidth - sideWidth;
    // Op smal web kan het venster onder rail-plus-editor komen; de rail
    // valt dan weg (#1881) — anders gooit clamp ArgumentError.
    final showRail = mainWidth >= _minSlideRailWidth + _minEditorWidth;
    final maxRailWidth = showRail
        ? (mainWidth - _minEditorWidth)
              .clamp(_minSlideRailWidth, mainWidth)
              .toDouble()
        : 0.0;
    final railWidth = showRail
        ? slideRailWidth.clamp(_minSlideRailWidth, maxRailWidth).toDouble()
        : 0.0;
    if (railWidth != slideRailWidth) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onSlideRailResize(railWidth),
      );
    }

    // De editor duikt nooit onder zijn minimum: past de rij nergens meer,
    // scrollt hij horizontaal in plaats van dat de inhoud overlapt
    // (#2603). Alleen in die scrolltak krijgt hij een vaste breedte — een
    // Expanded mag niet in een horizontale scroll — anders vult hij
    // gewoon wat de rij overlaat.
    const dividerWidth = 9.0;
    final scrolls =
        sideWidth +
            (showRail ? railWidth + dividerWidth : 0) +
            _minEditorWidth >
        bodyWidth;
    // Chat stays beside the editor during Matrix (§6), so editing
    // continues; `collabChatRail` is empty otherwise.
    final workspace = Row(
      children: [
        if (showRail) ...[
          SizedBox(
            width: railWidth,
            child: SlideListPanel(
              railWidth: railWidth,
              onPresentFromHere: onPresentFromSlide,
              onOpenOverview: onOpenOverview,
            ),
          ),
          _ResizableDivider(
            onDrag: (delta) => onSlideRailResize(
              (slideRailWidth + delta)
                  .clamp(_minSlideRailWidth, maxRailWidth)
                  .toDouble(),
            ),
          ),
        ],
        scrolls
            ? const SizedBox(width: _minEditorWidth, child: EditorPanel())
            : const Expanded(child: EditorPanel()),
        ...collabChatRail(ref),
        ...callRail(ref),
      ],
    );
    // Banners stack above the workspace: de opname-indicator (alleen
    // zichtbaar tijdens een sessie, maar dan boven élke tab), de collab
    // verification prompt (self-hiding — see CollabVerifyBanner) en de
    // read-only finalized lock.
    return Column(
      children: [
        const CallRecordingBanner(),
        const RecordingIndicator(),
        const CollabVerifyBanner(),
        if (deck.finalized) _finalizedBanner(context, l10n),
        Expanded(
          child: scrolls
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: workspace,
                )
              : workspace,
        ),
      ],
    );
  }

  /// Read-only-banner voor een afgerond & verzegeld deck (§8 A1). Slank,
  /// boven de werkruimte; bekijken/exporteren blijft mogelijk, bewerken
  /// niet.
  Widget _finalizedBanner(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Material(
      color: AppTheme.amber600.withValues(alpha: 0.14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 16, color: AppTheme.amber600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.d(
                  'Deze presentatie is afgerond en verzegeld en kan niet worden bewerkt.',
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
