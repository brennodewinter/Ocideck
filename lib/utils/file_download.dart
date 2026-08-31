/// Download-als-bestand voor de webversie: biedt [downloadBytesToBrowser] aan
/// dat in de browser een download start (Blob + tijdelijk anchor). Op niet-web
/// is het een stub die `false` teruggeeft — daar schrijft de app gewoon naar
/// disk.
///
/// Dit is het rauwe primitief. Exportpaden gebruiken het niet rechtstreeks maar
/// via `services/download_delivery.dart`, dat één export ook echt als één
/// download aflevert.
library;

export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';
