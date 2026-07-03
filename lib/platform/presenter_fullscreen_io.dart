import 'package:window_manager/window_manager.dart';

import '../utils/log.dart';

/// Desktop: het native venster naar (uit) volledig scherm. Best-effort — een
/// fout mag het presenteren niet blokkeren.
Future<void> setPresenterFullscreen(bool fullscreen) async {
  try {
    await windowManager.setFullScreen(fullscreen);
  } catch (e) {
    logWarning('setPresenterFullscreen: window_manager niet beschikbaar', e);
  }
}
