import 'package:nativeapi/nativeapi.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../utils/log.dart';

class _DisplayMoveRequest {
  WindowController? controller;
  bool cancelled = false;
}

final _displayMoves = <_DisplayMoveRequest>{};

/// A native move is bound to its window and can be cancelled even while its
/// window definition is loading. No operation starts after that cancellation.
Future<void> movePresenterToDisplay({
  required String presenterDisplay,
  required String targetDisplay,
}) async {
  final request = _DisplayMoveRequest();
  _displayMoves.add(request);
  try {
    final controller = await WindowController.fromCurrentEngine();
    if (request.cancelled) throw StateError('Display move cancelled');
    request.controller = controller;
    await controller.moveToDisplay(
      presenterDisplay: presenterDisplay,
      targetDisplay: targetDisplay,
    );
    if (request.cancelled) throw StateError('Display move cancelled');
  } finally {
    _displayMoves.remove(request);
  }
}

Future<void> _cancelDisplayMoves() async {
  final pending = _displayMoves.toList();
  for (final request in pending) {
    request.cancelled = true;
  }
  await Future.wait(
    pending.map((request) async {
      final controller = request.controller;
      if (controller == null) return;
      try {
        await controller.cancelDisplayMove().timeout(
          const Duration(seconds: 2),
        );
      } catch (e) {
        logWarning(
          'setPresenterFullscreen: display move cancellation unavailable',
          e,
        );
      }
    }),
  );
}

/// Desktop: het native venster naar (uit) volledig scherm. Best-effort — een
/// fout mag het presenteren niet blokkeren.
Future<void> setPresenterFullscreen(bool fullscreen) async {
  if (!fullscreen && _displayMoves.isNotEmpty) await _cancelDisplayMoves();
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
