import 'dart:ui' show AppExitResponse, Size;

/// Op web is er geen minimum venstergrootte — het browservenster is wat het is.
const Size minimumWindowSize = Size(0, 0);

/// Op web is er geen willClose-hook — een browsertabblad sluiten werkt altijd.
void setWillCloseCallback(void Function() callback) {}

/// Op web bestaat de vensterval van [quitApp] niet: een browsertabblad sluiten
/// werkt altijd, en een pagina kan zichzelf niet betrouwbaar sluiten. Daarom
/// een no-op — de afsluitknop wordt op web ook niet getoond.
Future<void> quitApp() async {}

Future<void> configureNativeWindow() async {}

/// Op web is er geen `System.requestAppExit` vanuit een app-menu.
void setAppExitHandler(void Function()? handler) {}

/// Op web neemt de shell de afsluitvraag nooit over.
bool get hasAppExitHandler => false;

/// Op web komt dit verzoek niet voor; `exit` houdt de aanroep geldig.
Future<AppExitResponse> respondToAppExitRequest() async => AppExitResponse.exit;
