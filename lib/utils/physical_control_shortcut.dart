import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ctrl+H-sneltoets die de macOS-Backspacevertaling opvangt.
///
/// macOS vertaalt Ctrl+H vóór Flutter naar de logische Backspace-toets. Een
/// gewone [SingleActivator] ziet daardoor geen H en laat de tekst verwijderen.
/// Meestal blijft de fysieke toets H; sommige invoerroutes leveren echter ook
/// fysiek Backspace. Beide vormen horen bij dezelfde klassieke sneltoets.
class ControlHActivator extends ShortcutActivator {
  const ControlHActivator();

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!state.isControlPressed ||
        state.isAltPressed ||
        state.isMetaPressed ||
        state.isShiftPressed) {
      return false;
    }
    if (event.physicalKey == PhysicalKeyboardKey.keyH) return true;
    // Afhankelijk van de macOS-invoerroute gaat niet alleen de logische H,
    // maar ook de fysieke identiteit verloren en ontvangt Flutter Backspace.
    // Met ingehouden Ctrl is dit dezelfde gedocumenteerde Ctrl+H-sneltoets.
    return defaultTargetPlatform == TargetPlatform.macOS &&
        event.logicalKey == LogicalKeyboardKey.backspace;
  }

  @override
  String debugDescribeKeys() => 'Control + H';

  @override
  bool operator ==(Object other) => other is ControlHActivator;

  @override
  int get hashCode => 0x4354524c48;
}
