// Een inzendserver in het geheugen, naar INTAKE_PROTOCOL.md: de plek waar de client zijn
// toetsen tegen draait zonder netwerk. Het is een [IntakeHttp], dus de client praat er
// zoals met de echte; de routes en de grammatica komen uit de kern (`matchIntakeRoute`), niet uit
// een tweede lezing van het document.
//
// Wat er van het protocol in zit groeit met de client: `info`, het formulier en het uploaden —
// met de controles in de volgorde van INTAKE_PROTOCOL.md §4.3.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ocideck/services/form/intake/intake_http.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

/// De uitnodigingstoken die een gepubliceerd formulier standaard accepteert.
const String kTestInvite = 'nvqwy3dpoixxg5dfonzgc3tjnq';

/// Een verzoek zoals de server het kreeg.
class FakeIntakeRequest {
  FakeIntakeRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> body;

  String get target => url.hasQuery ? '${url.path}?${url.query}' : url.path;
}

class FakeIntakeServer implements IntakeHttp {
  FakeIntakeServer({this.host = 'intake.example.org'});

  /// De host zoals de uitnodiging hem noemt; een verzoek aan een andere host komt nergens.
  final String host;

  /// Wat `GET /v1/info` zegt.
  int protocol = 1;
  int maxPackageBytes = 60 * 1024 * 1024;
  String sourceUrl = 'https://example.org/ocideck-intake';
  String operatorContact = 'beheer@example.org';

  /// De gepubliceerde formulieren, per `fid`, met de hash van hun open uitnodigingstoken.
  final Map<
    String,
    ({IntakeFormState state, List<IntakeVariant> variants, String? tokenHash})
  >
  forms = {};

  /// Wat de server bewaart, per `sid`: het formulier, de ciphertext, wanneer hij kwam en de hash
  /// van het intrekgeheim.
  final Map<
    String,
    ({
      String fid,
      Uint8List bytes,
      String hash,
      String at,
      String withdrawalHash,
    })
  >
  submissions = {};

  /// De klok van de server, voor de aankomsttijd en de sluitingsdag.
  DateTime Function() clock = () => DateTime.utc(2026, 11, 3, 9, 30, 12);

  /// Het contactadres in elk aankomstbericht.
  String contact = 'redactie@example.org';

  /// Zo vaak antwoordt de server de eerstvolgende uploads met `429`.
  int rateLimited = 0;
  Duration? retryAfter;

  /// Elk verzoek in volgorde van binnenkomst.
  final List<FakeIntakeRequest> requests = [];

  /// Hoeveel verzoeken af zijn (met een antwoord of een mislukking): `requests.length` min wat nog
  /// vastzit achter [gate].
  int completed = 0;

  /// Als dit gezet is, mislukt elk verzoek zo.
  IntakeHttpFailure? failWith;

  /// Houdt elk verzoek vast tot de test dit loslaat: zo is te zien wat de client doet terwijl
  /// hij wacht.
  Completer<void>? gate;

  /// Antwoorden die dit te lezen krijgen in plaats van het protocol, per doel
  /// (`/v1/info`, `/v1/forms/<fid>`), voor een server die zich misdraagt.
  final Map<String, IntakeHttpResponse> overrides = {};

  void publish(
    String fid,
    List<IntakeVariant> variants, {
    IntakeFormState state = IntakeFormState.open,
    String? token = kTestInvite,
  }) {
    forms[fid] = (
      state: state,
      variants: variants,
      tokenHash: token == null ? null : inviteTokenHash(token),
    );
  }

  @override
  Future<IntakeHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    List<int>? body,
    required int maxResponseBytes,
    required Duration timeout,
  }) async {
    final request = FakeIntakeRequest(method, url, headers, body ?? const []);
    requests.add(request);
    try {
      return await _answer(request, maxResponseBytes);
    } finally {
      completed++;
    }
  }

  Future<IntakeHttpResponse> _answer(
    FakeIntakeRequest request,
    int maxResponseBytes,
  ) async {
    final method = request.method;
    final url = request.url;
    await gate?.future;
    if (failWith != null) throw IntakeHttpException(failWith!);
    if (url.scheme != 'https' ||
        '${url.host}${url.hasPort && url.port != 443 ? ':${url.port}' : ''}' !=
            host) {
      throw const IntakeHttpException(IntakeHttpFailure.network);
    }
    final canned = overrides[request.target];
    if (canned != null) return _capped(canned, maxResponseBytes);

    final routed = matchIntakeRoute(method, request.target);
    if (routed is IntakeRouteRefused) return _error(routed.code);
    final route = (routed as IntakeRouteMatched).route;
    return _capped(switch (route) {
      IntakeInfoRoute() => _json(200, {
        'protocol': protocol,
        'limits': {'max_package_bytes': maxPackageBytes},
        'source_url': sourceUrl,
        'operator_contact': operatorContact,
      }),
      IntakeGetFormRoute(:final fid) => _form(fid),
      IntakeUploadRoute(:final sid) => _upload(sid, request),
      _ => _error(IntakeErrorCode.notFound),
    }, maxResponseBytes);
  }

  IntakeHttpResponse _form(String fid) {
    final form = forms[fid];
    if (form == null) return _error(IntakeErrorCode.formUnknown);
    return _json(
      200,
      IntakeForm(state: form.state, variants: form.variants).toJson(),
    );
  }

  /// Een upload, in de volgorde van het protocol; elke stap eindigt het verzoek met zijn fout.
  IntakeHttpResponse _upload(String sid, FakeIntakeRequest request) {
    final fid = request.headers['intake-form'];
    final withdrawal = request.headers['intake-withdrawal'];
    // 1. de ids en de kop.
    if (fid == null ||
        !isValidFormId(fid) ||
        withdrawal == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(withdrawal)) {
      return _error(IntakeErrorCode.badRequest);
    }
    // 2. te groot, vóór er een byte is gelezen.
    if (request.body.length > maxPackageBytes) {
      return _error(IntakeErrorCode.tooLarge);
    }
    // 3. het formulier.
    final form = forms[fid];
    if (form == null) return _error(IntakeErrorCode.formUnknown);
    // 4. de uitnodigingstoken.
    final token = request.headers['intake-token'];
    if (token == null ||
        form.tokenHash == null ||
        inviteTokenHash(token) != form.tokenHash) {
      return _error(IntakeErrorCode.inviteInvalid);
    }
    // 5. gesloten.
    if (form.state == IntakeFormState.closed) {
      return _error(IntakeErrorCode.formClosed);
    }
    // 6. te veel verzoeken.
    if (rateLimited > 0) {
      rateLimited--;
      return raw(
        429,
        IntakeError(IntakeErrorCode.rateLimited, 'Rustig aan.').toJsonText(),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          if (retryAfter != null) 'retry-after': '${retryAfter!.inSeconds}',
        },
      );
    }
    // 7 en 8. de hash, en wat er al onder dit nummer staat.
    final bytes = Uint8List.fromList(request.body);
    final hash = sha256Hex(bytes);
    final held = submissions[sid];
    if (held != null && (held.fid != fid || held.hash != hash)) {
      return _error(IntakeErrorCode.submissionConflict);
    }
    final stored =
        held ??
        (submissions[sid] = (
          fid: fid,
          bytes: bytes,
          hash: hash,
          at: _stamp(clock()),
          withdrawalHash: withdrawal,
        ));
    return _json(held == null ? 201 : 200, {
      'sid': sid,
      'at': stored.at,
      'ciphertext_sha256': stored.hash,
      'contact': contact,
    });
  }

  static String _stamp(DateTime t) =>
      '${t.toUtc().toIso8601String().split('.').first}Z';

  static IntakeHttpResponse _capped(IntakeHttpResponse r, int max) {
    if (r.body.length > max) {
      throw const IntakeHttpException(IntakeHttpFailure.responseTooLarge);
    }
    return r;
  }

  static IntakeHttpResponse _json(int status, Object body) => raw(
    status,
    jsonEncode(body),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  static IntakeHttpResponse _error(IntakeErrorCode code) => raw(
    code.status,
    IntakeError(code, 'Fout: ${code.wire}').toJsonText(),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  /// Een antwoord met deze tekst, voor [overrides].
  static IntakeHttpResponse raw(
    int status,
    String body, {
    Map<String, String> headers = const {},
  }) => IntakeHttpResponse(
    statusCode: status,
    body: Uint8List.fromList(utf8.encode(body)),
    headers: headers,
  );
}
