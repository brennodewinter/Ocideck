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
            nativeId: d.nativeObject.address.toString(),
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

void moveToDisplay(DisplayInfo display) {
  if (!display.hasValidBounds) throw StateError('Invalid display bounds');
  try {
    final window = WindowManager.instance.getCurrent();
    if (window == null) throw StateError('Presenter window is not available');
    window.isFullScreen = false;
    window.bounds = Rect.fromLTWH(
      display.x,
      display.y,
      display.width,
      display.height,
    );
    window.isFullScreen = true;
  } catch (e) {
    logError('display_info_io.moveToDisplay: failed', e);
    rethrow;
  }
}
