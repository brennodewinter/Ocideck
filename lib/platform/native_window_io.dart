import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:nativeapi/nativeapi.dart';

/// De kleinste maat waarop de shell nog werkt.
///
/// OciDeck's hoofdscherm is een drieluik — diastrook, editor, preview — en
/// daaronder vouwen die panelen over elkaar heen. Zonder deze ondergrens kan
/// een gebruiker het venster kleiner slepen dan de app aankan.
const Size minimumWindowSize = Size(1000, 650);

/// De callback die OciDeck registreert op de willClose-hook. Het native
/// venster roept deze synchroon aan vóór het sluiten — de shell start er een
/// async-bewaking in (dialogen, opslaan) en roept [quitApp] als alles veilig
/// is. Wil de shell het sluiten afbreken, dan doet ze niets.
typedef WillCloseCallback = void Function();

WillCloseCallback? _willCloseCallback;

Future<void> configureNativeWindow() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;

  final window = WindowManager.instance.getCurrent();
  if (window == null) return;
  window.minimumSize = minimumWindowSize;
  window.show();
  window.focus();

  // nativeapi gebruikt een willClose-hook i.p.v. window_manager's
  // setPreventClose: het native venster roept de hook synchroon aan vóór
  // het sluiten, en de shell beslist dan async of er niet-opgeslagen werk
  // is. Wil de shell sluiten, dan roept ze [quitApp]; wil ze afbreken,
  // dan doet ze niets en het venster blijft open.
  WindowManager.instance.setWillCloseHook((_) {
    _willCloseCallback?.call();
  });
}

/// Registreert de callback die bij het sluiten van het venster wordt
/// aangeroepen. De shell gebruikt dit om niet-opgeslagen werk te bewaken.
void setWillCloseCallback(WillCloseCallback callback) {
  _willCloseCallback = callback;
}

/// Sluit de app netjes af — de uitweg voor een gebruiker die niet verder wíl.
///
/// Nodig omdat de willClose-hook het sluiten onderschept en alleen de shell
/// (`AppShell._onWillClose`) dat sluiten weer afhandelt. Vóór de shell — bij
/// de toestemmingspoort — luistert er niemand naar de kruis-knop, dus dan zit
/// een gebruiker die niet akkoord gaat klem (#1207). Deze route omzeilt de
/// vensterbewaking: er is op de poort niets opgeslagen om te bewaken.
Future<void> quitApp() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
  final window = WindowManager.instance.getCurrent();
  if (window == null) return;
  WindowManager.instance.callOriginalClose(window.id);
}
