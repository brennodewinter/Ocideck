/// Fetches the response body of [uri] for the CVE search
/// (`cve_search_service.dart`). Injected so tests never touch the network; the
/// default IO implementation is SSRF-pinned (see `cve_transport_io.dart`), and
/// the web build has no transport (CVE lookup is desktop-only).
abstract class CveTransport {
  Future<String> getBody(Uri uri);
}

/// A transport-layer failure: a disallowed scheme/host, a non-200 status, an
/// over-cap body, or an unsupported platform (web).
class CveTransportException implements Exception {
  const CveTransportException(this.reason);

  final String reason;

  @override
  String toString() => 'CveTransportException: $reason';
}
