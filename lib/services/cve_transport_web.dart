import 'cve_transport.dart';

/// The web build has no SSRF-pinned socket layer, so CVE lookup is desktop-only;
/// the UI already gates the feature off on web, so this is never invoked.
CveTransport createCveTransport() => const _UnsupportedCveTransport();

class _UnsupportedCveTransport implements CveTransport {
  const _UnsupportedCveTransport();

  @override
  Future<String> getBody(Uri uri) async =>
      throw const CveTransportException('web-unsupported');
}
