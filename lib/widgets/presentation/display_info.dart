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

/// Index van het scherm dat [point] bevat, in de volgorde waarin het platform
/// zijn schermen opsomt — dezelfde volgorde die `coverScreen(presenterScreen:)`
/// native aanneemt. Null bij geen scherm, een null-punt, of een punt buiten alle
/// schermen (#1913).
int? screenIndexContaining(List<DisplayInfo> displays, Offset? point) {
  if (point == null) return null;
  for (var i = 0; i < displays.length; i++) {
    final d = displays[i];
    if (Rect.fromLTWH(d.x, d.y, d.width, d.height).contains(point)) {
      return i;
    }
  }
  return null;
}

/// Index van het scherm waarop het hoofdvenster (de presentator) staat, in de
/// volgorde waarin het platform zijn schermen opsomt — dezelfde volgorde die
/// `coverScreen(presenterScreen:)` native aanneemt. Null bij één scherm of als
/// de schermherkenning faalt (dan valt `coverScreen` terug op `external`) (#1913).
int? presenterScreenIndex() {
  final displays = getAllDisplays();
  if (displays.length < 2) return null;
  return screenIndexContaining(displays, getCurrentWindowCenter());
}

/// Verhuist het venster naar scherm [index] en zet het in volledig scherm.
/// No-op op web; best-effort op desktop.
void moveToDisplay(int index, List<DisplayInfo> displays) =>
    impl.moveToDisplay(index, displays);
