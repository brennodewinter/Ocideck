import '../../models/ociserve_settings.dart';
import 'ociserve_http.dart';
import 'ociserve_step_up.dart';
import 'ociserve_web_session_stub.dart'
    if (dart.library.js_interop) 'ociserve_web_session_browser.dart'
    as implementation;

/// Compatibility marker for the typed gateway. It is never a credential and
/// the browser transport removes it before Fetch. Native OAuth stays separate.
const ociServeBrowserSessionMarker = 'ociserve-bff-session:';
final _bindingPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class OciServeBrowserSession {
  const OciServeBrowserSession({
    required this.issuer,
    required this.expiresAt,
    required this.binding,
  });
  final Uri issuer;
  final String binding;
  String get marker => ociServeBrowserSessionMarker + binding;
  final DateTime expiresAt;
}

abstract class OciServeWebSessionClient {
  bool get available;
  String? get origin;
  void prepareLogin();
  void cancel();
  Future<OciServeBrowserSession?> restore(OciServeSettings settings);
  Future<OciServeBrowserSession> login(
    OciServeSettings settings, {
    OciServeStepUpRequired? stepUp,
    String? loginHint,
    bool forceLogin = false,
  });
  Future<void> logout(OciServeSettings settings, {String? sessionMarker});
}

OciServeWebSessionClient createOciServeWebSessionClient() =>
    implementation.createOciServeWebSessionClient();

/// The same-origin policy is independent of Fetch and testable on the VM.
Map<String, String> ociServeBffHeaders({
  required Uri url,
  required Uri appOrigin,
  required String method,
  required Map<String, String> headers,
  String? csrfToken,
}) {
  if (url.scheme != 'https' ||
      !url.hasAuthority ||
      url.host.isEmpty ||
      url.origin != appOrigin.origin ||
      url.userInfo.isNotEmpty ||
      url.hasFragment ||
      !url.path.startsWith('/api/v1/') ||
      url.path.startsWith('/api/v1/public/file-shares/')) {
    throw const OciServeTransportException('web_origin_required');
  }
  final result = {
    for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
  };
  final authorization = result.remove('authorization');
  if (result.containsKey('cookie')) {
    throw const OciServeTransportException('request_refused');
  }
  if (authorization != null) {
    const prefix = 'Bearer $ociServeBrowserSessionMarker';
    if (!authorization.startsWith(prefix) ||
        !_bindingPattern.hasMatch(authorization.substring(prefix.length))) {
      throw const OciServeTransportException('request_refused');
    }
    result['x-ociserve-client'] = 'ocideck';
    result['x-ociserve-session'] = authorization.substring(prefix.length);
    if (!{'GET', 'HEAD', 'OPTIONS'}.contains(method)) {
      if (csrfToken == null || csrfToken.isEmpty) {
        throw const OciServeTransportException('session_expired');
      }
      result['x-csrf-token'] = csrfToken;
    }
  }
  return result;
}
