import 'dart:io';

import '../../utils/log.dart';

/// Wát er misging toen een netwerkaanroep afbrak, los van welke opslag hem deed.
///
/// De drie opslagbackends (WebDAV, S3, git) stelden allemaal dezelfde vraag aan
/// een gevangen `dart:io`-uitzondering, en gaven allemaal hetzelfde antwoord —
/// in drie kopieën. De vertaling naar een eigen uitzonderingstype is per
/// backend anders en blijft daar; het uit elkaar houden van de soorten is dat
/// niet en staat hier.
///
/// Het onderscheid is niet cosmetisch. Ervoor eindigde elke fout als
/// "verbinding mislukt", en of het nu een afgewezen certificaat, een dichte
/// poort of een weggevallen verbinding was, stond alleen nog in het logboek —
/// waar de gebruiker niet kijkt. Bovendien hangt aan de soort of het zin heeft
/// het nog eens te proberen.
enum TransportFailure {
  /// Het certificaat werd niet vertrouwd, of de TLS-handdruk mislukte.
  ///
  /// Niet tijdelijk: een afgewezen certificaat wordt niet vertrouwd door het
  /// nog eens te proberen.
  tls,

  /// De tegenpartij was niet te bereiken — DNS, een dichte poort, geen route.
  unreachable,

  /// De verbinding viel halverwege weg. Juist hiervoor bestaat een tweede
  /// poging.
  interrupted,

  /// Iets anders. De aanroeper heeft hier geen betere zin over te melden dan
  /// zijn eigen terugvalboodschap.
  unknown,
}

/// Deel een gevangen laag-niveau uitzondering in bij een [TransportFailure].
///
/// Alleen de indeling — het loggen en het gooien van een backend-eigen
/// uitzondering blijft bij de aanroeper, want dat is precies het stuk dat per
/// backend echt verschilt.
TransportFailure classifyTransportFailure(Object e) {
  // TlsException dekt zowel HandshakeException als CertificateException.
  if (e is TlsException) return TransportFailure.tls;
  if (e is SocketException) return TransportFailure.unreachable;
  // Een verbinding die halverwege wegviel meldt Dart als HttpException
  // ("Connection closed before full header was received"), niet als
  // SocketException.
  if (e is HttpException) return TransportFailure.interrupted;
  return TransportFailure.unknown;
}

/// Schrijf de fout naar het logboek op het niveau dat bij [kind] hoort.
///
/// [where] is de aanroeper in de vorm `Service.methode`, zodat een logregel
/// zonder stacktrace nog steeds aanwijst waar hij vandaan komt. Een herkende
/// soort is een waarschuwing (we weten wat er aan de hand is en vertellen het
/// de gebruiker); [TransportFailure.unknown] is een fout, want daar hebben we
/// geen verklaring voor.
void logTransportFailure(String where, TransportFailure kind, Object e) {
  switch (kind) {
    case TransportFailure.tls:
      logWarning('$where: TLS geweigerd', e);
    case TransportFailure.unreachable:
      logWarning('$where: niet bereikbaar', e);
    case TransportFailure.interrupted:
      logWarning('$where: verbinding afgebroken', e);
    case TransportFailure.unknown:
      logError('$where: mislukt', e);
  }
}
