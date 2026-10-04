// De intake-context van een respondent (FORM_INTAKE.md §6.3, §6.4): bij welk
// gepubliceerd formulier dit ingevulde document hoort, en — zodra er een
// inzending is — onder welke locator hij daar bekend is.
//
// De context staat als gewone JSON in een sidecar naast het document
// (`<naam>.md.intake.json`). Er staat bewust niets geheims in: de locator is
// een verwijzing, geen sleutel — elke inhoudelijke actie eist een verse
// mailboxcode (§6.3). De mailboxcode en de grant komen hier dus nooit in.
library;

import 'dart:convert';
import 'dart:io';

import '../../models/ociserve_intake.dart';
import '../../utils/atomic_file.dart';

/// Waar een ingevuld formulier op de server om bekend is.
class FormIntakeContext {
  const FormIntakeContext({
    required this.baseUrl,
    required this.formRef,
    this.locator,
    this.revision,
    this.lastState,
  });

  /// De https-basis van de OciServe uit de uitnodigingslink.
  final String baseUrl;

  /// De publieke formuleerreferentie (`form_ref`) uit de link.
  final String formRef;

  /// De locator van de eigen inzending, zodra die bestaat. Niet geheim —
  /// op zichzelf opent hij niets.
  final String? locator;

  /// De hoogste revisie die deze client indiende, ter info op het scherm.
  final int? revision;

  /// De laatst geziene inzendingstoestand — bepaalt welke challenge-purpose
  /// de volgende stap vraagt (`correct` bij een open correctieronde).
  final IntakeSubmissionState? lastState;

  FormIntakeContext copyWith({
    String? locator,
    int? revision,
    IntakeSubmissionState? lastState,
  }) => FormIntakeContext(
    baseUrl: baseUrl,
    formRef: formRef,
    locator: locator ?? this.locator,
    revision: revision ?? this.revision,
    lastState: lastState ?? this.lastState,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'base_url': baseUrl,
    'form_ref': formRef,
    if (locator != null) 'locator': locator,
    if (revision != null) 'revision': revision,
    if (lastState != null) 'last_state': lastState!.wireName,
  };

  /// Strikte lezer: een sidecar die iets anders bevat is geen context en
  /// wordt genegeerd — hij is nooit het bewijs dat er een inzending is.
  static FormIntakeContext? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    final baseUrl = json['base_url'];
    final formRef = json['form_ref'];
    if (baseUrl is! String ||
        formRef is! String ||
        baseUrl.trim().isEmpty ||
        formRef.trim().isEmpty) {
      return null;
    }
    if (json.keys.any(
      (key) => !const {
        'v',
        'base_url',
        'form_ref',
        'locator',
        'revision',
        'last_state',
      }.contains(key),
    )) {
      return null;
    }
    final locator = json['locator'];
    final revision = json['revision'];
    if ((locator != null && locator is! String) ||
        (revision != null && revision is! int)) {
      return null;
    }
    final rawState = json['last_state'];
    IntakeSubmissionState? state;
    if (rawState != null) {
      try {
        state = IntakeSubmissionState.parse(rawState);
      } on FormatException {
        return null;
      }
    }
    return FormIntakeContext(
      baseUrl: baseUrl.trim(),
      formRef: formRef.trim(),
      locator: (locator as String?)?.trim(),
      revision: revision as int?,
      lastState: state,
    );
  }
}

/// Wat [parseIntakeLink] uit een geplakte link haalde.
class FormIntakeLink {
  const FormIntakeLink({required this.baseUrl, this.formRef, this.locator});

  /// De https-basis zonder pad.
  final String baseUrl;

  /// De `form_ref` uit een uitnodigingslink (`…/forms/{ref}`), of `null`.
  final String? formRef;

  /// De `locator` uit een terugkeerlink (`…/submissions/{locator}` of
  /// `?locator=…`), of `null`.
  final String? locator;
}

/// Leest de host en de referenties uit een uitnodigings- of terugkeerlink
/// (§6.4). Een uitnodiging draagt `…/forms/{form_ref}`; een terugkeerlink
/// `…/submissions/{locator}` — of een `locator`-query voor een linkvorm die
/// OciServe mailt zonder dat pad. `null` bij geen https-link met iets om te
/// pakken.
FormIntakeLink? parseIntakeLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    return null;
  }
  final baseUrl =
      '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  for (var i = 0; i < segments.length - 1; i++) {
    if (segments[i] == 'forms') {
      return FormIntakeLink(baseUrl: baseUrl, formRef: segments[i + 1]);
    }
    if (segments[i] == 'submissions') {
      return FormIntakeLink(baseUrl: baseUrl, locator: segments[i + 1]);
    }
  }
  final locator = uri.queryParameters['locator']?.trim();
  if (locator != null && locator.isNotEmpty) {
    return FormIntakeLink(baseUrl: baseUrl, locator: locator);
  }
  if (segments.isEmpty) return null;
  return FormIntakeLink(baseUrl: baseUrl, formRef: segments.last);
}

/// De uitnodigingslink die een organisator deelt (§6.2): de publieke
/// leesroute, die alleen `form_ref` draagt.
String intakeInvitationLink(String baseUrl, String formRef) =>
    '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/intake/forms/$formRef';

/// De naam van de sidecar bij [documentName] (`submission.md` →
/// `submission.md.intake.json`).
String intakeSidecarName(String documentName) => '$documentName.intake.json';

/// Leest de sidecar bij [documentPath]. `null` als hij er niet is, niet te
/// lezen is of iets anders bevat — een kapotte sidecar is geen reden het
/// document zelf te wantrouwen.
Future<FormIntakeContext?> readIntakeContext(String documentPath) async {
  try {
    final file = File(intakeSidecarName(documentPath));
    if (!file.existsSync()) return null;
    return FormIntakeContext.fromJson(jsonDecode(file.readAsStringSync()));
  } on Object {
    return null;
  }
}

/// Schrijft [context] naast [documentPath], atomair zoals elk bestand dat
/// OciDeck bijhoudt.
Future<void> writeIntakeContext(
  String documentPath,
  FormIntakeContext context,
) async {
  await writeStringAtomic(
    File(intakeSidecarName(documentPath)),
    '${jsonEncode(context.toJson())}\n',
  );
}
