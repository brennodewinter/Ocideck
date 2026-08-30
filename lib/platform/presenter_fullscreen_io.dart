import 'package:nativeapi/nativeapi.dart';

import '../utils/log.dart';

/// Desktop: het native venster naar (uit) volledig scherm. Best-effort — een
/// fout mag het presenteren niet blokkeren.
Future<void> setPresenterFullscreen(bool fullscreen) async {
  try {
    final window = WindowManager.instance.getCurrent();
    if (window == null) return;
    window.isFullScreen = fullscreen;
  } catch (e) {
    logWarning('setPresenterFullscreen: nativeapi niet beschikbaar', e);
  }
}

bool isPresenterFullscreen() {
  try {
    final window = WindowManager.instance.getCurrent();
    return window?.isFullScreen ?? false;
  } catch (e) {
    logWarning('isPresenterFullscreen: nativeapi niet beschikbaar', e);
    return false;
  }
}
