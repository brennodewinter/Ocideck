import 'dart:ui';

import 'display_info_data.dart';
export 'display_info_data.dart';
import 'display_info_io.dart'
    if (dart.library.js_interop) 'display_info_web.dart'
    as impl;

/// Geeft alle schermen terug, of een lege lijst op web / als het faalt.
List<DisplayInfo> getAllDisplays() => impl.getAllDisplays();

/// Geeft het centrum van het huidige venster terug, of null op web / als het faalt.
Offset? getCurrentWindowCenter() => impl.getCurrentWindowCenter();

/// Verhuist het venster naar scherm [index] en zet het in volledig scherm.
/// No-op op web; best-effort op desktop.
void moveToDisplay(int index, List<DisplayInfo> displays) =>
    impl.moveToDisplay(index, displays);
