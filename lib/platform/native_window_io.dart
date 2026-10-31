import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse, Size;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:nativeapi/nativeapi.dart';

import '../utils/log.dart';

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

/// De shell registreert hier dezelfde bewaking als op de willClose-hook.
/// macOS-afsluiten via Cmd+Q komt daar niet langs (#2678).
void Function()? _appExitHandler;

/// [quitApp] zet dit, zodat de terminate die het sluiten van het laatste
/// venster daarna nog eens vraagt wél doorgaat. De eerste vraag hebben we
/// geweigerd om de dialoog te kunnen tonen.
bool _platformExitAllowed = false;

/// Hoe vaak [quitApp] is aangeroepen. Een widgettest heeft geen native
/// venster; de teller bewijst dat de schone route de afsluiting bereikt.
@visibleForTesting
int debugQuitAppCalls = 0;

/// Slaat het native venster over. Zet een test dit, dan blijft de
/// FFI-binding van het venster buiten beeld.
@visibleForTesting
bool debugQuitAppSkipsNative = false;

/// Zet de afsluitvlag en de teller terug. Tests delen het proces.
@visibleForTesting
void debugResetAppExitForTest() {
  _platformExitAllowed = false;
  _appExitHandler = null;
  debugQuitAppCalls = 0;
  debugQuitAppSkipsNative = false;
}

/// Registreert wie een macOS-afsluitverzoek beantwoordt. `null` is de
/// toestemmingspoort: daar is niets opgeslagen en Cmd+Q mag direct weg
/// (#1207).
void setAppExitHandler(void Function()? handler) {
  _appExitHandler = handler;
}

/// Of de shell de afsluitvraag op zich heeft genomen.
bool get hasAppExitHandler => _appExitHandler != null;

/// Antwoord op `System.requestAppExit`.
///
/// Met een shell starten we de sluitbewaking en antwoorden we `cancel`:
/// de app blijft open tot de gebruiker kiest, en [quitApp] doet het echte
/// sluiten. Zonder shell, of nadat [quitApp] de vlag heeft gezet, is het
/// antwoord `exit`.
Future<AppExitResponse> respondToAppExitRequest() async {
  if (_platformExitAllowed || _appExitHandler == null) {
    return AppExitResponse.exit;
  }
  _appExitHandler!();
  return AppExitResponse.cancel;
}

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

/// Haalt het primaire venster naar voren. Een tweede Linux-start zonder
/// bestand heeft geen ander zichtbaar effect (#2679).
Future<void> focusPrimaryWindow() async {
  if (!Platform.isLinux) return;
  final window = WindowManager.instance.getCurrent();
  if (window == null) return;
  window.show();
  window.focus();
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
///
/// Vlak vóór het sluiten rondt [closeLog] het logbestand af en haalt de
/// sessiemarkering weg: dit ís de nette afsluiting (#2618).
Future<void> quitApp() async {
  // Eerst de vlag: het sluiten van het laatste venster vraagt macOS nog
  // een keer om terminate, en die tweede vraag mag niet opnieuw annuleren.
  _platformExitAllowed = true;
  debugQuitAppCalls++;
  if (debugQuitAppSkipsNative) {
    await closeLog();
    return;
  }
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
  final window = WindowManager.instance.getCurrent();
  if (window == null) return;
  await closeLog();
  WindowManager.instance.callOriginalClose(window.id);
}
