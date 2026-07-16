import 'dart:typed_data';

/// Antwoord van één begrensde GET. Bewust ruw: het transport interpreteert
/// niets, dat doet de forge-adapter.
class GitResponse {
  final int status;
  final Uint8List bytes;

  const GitResponse(this.status, this.bytes);

  bool get isOk => status >= 200 && status < 300;
}

/// De HTTP-laag onder [GitForge], gescheiden omdat io en web hem fundamenteel
/// anders moeten invullen: op desktop met SSRF-pinning uit [NetGuard], op web
/// met de browser-fetch (waar die pinning niet bestaat en ook niet kan).
///
/// Het transport kent géén provider-specifieke details — ook de auth-header
/// niet, want die verschilt per forge (Forgejo `token`, GitHub `Bearer`,
/// GitLab `PRIVATE-TOKEN`). De adapter levert de headers aan; zo lekt er geen
/// provider-kennis naar beneden (P6).
abstract class GitTransport {
  /// Eén GET met een harde bytecap. Gooit [GitForgeException] bij een
  /// geweigerde host, een transportfout of overschrijding van de cap; een
  /// HTTP-foutstatus komt gewoon terug in [GitResponse.status], want wat een
  /// 404 betekent weet alleen de adapter.
  Future<GitResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  });

  /// Als [get], maar met een body. Zelfde afspraak over fouten: een
  /// HTTP-foutstatus komt terug in [GitResponse.status] en is aan de adapter om
  /// te duiden — een 409 betekent bij een commit iets heel anders dan bij een
  /// leesactie.
  Future<GitResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> body,
    required int maxBytes,
  });

  void close();
}
