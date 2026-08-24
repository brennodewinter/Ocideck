import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ctrl-sneltoets die de fysieke lettertoets volgt.
///
/// macOS vertaalt Ctrl+H vóór Flutter naar de logische Backspace-toets. Een
/// gewone [SingleActivator] ziet daardoor geen H en laat de tekst verwijderen.
/// De fysieke toets blijft wel H; die is voor deze klassieke sneltoets de
/// betrouwbare identiteit.
class PhysicalControlActivator extends ShortcutActivator {
  const PhysicalControlActivator(this.key);

  final PhysicalKeyboardKey key;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    return event.physicalKey == key &&
        state.isControlPressed &&
        !state.isAltPressed &&
        !state.isMetaPressed &&
        !state.isShiftPressed;
  }

  @override
  String debugDescribeKeys() => 'Control + ${key.debugName ?? key.usbHidUsage}';

  @override
  bool operator ==(Object other) =>
      other is PhysicalControlActivator && other.key == key;

  @override
  int get hashCode => Object.hash(PhysicalControlActivator, key);
}
