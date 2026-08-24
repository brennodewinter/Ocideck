import 'package:flutter/services.dart';

const kNativeShortcutChannel = MethodChannel('ocideck/shortcuts');

/// Ontvangt sneltoetsen die macOS moet onderscheppen vóór de tekstinvoer.
///
/// Ctrl+H wordt door AppKit anders als Backspace aan Flutter geleverd. De
/// native vensterlaag herkent de oorspronkelijke NSEvent en meldt hier alleen
/// de bedoelde opdracht.
class NativeShortcutChannel {
  NativeShortcutChannel(this.onFindReplace);

  final void Function() onFindReplace;

  void start() {
    kNativeShortcutChannel.setMethodCallHandler((call) async {
      if (call.method == 'findReplace') onFindReplace();
    });
  }

  void dispose() => kNativeShortcutChannel.setMethodCallHandler(null);
}
