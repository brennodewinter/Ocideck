import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../../platform/native_window.dart';

/// Cmd+Q, Dock-Stop en uitloggen vragen het framework, niet het venster.
///
/// Die route slaat de willClose-hook over. Dezelfde bewaking als de rode
/// knop: annuleren houdt de app open, doorgaan eindigt in [quitApp].
/// Buiten macOS is er niets te registreren — daar mag deze vraag niet vóór
/// de sluitbewaking komen (#2678).
AppLifecycleListener? installMacosExitGuard(void Function() onWillClose) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return null;
  setAppExitHandler(onWillClose);
  return AppLifecycleListener(onExitRequested: respondToAppExitRequest);
}
