// Web-implementatie van de config.js-fetch: bewust fail-closed. De browser
// kan de host wel fetchen, maar de socket-pinning/CSP-beslissing die deze
// egress afdwingbaar maakt is er nog niet (dezelfde grens als
// `xmpp_frame_transport_web`). Tot die ligt weigert web — een preflight die
// "werkt maar niet gecontroleerd" is, is erger dan een eerlijke afwezigheid.

Future<String> fetchJitsiConfig(
  Uri configUrl, {
  required bool allowPrivate,
  String pinnedCertSha256 = '',
  Duration timeout = const Duration(seconds: 15),
  int maxBytes = 256 * 1024,
}) => throw UnsupportedError('Jitsi-preflight is op web nog niet beschikbaar');
