import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/ociserve_intake.dart';
import '../../models/ociserve_settings.dart';
import '../../utils/log.dart';
import 'ociserve_http.dart';
import 'ociserve_http_factory.dart';

/// De respondentkant van Managed Intake (ADR 0016): een bewust dunne,
/// aparte transportclient die **nooit een OIDC-token of de sessie van de
/// organisator vasthoudt** — alleen de kortlevende [IntakeGrant] die een
/// geverifieerde mailboxcode opleverde (FORM_INTAKE.md §6.6). De twee
/// auth-ketens delen geen referenties en geen codepad dat ze zou kunnen
/// verwisselen.
///
/// De basis-URL komt uit de uitnodigingslink van de organisator — nooit uit
/// de OciServe-instelling van dit apparaat. Locator, code, grant en
/// idempotency-key gaan in het pad of in headers zoals het contract voorschrijft
/// — nooit in een query, log of foutmelding.
class IntakeRespondentClient {
  IntakeRespondentClient({
    required String baseUrl,
    this.trustedInternal = false,
    OciServeHttpTransport? transport,
  }) : _transport = transport ?? createOciServeHttpTransport() {
    final refusal = validateOciServeBaseUrl(baseUrl);
    if (refusal != null) throw OciServeException(refusal);
    _base = Uri.parse(normalizeOciServeBaseUrl(baseUrl));
  }

  /// De contractgrens voor een inzendpakket — grotere uploads stopt de
  /// client voordat er een byte het netwerk op gaat.
  static const maxPackageBytes = 120 * 1024 * 1024;

  static const _jsonCap = 2 * 1024 * 1024;
  static const _controlTimeout = Duration(seconds: 30);
  static const _payloadTimeout = Duration(minutes: 2);

  final OciServeHttpTransport _transport;

  /// De beheerder van de respondentmachine heeft deze installatie als
  /// intern vertrouwd gemarkeerd — zie [OciServeGateway.trustedInternal].
  final bool trustedInternal;
  late final Uri _base;

  Uri _api(List<String> segments) => _base.replace(
    pathSegments: [
      ..._base.pathSegments.where((part) => part.isNotEmpty),
      'api',
      'v1',
      ...segments,
    ],
    query: null,
    fragment: null,
  );

  /// Deelt één vorm met de organisatorgateway: probleemantwoorden lezen en
  /// sanitizen — `unauthorized` op 401, `http_error` + probleemdetails
  /// elders, `invalid_response` als het transport iets onverwachts geeft.
  Future<OciServeHttpResponse> _send({
    required String method,
    required Uri url,
    IntakeGrant? grant,
    Map<String, String> headers = const {},
    List<int>? body,
    int cap = _jsonCap,
    Duration timeout = _controlTimeout,
    bool allowNotModified = false,
  }) async {
    try {
      final response = await _transport.send(
        method: method,
        url: url,
        trustedInternal: trustedInternal,
        headers: {
          'accept': 'application/json',
          if (grant != null) 'authorization': 'Bearer ${grant.token}',
          ...headers,
        },
        body: body,
        maxResponseBytes: cap,
        timeout: timeout,
      );
      if (allowNotModified && response.statusCode == 304) return response;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OciServeException(
          response.statusCode == 401 ? 'unauthorized' : 'http_error',
          statusCode: response.statusCode,
          problem: ociServeProblemOf(response),
        );
      }
      return response;
    } on OciServeException {
      rethrow;
    } on OciServeTransportException catch (e) {
      throw OciServeException(e.code);
    } catch (error, stack) {
      logError('Intake: antwoord ontvangen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  T _parse<T>(
    OciServeHttpResponse response,
    String what,
    T Function(Map<String, Object?>) parse,
  ) {
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is! Map) throw const FormatException();
      return parse(Map<String, Object?>.from(decoded));
    } catch (error, stack) {
      if (error is OciServeException) rethrow;
      logError('Intake: $what lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  /// Het gepubliceerde formulier achter [formRef] — publiek, zonder
  /// enige credential (security: [] in het contract).
  Future<IntakePublicForm> publicForm(String formRef) async {
    final response = await _send(
      method: 'GET',
      url: _api(['intake', 'forms', formRef.trim()]),
    );
    return _parse(response, 'intake-formulier', IntakePublicForm.fromJson);
  }

  /// Vraagt een mailboxcode aan voor [purpose] (202 — het antwoord is
  /// bewust identiek voor bekende en onbekende invoer). `start` eist
  /// [formRef], de overige doelen [locator]; iets anders is een
  /// clientfout, geen servervraag.
  Future<IntakeChallenge> requestChallenge({
    required IntakePurpose purpose,
    required String email,
    String? formRef,
    String? locator,
  }) async {
    final trimmedEmail = email.trim();
    final needsForm = purpose == IntakePurpose.start;
    if (trimmedEmail.isEmpty ||
        trimmedEmail.length > 320 ||
        (needsForm
            ? (formRef?.trim().isEmpty ?? true)
            : (locator?.trim().isEmpty ?? true))) {
      throw const OciServeException('invalid_request');
    }
    final response = await _send(
      method: 'POST',
      url: _api(['intake', 'challenges']),
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(
        jsonEncode({
          'purpose': purpose.wireName,
          'email': trimmedEmail,
          'form_ref': ?formRef?.trim(),
          'locator': ?locator?.trim(),
        }),
      ),
    );
    if (response.statusCode != 202) {
      throw const OciServeException('invalid_response');
    }
    return _parse(response, 'intake-uitdaging', IntakeChallenge.fromJson);
  }

  /// Levert de getypte mailbox[code] in en ontvangt de kortlevende
  /// [IntakeGrant] voor één inzending, één formulier en één doel.
  Future<IntakeGrant> verifyChallenge({
    required String challengeId,
    required String code,
  }) async {
    final trimmedCode = code.trim();
    if (challengeId.trim().isEmpty ||
        trimmedCode.length < 6 ||
        trimmedCode.length > 16) {
      throw const OciServeException('invalid_request');
    }
    final response = await _send(
      method: 'POST',
      url: _api(['intake', 'challenges', challengeId.trim(), 'verify']),
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(jsonEncode({'code': trimmedCode})),
    );
    return _parse(response, 'intake-grant', IntakeGrant.fromJson);
  }

  /// De eigen inzendingstoestand; `null` als de server op [ifNoneMatch] met
  /// 304 antwoordt.
  Future<OciServeEtag<IntakeRespondentSubmission>?> submission({
    required IntakeGrant grant,
    String? ifNoneMatch,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['intake', 'submissions', grant.locator]),
      grant: grant,
      headers: {'if-none-match': ?ifNoneMatch},
      allowNotModified: true,
    );
    if (response.statusCode == 304) return null;
    final etag = response.headers['etag']?.trim();
    return OciServeEtag(
      _parse(response, 'intake-inzending', IntakeRespondentSubmission.fromJson),
      etag == null || etag.isEmpty ? null : etag,
    );
  }

  /// Zet het ontwerppakket neer (octet-stream) en toetst dat de server
  /// precies de verstuurde bytes ontving — een afwijkende `sha256` of
  /// `size` in de ontvangst is een harde fout, geen retry.
  Future<IntakeDraftReceipt> putDraft({
    required IntakeGrant grant,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > maxPackageBytes) {
      throw const OciServeException('package_too_large');
    }
    final response = await _send(
      method: 'PUT',
      url: _api(['intake', 'submissions', grant.locator, 'draft']),
      grant: grant,
      headers: const {'content-type': 'application/octet-stream'},
      body: bytes,
      timeout: _payloadTimeout,
    );
    final receipt = _parse(
      response,
      'intake-ontvangst',
      IntakeDraftReceipt.fromJson,
    );
    if (receipt.size != bytes.length ||
        receipt.sha256 != sha256.convert(bytes).toString()) {
      throw const OciServeException('intake_digest_mismatch');
    }
    return receipt;
  }

  /// Legt het huidige ontwerp definitief vast als nieuwe immutable revisie
  /// (201). [expectedSha256]/[expectedSize] zijn de digest van het
  /// ingediende pakket — afwijking is een harde fout.
  Future<IntakeSubmitReceipt> submit({
    required IntakeGrant grant,
    required String idempotencyKey,
    required String expectedSha256,
    required int expectedSize,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(['intake', 'submissions', grant.locator, 'submit']),
      grant: grant,
      headers: {'idempotency-key': idempotencyKey},
      body: const [],
    );
    if (response.statusCode != 201) {
      throw const OciServeException('invalid_response');
    }
    final receipt = _parse(
      response,
      'intake-indiening',
      IntakeSubmitReceipt.fromJson,
    );
    if (receipt.size != expectedSize ||
        receipt.sha256 != expectedSha256.toLowerCase()) {
      throw const OciServeException('intake_digest_mismatch');
    }
    return receipt;
  }

  /// Trekt de inzending in; de server moet `withdrawn` melden en trekt de
  /// uitstaande grants in.
  Future<IntakeWithdrawReceipt> withdraw({
    required IntakeGrant grant,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(['intake', 'submissions', grant.locator, 'withdraw']),
      grant: grant,
      headers: {'idempotency-key': idempotencyKey},
      body: const [],
    );
    final receipt = _parse(
      response,
      'intake-intrekking',
      IntakeWithdrawReceipt.fromJson,
    );
    if (receipt.state != IntakeSubmissionState.withdrawn) {
      throw const OciServeException('invalid_response');
    }
    return receipt;
  }
}
