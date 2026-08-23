import 'dart:ui';

import 'package:nativeapi/nativeapi.dart';

import '../../utils/log.dart';
import 'display_info_data.dart';

List<DisplayInfo> getAllDisplays() {
  try {
    return DisplayManager.instance
        .getAll()
        .map(
          (d) => DisplayInfo(
            x: d.position.dx,
            y: d.position.dy,
            width: d.size.width,
            height: d.size.height,
          ),
        )
        .toList();
  } catch (e) {
    logWarning('display_info_io.getAllDisplays: failed', e);
    return [];
  }
}

Offset? getCurrentWindowCenter() {
  try {
    final window = WindowManager.instance.getCurrent();
    if (window == null) return null;
    return window.bounds.center;
  } catch (e) {
    logWarning('display_info_io.getCurrentWindowCenter: failed', e);
    return null;
  }
}

void moveToDisplay(int index, List<DisplayInfo> displays) {
  if (displays.length < 2) return;
  final d = displays[index.clamp(0, displays.length - 1)];
  try {
    final window = WindowManager.instance.getCurrent();
    if (window == null) return;
    window.isFullScreen = false;
    window.bounds = Rect.fromLTWH(d.x, d.y, d.width, d.height);
    window.isFullScreen = true;
  } catch (e) {
    logError('display_info_io.moveToDisplay: failed', e);
    rethrow;
  }
}
