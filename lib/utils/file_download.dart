/// Download-als-bestand voor de webversie: biedt [downloadTextFile] aan dat in
/// de browser een download start (Blob + tijdelijk anchor). Op niet-web is het
/// een stub die `false` teruggeeft — daar schrijft de app gewoon naar disk.
library;

export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';
