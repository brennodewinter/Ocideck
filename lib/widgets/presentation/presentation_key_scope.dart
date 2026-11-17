import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef PresentationKeyHandler =
    KeyEventResult Function(
      LogicalKeyboardKey key, {
      bool meta,
      bool control,
      bool shift,
    });

/// The current slide may forward native child-window keys through the same
/// logical route as Flutter keys. Deliberately absent around editor/next views.
class PresentationKeyScope extends InheritedWidget {
  const PresentationKeyScope({
    super.key,
    required this.onKey,
    required super.child,
  });
  factory PresentationKeyScope.layout({
    Key? key,
    required PresentationKeyHandler onKey,
    required LayoutWidgetBuilder builder,
  }) => PresentationKeyScope(
    key: key,
    onKey: onKey,
    child: LayoutBuilder(builder: builder),
  );

  final PresentationKeyHandler onKey;

  static PresentationKeyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PresentationKeyScope>();

  void dispatchWindowsKey(
    int virtualKey, {
    bool meta = false,
    bool control = false,
    bool shift = false,
  }) {
    final key = switch (virtualKey) {
      0x25 => LogicalKeyboardKey.arrowLeft,
      0x27 => LogicalKeyboardKey.arrowRight,
      0x21 => LogicalKeyboardKey.pageUp,
      0x22 => LogicalKeyboardKey.pageDown,
      0x1b => LogicalKeyboardKey.escape,
      0x24 => LogicalKeyboardKey.home,
      0x23 => LogicalKeyboardKey.end,
      _ => null,
    };
    if (key != null) onKey(key, meta: meta, control: control, shift: shift);
  }

  @override
  bool updateShouldNotify(PresentationKeyScope oldWidget) =>
      oldWidget.onKey != onKey;
}
