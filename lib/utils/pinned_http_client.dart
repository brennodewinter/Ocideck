import 'dart:io';

import 'net_guard.dart';

/// Bouwt een [HttpClient] die de socket pint op [pinnedAddress] (SSRF-pinning:
/// een DNS-rebind kan zo niet naar een intern adres doorverwijzen) en het
/// certificaat toetst tegen [pinnedCertSha256] wanneer die is meegegeven.
///
/// Eén plek voor het recept dat voorheen in vijf transports gekopieerd stond
/// (cve, git, matrix, webdav, s3). De aanroeper houdt de scheme-check, de
/// resolve, de body-cap en de error-types — die verschillen per transport. Een
/// wijziging aan het pinning-recept is hier één diff in plaats van vijf, wat
/// precies de fout is die duplicaat van beveiligingscode maakt: één kopie die
/// niet meekomt bij een fix.
///
/// De aanroeper zet per request `followRedirects = false` — een 3xx mag niet
/// om de hostcontrole heen lopen (zie network_sink_guard_test). Een semgrep-regel
/// (`ocideck-follow-redirects-op-gepinde-client`) vlagt een `openUrl`-aanroep
/// zonder `followRedirects = false` in dezelfde functie, zodat een nieuwe
/// aanroeper die de conventie mist niet onopgemerkt blijft.
HttpClient buildPinnedClient(
  InternetAddress pinnedAddress, {
  Duration connectionTimeout = const Duration(seconds: 15),
  String? pinnedCertSha256,
}) => HttpClient()
  ..connectionTimeout = connectionTimeout
  ..connectionFactory = (u, _, _) => NetGuard.connectPinned(
    pinnedAddress,
    u,
    onBadCertificate: NetGuard.pinnedCertCheck(pinnedCertSha256 ?? ''),
  );
