import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;
import '../../models/ociserve_settings.dart';
import '../../utils/log.dart';
import 'ociserve_http.dart';
import 'ociserve_public_http_web.dart';
import 'ociserve_step_up.dart';
import 'ociserve_web_session.dart';

final _session = _BrowserSession();
OciServeWebSessionClient createOciServeWebSessionClient() => _session;
OciServeHttpTransport createBrowserAccountTransport() =>
    OciServeBrowserHttpTransport(
      accountSession: true,
      csrfToken: () => _session._csrf,
    );

class _BrowserSession implements OciServeWebSessionClient {
  String? _csrf;
  web.Window? _popup;
  int _epoch = 0;
  final _requests = <OciServeHttpTransport>{};
  @override
  bool get available => true;
  @override
  String get origin => Uri.base.origin;
  void _validate(OciServeSettings settings) {
    final uri = Uri.tryParse(settings.normalizedBaseUrl);
    if (!settings.enabled ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.origin != origin ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const OciServeException('web_origin_required');
    }
  }

  @override
  void prepareLogin() {
    _popup ??= web.window.open(
      'about:blank',
      'ocideck-ociserve-login',
      'popup,width=720,height=820',
    );
  }

  @override
  void cancel() {
    ++_epoch;
    _csrf = null;
    for (final request in _requests.toList()) {
      (request as OciServeClosableTransport).close();
    }
    _requests.clear();
    _closePopup();
  }

  void _closePopup() {
    try {
      _popup?.close();
    } catch (error) {
      logWarning('OciServe: aanmeldvenster sluiten (${error.runtimeType})');
    }
    _popup = null;
  }

  Future<Map<String, Object?>?> _metadata(OciServeSettings settings) async {
    _validate(settings);
    final epoch = _epoch;
    final transport = createBrowserAccountTransport();
    _requests.add(transport);
    try {
      final response = await transport.send(
        method: 'GET',
        url: Uri.parse(
          origin,
        ).replace(path: '/api/v1/auth/web/ocideck-session'),
        trustedInternal: false,
        headers: const {
          'accept': 'application/json',
          'x-ociserve-client': 'ocideck',
        },
        maxResponseBytes: 16 * 1024,
        timeout: const Duration(seconds: 10),
      );
      if (epoch != _epoch) throw const OciServeException('cancelled');
      if (response.statusCode == 401 || response.statusCode == 404) {
        _csrf = null;
        return null;
      }
      if (response.statusCode == 403) {
        throw const OciServeException('web_origin_required');
      }
      if (response.statusCode != 200) {
        throw OciServeException('http_error', statusCode: response.statusCode);
      }
      final data = Map<String, Object?>.from(
        jsonDecode(utf8.decode(response.body)) as Map,
      );
      final value = data['csrf_token'];
      if (value is! String || value.length < 32 || value.length > 128) {
        throw const OciServeException('invalid_response');
      }
      _csrf = value;
      return data;
    } on OciServeTransportException catch (error) {
      throw OciServeException(error.code);
    } on FormatException {
      throw const OciServeException('invalid_response');
    } on TypeError {
      throw const OciServeException('invalid_response');
    } finally {
      _requests.remove(transport);
      (transport as OciServeClosableTransport).close();
    }
  }

  OciServeBrowserSession _parse(Map<String, Object?> data) {
    try {
      final issuer = Uri.parse(data['issuer'] as String);
      final absolute = DateTime.parse(data['expires_at'] as String).toUtc();
      final idle = DateTime.parse(data['idle_expires_at'] as String).toUtc();
      if (issuer.scheme != 'https' ||
          issuer.host.isEmpty ||
          issuer.userInfo.isNotEmpty) {
        throw const FormatException();
      }
      return OciServeBrowserSession(
        binding: data['session_id'] as String,
        issuer: issuer,
        expiresAt: idle.isBefore(absolute) ? idle : absolute,
      );
    } on FormatException {
      throw const OciServeException('invalid_response');
    } on TypeError {
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeBrowserSession?> restore(OciServeSettings settings) async {
    final data = await _metadata(settings);
    return data == null ? null : _parse(data);
  }

  @override
  Future<OciServeBrowserSession> login(
    OciServeSettings settings, {
    OciServeStepUpRequired? stepUp,
    String? loginHint,
    bool forceLogin = false,
  }) async {
    _validate(settings);
    prepareLogin();
    if (_popup == null) throw const OciServeException('browser_refused');
    final epoch = ++_epoch;
    final requestID = const Uuid().v4();
    final uri = Uri.parse(origin).replace(
      path: '/api/v1/auth/web/login',
      queryParameters: {
        'application': 'ocideck',
        'request_id': requestID,
        'login_hint': ?loginHint,
        if (forceLogin) 'force_authentication': 'true',
        if (stepUp != null && stepUp.acrValues.isNotEmpty)
          'acr_values': stepUp.acrValues.join(' '),
        if (stepUp?.maxAge case final age?) 'max_age': '${age.inSeconds}',
      },
    );
    try {
      _popup!.location.href = uri.toString();
      final elapsed = Stopwatch()..start();
      while (elapsed.elapsed < const Duration(minutes: 2)) {
        if (epoch != _epoch) throw const OciServeException('cancelled');
        final data = await _metadata(settings);
        if (epoch != _epoch) throw const OciServeException('cancelled');
        if (data != null && data['login_request_id'] == requestID) {
          return _parse(data);
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      throw const OciServeException('authorization_timeout');
    } finally {
      _closePopup();
    }
  }

  @override
  Future<void> logout(
    OciServeSettings settings, {
    String? sessionMarker,
  }) async {
    _validate(settings);
    if (_csrf == null || sessionMarker == null) {
      final restored = await restore(settings);
      if (restored == null) {
        cancel();
        return;
      }
      sessionMarker ??= restored.marker;
    }
    final transport = createBrowserAccountTransport();
    try {
      final response = await transport.send(
        method: 'POST',
        url: Uri.parse(origin).replace(path: '/api/v1/auth/web/logout'),
        trustedInternal: false,
        headers: {'authorization': 'Bearer $sessionMarker'},
        maxResponseBytes: 16 * 1024,
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode == 401 && await restore(settings) != null) {
        throw const OciServeException('logout_cleanup_failed');
      }
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 401) {
        throw OciServeException('http_error', statusCode: response.statusCode);
      }
    } on OciServeTransportException catch (error) {
      throw OciServeException(error.code);
    } finally {
      (transport as OciServeClosableTransport).close();
      cancel();
    }
  }
}
