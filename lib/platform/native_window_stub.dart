import 'dart:ui' show AppExitResponse, Size;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Op web is er geen minimum venstergrootte — het browservenster is wat het is.
const Size minimumWindowSize = Size(0, 0);

/// Op web is er geen willClose-hook — een browsertabblad sluiten werkt altijd.
void setWillCloseCallback(void Function() callback) {}

/// Hoe vaak [quitApp] is aangeroepen. Zelfde naad als de desktophelft, zodat
/// de voorwaardelijke export één API houdt.
@visibleForTesting
int debugQuitAppCalls = 0;

/// Op web is er geen native venster om over te slaan; de vlag bestaat zodat
/// de voorwaardelijke export dezelfde namen heeft.
@visibleForTesting
bool debugQuitAppSkipsNative = false;

/// Zet de teller terug. Tests delen het proces.
@visibleForTesting
void debugResetAppExitForTest() {
  debugQuitAppCalls = 0;
  debugQuitAppSkipsNative = false;
}

/// Op web bestaat de vensterval van [quitApp] niet: een browsertabblad sluiten
/// werkt altijd, en een pagina kan zichzelf niet betrouwbaar sluiten. Daarom
/// een no-op — de afsluitknop wordt op web ook niet getoond. De teller loopt
/// wél mee, anders ziet een test op deze helft een stille no-op.
Future<void> quitApp() async {
  debugQuitAppCalls++;
}

Future<void> configureNativeWindow() async {}

/// Op web is er geen native venster om naar voren te halen.
Future<void> focusPrimaryWindow() async {}

/// Op web is er geen `System.requestAppExit` vanuit een app-menu.
void setAppExitHandler(void Function()? handler) {}

/// Op web neemt de shell de afsluitvraag nooit over.
bool get hasAppExitHandler => false;

/// Op web komt dit verzoek niet voor; `exit` houdt de aanroep geldig.
Future<AppExitResponse> respondToAppExitRequest() async => AppExitResponse.exit;
