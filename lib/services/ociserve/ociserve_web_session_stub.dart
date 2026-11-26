import '../../models/ociserve_settings.dart';
import 'ociserve_http.dart';
import 'ociserve_step_up.dart';
import 'ociserve_web_session.dart';

OciServeWebSessionClient createOciServeWebSessionClient() =>
    const _UnavailableWebSession();

class _UnavailableWebSession implements OciServeWebSessionClient {
  const _UnavailableWebSession();
  @override
  bool get available => false;
  @override
  String? get origin => null;
  @override
  void prepareLogin() {}
  @override
  void cancel() {}
  @override
  Future<OciServeBrowserSession?> restore(OciServeSettings settings) async =>
      null;
  @override
  Future<OciServeBrowserSession> login(
    OciServeSettings settings, {
    OciServeStepUpRequired? stepUp,
    String? loginHint,
    bool forceLogin = false,
  }) async => throw const OciServeException('not_available');
  @override
  Future<void> logout(
    OciServeSettings settings, {
    String? sessionMarker,
  }) async {}
}
