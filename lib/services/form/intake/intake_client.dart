// De client van het inzendprotocol (docs/design/INTAKE_PROTOCOL.md; FORM_INTAKE.md §6.6): wat
// de invuller doet tegen een inzendserver. Alles wat hij van de server gelooft komt uit de
// **ondertekende bundel**, getoetst aan de vingerafdruk uit de uitnodiging; de rest is
// vervoer. Elke uitkomst is een waarde, geen uitzondering — de dialoog erboven vertaalt ze naar
// een zin in de taal van de invuller.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'intake_http.dart';

/// Wat er mis ging, op het niveau waarop de invuller er iets mee kan.
enum IntakeProblem {
  /// Geen antwoord: [IntakeFailed.http] zegt waarom.
  unreachable,

  /// Het adres antwoordt niet als een inzendserver.
  notIntakeServer,

  /// De server spreekt een oudere versie van het protocol dan deze client kent.
  serverTooOld,

  /// De server spreekt een nieuwere versie.
  serverTooNew,

  /// De server weigerde met een code van het protocol: [IntakeFailed.error].
  serverRefused,

  /// De server stuurde een formulier dat niet te lezen is: [IntakeFailed.formIssue].
  formMalformed,

  /// De server zegt `200` of `201` maar zijn aankomstbericht is geen bericht, of gaat over iets
  /// anders dan wat is verstuurd: een ander inzendnummer of een andere hash. Wat de server
  /// ontving is dan niet wat de invuller stuurde.
  noteMismatch,

  /// Geen enkele bundel werd geloofd: [IntakeFailed.bundleIssue] is de reden van de eerste.
  bundleRefused,
}

/// Een bewerking die niet slaagde.
class IntakeFailed implements IntakeOpenResult, IntakeSubmitResult {
  const IntakeFailed(
    this.problem, {
    this.http,
    this.error,
    this.formIssue,
    this.bundleIssue,
    this.retryAfter,
  });

  final IntakeProblem problem;
  final IntakeHttpFailure? http;
  final IntakeError? error;
  final IntakeFormIssue? formIssue;
  final FormBundleIssue? bundleIssue;

  /// Wanneer de server vraagt het opnieuw te proberen (`Retry-After`), als hij dat deed.
  final Duration? retryAfter;
}

/// Wat [IntakeClient.openInvitation] opleverde.
sealed class IntakeOpenResult {
  const IntakeOpenResult();
}

/// Wat [IntakeClient.submit] opleverde.
sealed class IntakeSubmitResult {
  const IntakeSubmitResult();
}

/// De inzending staat bij de server, en het bericht gaat over precies wat is verstuurd.
class IntakeSubmitted extends IntakeSubmitResult {
  const IntakeSubmitted({required this.note, required this.alreadyHeld});

  /// Wat de server zegt ontvangen te hebben. **Geen bewijs tegen de server**: hij zou alles
  /// ondertekenen; de invuller kan er de hash en de tijd aan noemen.
  final IntakeArrivalNote note;

  /// De server had deze inzending al (een herhaling, `200`): het eerste antwoord ging verloren.
  final bool alreadyHeld;
}

/// Eén sjabloon waarvan de bundel is geloofd.
class IntakeOpenedVariant {
  const IntakeOpenedVariant({
    required this.template,
    required this.spec,
    required this.bundleText,
    required this.verified,
  });

  /// De tekst van het sjabloon, zoals de bundel hem ondertekende.
  final String template;

  /// Het formulier dat erin staat.
  final FormSpec spec;

  /// De bundel als tekst, zoals [verifyFormBundle] hem las.
  final String bundleText;

  final FormBundleVerified verified;
}

/// Een uitnodiging is geopend: de server is een inzendserver, en minstens één bundel is geloofd.
class IntakeOpened extends IntakeOpenResult {
  const IntakeOpened({
    required this.invite,
    required this.info,
    required this.state,
    required this.variants,
    required this.pins,
  });

  final InviteLink invite;
  final IntakeInfo info;

  /// Of de server het formulier open of gesloten noemt. **Adviserend**: de server dwingt het
  /// af bij het uploaden, en de bundel noemt zelf de sluitingsdag.
  final IntakeFormState state;

  /// De sjablonen waarvan de bundel is geloofd, in de volgorde van de server.
  final List<IntakeOpenedVariant> variants;

  /// De pins na deze bundels: de aanroeper bewaart ze.
  final FormBundlePins pins;
}

/// Praat met een inzendserver.
class IntakeClient {
  IntakeClient(this._http, {this.timeout});

  final IntakeHttp _http;

  /// Hoe lang één verzoek mag duren; `null` laat het aan de HTTP-laag.
  final Duration? timeout;

  /// Haalt het formulier van een uitnodiging op en toetst wat de server zegt.
  ///
  /// In deze volgorde: de server noemt zich een inzendserver van een versie die deze client
  /// kent (`GET /v1/info`), dan het formulier (`GET /v1/forms/{fid}`), en dan elke bundel
  /// **tegen de vingerafdruk uit de uitnodiging** — handtekening, sjabloon, geldigheid, het
  /// adres van de server en de pins. Een bundel die niet slaagt valt af; slaagt er geen, dan is
  /// het formulier geweigerd, met de reden van de eerste.
  ///
  /// Elke bundel wordt getoetst aan de pins zoals ze **voor** dit antwoord waren: de bundels van
  /// verschillende talen hebben elk hun eigen volgnummer, en een lagere in dezelfde reeks is
  /// geen terugval.
  Future<IntakeOpenResult> openInvitation(
    InviteLink invite, {
    required FormBundlePins pins,
    required DateTime now,
  }) async {
    final infoGot = await _get(invite, intakeInfoTarget, 64 * 1024);
    if (infoGot.failed != null) return infoGot.failed!;
    final info = parseIntakeInfo(_text(infoGot.ok!));
    if (info is IntakeInfoRefused) {
      return IntakeFailed(switch (info.issue) {
        IntakeInfoIssue.serverTooOld => IntakeProblem.serverTooOld,
        IntakeInfoIssue.serverTooNew => IntakeProblem.serverTooNew,
        _ => IntakeProblem.notIntakeServer,
      });
    }
    info as IntakeInfoRead;

    final formGot = await _get(
      invite,
      intakeFormTarget(invite.fid),
      kIntakeMaxFormBytes + 1024,
    );
    if (formGot.failed != null) return formGot.failed!;
    final read = parseIntakeFormResponse(_text(formGot.ok!));
    if (read is IntakeFormRefused) {
      return IntakeFailed(IntakeProblem.formMalformed, formIssue: read.issue);
    }
    final form = (read as IntakeFormRead).form;

    final variants = <IntakeOpenedVariant>[];
    FormBundleIssue? firstIssue;
    var accepted = pins;
    for (final variant in form.variants) {
      final result = await verifyFormBundle(
        variant.bundleText,
        templateText: variant.template,
        fingerprint: invite.fingerprint,
        now: now,
        expectedApiHost: invite.apiHost,
        pins: pins,
      );
      if (result is FormBundleRefused) {
        firstIssue ??= result.issue;
        continue;
      }
      result as FormBundleVerified;
      // Een bundel voor een ander formulier van dezelfde organisator is geloofd, maar niet
      // het formulier waar deze uitnodiging over gaat.
      if (result.bundle.fid != invite.fid) {
        firstIssue ??= FormBundleIssue.templateMismatch;
        continue;
      }
      // De bundel is geloofd, dus het sjabloon is een formulier: `verifyFormBundle` weigert er
      // anders een.
      final spec = (parseForm(variant.template) as ParsedForm).spec;
      accepted = accepted.accepting(result.bundle, result.fingerprint);
      variants.add(
        IntakeOpenedVariant(
          template: variant.template,
          spec: spec,
          bundleText: variant.bundleText,
          verified: result,
        ),
      );
    }
    if (variants.isEmpty) {
      return IntakeFailed(
        IntakeProblem.bundleRefused,
        bundleIssue: firstIssue ?? FormBundleIssue.notABundle,
      );
    }
    return IntakeOpened(
      invite: invite,
      info: info.info,
      state: form.state,
      variants: variants,
      pins: accepted,
    );
  }

  /// Stuurt het verzegelde pakket [sealed] onder [sid] naar de server van [invite]
  /// (INTAKE_PROTOCOL.md §4.3).
  ///
  /// De server krijgt de uitnodigingstoken, het formulier en **alleen de hash** van het
  /// intrekgeheim: wat hij niet heeft kan hij niet lekken. Een herhaling met hetzelfde [sid] en
  /// dezelfde bytes is veilig (`200`, hetzelfde bericht); een ander pakket onder hetzelfde [sid]
  /// weigert de server. Het bericht dat terugkomt moet gaan over wat is verstuurd, anders is het
  /// [IntakeProblem.noteMismatch].
  Future<IntakeSubmitResult> submit({
    required InviteLink invite,
    required String sid,
    required Uint8List sealed,
    required String withdrawalSecret,
  }) async {
    final IntakeHttpResponse response;
    try {
      response = await _http.send(
        method: 'PUT',
        url: Uri.parse(
          'https://${invite.apiHost}${intakeSubmissionTarget(sid)}',
        ),
        headers: {
          'accept': 'application/json',
          'content-type': 'application/octet-stream',
          'intake-form': invite.fid,
          'intake-token': invite.token,
          'intake-withdrawal': withdrawalSecretHash(withdrawalSecret),
        },
        body: sealed,
        maxResponseBytes: 64 * 1024,
        timeout: timeout ?? const Duration(minutes: 10),
      );
    } on IntakeHttpException catch (e) {
      return IntakeFailed(IntakeProblem.unreachable, http: e.failure);
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      return IntakeFailed(
        IntakeProblem.serverRefused,
        error: parseIntakeError(response.statusCode, _text(response)),
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    final note = parseIntakeArrivalNote(_text(response));
    if (note == null ||
        note.sid != sid ||
        note.ciphertextSha256 != sha256Hex(sealed)) {
      return const IntakeFailed(IntakeProblem.noteMismatch);
    }
    return IntakeSubmitted(note: note, alreadyHeld: response.statusCode == 200);
  }

  /// Een `GET`: het antwoord bij 200, anders de mislukking.
  Future<_Got> _get(InviteLink invite, String target, int maxBytes) async {
    final IntakeHttpResponse response;
    try {
      response = await _http.send(
        method: 'GET',
        url: Uri.parse('https://${invite.apiHost}$target'),
        headers: const {'accept': 'application/json'},
        maxResponseBytes: maxBytes,
        timeout: timeout ?? const Duration(seconds: 30),
      );
    } on IntakeHttpException catch (e) {
      return _Got.failed(
        IntakeFailed(IntakeProblem.unreachable, http: e.failure),
      );
    }
    if (response.statusCode == 200) return _Got.ok(response);
    return _Got.failed(
      IntakeFailed(
        IntakeProblem.serverRefused,
        error: parseIntakeError(response.statusCode, _text(response)),
        retryAfter: _retryAfter(response.headers['retry-after']),
      ),
    );
  }
}

/// Het antwoord van een verzoek, of waarom er geen kwam. Precies één van beide is gevuld.
class _Got {
  const _Got.ok(IntakeHttpResponse this.ok) : failed = null;
  const _Got.failed(IntakeFailed this.failed) : ok = null;

  final IntakeHttpResponse? ok;
  final IntakeFailed? failed;
}

/// De body als tekst; wat geen UTF-8 is wordt een onleesbaar teken en dus geen formulier.
String _text(IntakeHttpResponse response) =>
    utf8.decode(response.body, allowMalformed: true);

/// `Retry-After` in seconden, begrensd tot een dag; een datumvorm of onzin is `null`.
Duration? _retryAfter(String? header) {
  final seconds = header == null ? null : int.tryParse(header.trim());
  if (seconds == null || seconds < 0) return null;
  return Duration(seconds: min(seconds, 86400));
}
