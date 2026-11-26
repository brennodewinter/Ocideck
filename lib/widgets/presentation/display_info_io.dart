import 'dart:ui';

import 'package:nativeapi/nativeapi.dart';
import '../../platform/presenter_fullscreen_io.dart' as presenter;

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

Future<void> moveToDisplay(
  DisplayInfo display, {
  required DisplayInfo previous,
}) async {
  await presenter.movePresenterToDisplay(
    presenterDisplay: previous.nativeId!,
    targetDisplay: display.nativeId!,
  );
}
