// De organisatorkant van Managed Intake in de werkmap (FORM_INTAKE.md §7.8):
// welke OciServe-inzendingen bij welk lokaal formulier horen en welke revisies
// er al binnen zijn — als gewone JSON naast het gepubliceerde formulier
// (`forms/<form-id>/intake.json`), dus overdraagbaar met de werkmap zelf.
//
// De haal-weg is bewust eenvoudig: per serverinzending wordt de nieuwste
// immutable revisie binnengehaald en met dezelfde import gelegd als een
// inzending die per bestand arriveerde. Daardoor gelden automatisch dezelfde
// regels — het ontvangen origineel wordt nooit overschreven, werken gebeurt
// op kopieën, en het register blijft de enige waarheid over status.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import '../../models/ociserve_intake.dart';
import '../../utils/atomic_file.dart';
import '../ociserve/ociserve_gateway.dart';
import 'form_import.dart';
import 'form_submission_actions.dart';
import 'form_workspace.dart';

/// Wat de werkmap weet over één serverinzending.
class IntakeSubmissionLink {
  const IntakeSubmissionLink({
    required this.sid,
    required this.revision,
    required this.state,
    required this.handled,
  });

  /// De lokale inzending (het manifest-nummer uit het pakket).
  final String sid;

  /// De hoogst binnengehaalde immutable revisie.
  final int revision;

  /// De laatst geziene servertostaand.
  final IntakeSubmissionState state;

  /// Of de organisator hem op de server als behandeld markeerde.
  final bool handled;

  IntakeSubmissionLink copyWith({
    String? sid,
    int? revision,
    IntakeSubmissionState? state,
    bool? handled,
  }) => IntakeSubmissionLink(
    sid: sid ?? this.sid,
    revision: revision ?? this.revision,
    state: state ?? this.state,
    handled: handled ?? this.handled,
  );

  Map<String, Object?> toJson() => {
    'sid': sid,
    'revision': revision,
    'state': state.wireName,
    'handled': handled,
  };

  static IntakeSubmissionLink? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json.keys.any(
      (key) => !const {'sid', 'revision', 'state', 'handled'}.contains(key),
    )) {
      return null;
    }
    final sid = json['sid'];
    final revision = json['revision'];
    final handled = json['handled'];
    if (sid is! String ||
        !isValidFormId(sid) ||
        revision is! int ||
        revision < 1 ||
        handled is! bool) {
      return null;
    }
    final IntakeSubmissionState state;
    try {
      state = IntakeSubmissionState.parse(json['state']);
    } on FormatException {
      return null;
    }
    return IntakeSubmissionLink(
      sid: sid,
      revision: revision,
      state: state,
      handled: handled,
    );
  }
}

/// De koppeling tussen een lokaal formulier en zijn publicatie op OciServe.
class IntakeOrganiserRecord {
  const IntakeOrganiserRecord({
    required this.baseUrl,
    required this.organizationId,
    required this.formId,
    required this.formRef,
    required this.activeVersion,
    this.submissions = const {},
  });

  final String baseUrl;
  final String organizationId;

  /// De server-`form_id` — intern, nooit in een uitnodigingslink.
  final String formId;

  /// De publieke `form_ref` die de uitnodigingslink draagt.
  final String formRef;

  /// De hoogst gepubliceerde versie; de volgende publicatie wordt n+1.
  final int activeVersion;

  /// Server-`submission_id` → link naar de lokale inzending.
  final Map<String, IntakeSubmissionLink> submissions;

  IntakeOrganiserRecord copyWith({
    int? activeVersion,
    Map<String, IntakeSubmissionLink>? submissions,
  }) => IntakeOrganiserRecord(
    baseUrl: baseUrl,
    organizationId: organizationId,
    formId: formId,
    formRef: formRef,
    activeVersion: activeVersion ?? this.activeVersion,
    submissions: submissions ?? this.submissions,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'base_url': baseUrl,
    'organization_id': organizationId,
    'form_id': formId,
    'form_ref': formRef,
    'active_version': activeVersion,
    'submissions': {
      for (final MapEntry(:key, :value) in submissions.entries)
        key: value.toJson(),
    },
  };

  /// Strikte lezer: een bestand dat iets anders bevat is geen record —
  /// `null`, en de werkmap blijft werken alsof er geen publicatie is.
  static IntakeOrganiserRecord? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    if (json.keys.any(
      (key) => !const {
        'v',
        'base_url',
        'organization_id',
        'form_id',
        'form_ref',
        'active_version',
        'submissions',
      }.contains(key),
    )) {
      return null;
    }
    final baseUrl = json['base_url'];
    final organizationId = json['organization_id'];
    final formId = json['form_id'];
    final formRef = json['form_ref'];
    final activeVersion = json['active_version'];
    final submissions = json['submissions'];
    if (baseUrl is! String ||
        organizationId is! String ||
        formId is! String ||
        formRef is! String ||
        activeVersion is! int ||
        activeVersion < 1 ||
        submissions is! Map ||
        formRef.trim().isEmpty) {
      return null;
    }
    final links = <String, IntakeSubmissionLink>{};
    for (final MapEntry(:key, :value) in submissions.entries) {
      if (key is! String) return null;
      final link = IntakeSubmissionLink.fromJson(value);
      if (link == null) return null;
      links[key] = link;
    }
    return IntakeOrganiserRecord(
      baseUrl: baseUrl,
      organizationId: organizationId,
      formId: formId,
      formRef: formRef,
      activeVersion: activeVersion,
      submissions: Map.unmodifiable(links),
    );
  }
}

/// Waar het record van lokaal formulier [formId] staat.
String intakeRecordPath(FormWorkspace workspace, String formId) =>
    p.join(workspace.root, 'forms', formId, 'intake.json');

/// Leest het record van [formId]; `null` als er geen is of als het niet te
/// lezen is — de Inbox werkt dan gewoon als alleen-lokaal.
Future<IntakeOrganiserRecord?> readIntakeRecord(
  FormWorkspace workspace,
  String formId,
) async {
  try {
    final file = File(intakeRecordPath(workspace, formId));
    if (!await file.exists()) return null;
    return IntakeOrganiserRecord.fromJson(
      jsonDecode(await file.readAsString()),
    );
  } on Object {
    return null;
  }
}

/// Schrijft [record] bij zijn formulier, atomair zoals elk werkmapbestand.
Future<void> writeIntakeRecord(
  FormWorkspace workspace,
  String formId,
  IntakeOrganiserRecord record,
) async {
  final file = File(intakeRecordPath(workspace, formId));
  await file.parent.create(recursive: true);
  await writeStringAtomic(file, '${jsonEncode(record.toJson())}\n');
}

/// Alle intake-records van de werkmap, lokaal-formulier-id → record.
Future<Map<String, IntakeOrganiserRecord>> readIntakeRecords(
  FormWorkspace workspace,
) async {
  final records = <String, IntakeOrganiserRecord>{};
  final formsDir = Directory(p.join(workspace.root, 'forms'));
  if (!await formsDir.exists()) return records;
  await for (final entry in formsDir.list(followLinks: false)) {
    // Geen id-filter op de mapnaam: een formulier-id is een slug uit de
    // markdown ('kook'), geen Crockford-inzendingsnummer — de strikte
    // recordlezer is de grens, niet de mapnaam.
    if (entry is! Directory) continue;
    final record = await readIntakeRecord(workspace, p.basename(entry.path));
    if (record != null) records[p.basename(entry.path)] = record;
  }
  return records;
}

/// Zoekt de serverkant van lokale inzending [sid] op in alle records:
/// `(lokaal formulier-id, record, server-submission-id, link)` of `null`.
Future<
  ({
    String localFormId,
    IntakeOrganiserRecord record,
    String submissionId,
    IntakeSubmissionLink link,
  })?
>
lookupIntakeSubmission(FormWorkspace workspace, String sid) async {
  for (final MapEntry(key: localFormId, value: record)
      in (await readIntakeRecords(workspace)).entries) {
    for (final MapEntry(key: submissionId, value: link)
        in record.submissions.entries) {
      if (link.sid == sid) {
        return (
          localFormId: localFormId,
          record: record,
          submissionId: submissionId,
          link: link,
        );
      }
    }
  }
  return null;
}

/// Wat een ophaalronde opleverde.
class IntakeFetchResult {
  const IntakeFetchResult({
    required this.fetched,
    required this.updated,
    required this.withdrawn,
    required this.failed,
  });

  /// Inzendingen die voor het eerst in de werkmap landden.
  final int fetched;

  /// Inzendingen waarvan een nieuwere revisie binnenkwam.
  final int updated;

  /// Inzendingen die als ingetrokken in het register kwamen.
  final int withdrawn;

  /// Inzendingen die niet binnengehaald konden worden.
  final int failed;
}

/// Haalt de toegewezen inzendingen van [record] binnen (§7.8): expliciet,
/// nooit op de achtergrond. Per serverinzending die nieuw of nieuwer is wordt
/// de nieuwste revisie gedownload — digest getoetst door de gateway — en met
/// de gewone import gelegd, zodat het ontvangen origineel immutable landt.
/// Een inzending die de server als ingetrokken meldt wordt zo ook in het
/// register gemarkeerd.
///
/// Gooit [OciServeException] als de lijst zelf niet te lezen is; een
/// mislukte inzending telt als `failed` en stopt de ronde niet.
Future<IntakeFetchResult> fetchIntakeSubmissions({
  required FormWorkspace workspace,
  required OciServeIntakeApi api,
  required String accessToken,
  required IntakeOrganiserRecord record,
  required DateTime now,
  Future<void> Function(IntakeOrganiserRecord updated)? recordChanged,
}) async {
  var fetched = 0;
  var updated = 0;
  var withdrawn = 0;
  var failed = 0;
  final submissions = Map<String, IntakeSubmissionLink>.of(record.submissions);

  String? cursor;
  do {
    final page = await api.intakeSubmissions(
      accessToken: accessToken,
      organizationId: record.organizationId,
      formId: record.formId,
      cursor: cursor,
    );
    if (page == null) break;
    for (final summary in page.value.items) {
      final known = submissions[summary.submissionId];
      if (known != null &&
          known.revision >= summary.revision &&
          known.state == summary.state &&
          known.handled == summary.handled) {
        continue;
      }
      try {
        final sid = await _fetchOne(
          workspace: workspace,
          api: api,
          accessToken: accessToken,
          record: record,
          summary: summary,
          known: known,
          now: now,
          onWithdrawn: () => withdrawn++,
        );
        // Een inzending zonder landbaar pakket (een nog-lege draft) krijgt
        // geen link en telt niet mee: een lege sid zou de strikte lezer het
        // hele record laten verwerpen.
        final localSid = sid ?? known?.sid;
        if (localSid == null) continue;
        if (known == null) {
          fetched++;
        } else if (summary.revision > known.revision) {
          updated++;
        }
        submissions[summary.submissionId] = IntakeSubmissionLink(
          sid: localSid,
          revision: summary.revision,
          state: summary.state,
          handled: summary.handled,
        );
        // Sla na elke inzending op: een ronde die halverwege stopt verliest
        // niet wat al binnen was.
        await recordChanged?.call(record.copyWith(submissions: submissions));
      } on Object {
        failed++;
      }
    }
    cursor = page.value.nextCursor;
  } while (cursor != null);

  return IntakeFetchResult(
    fetched: fetched,
    updated: updated,
    withdrawn: withdrawn,
    failed: failed,
  );
}

/// Haalt de nieuwste revisie van [summary] binnen en legt hem. Geeft de
/// lokale sid terug, of `null` als er nog geen pakket te landen viel (een
/// inzending zonder revisies — kan alleen bij een nog-openstaande draft,
/// die de organisatorlijst zonder revisies kan tonen).
Future<String?> _fetchOne({
  required FormWorkspace workspace,
  required OciServeIntakeApi api,
  required String accessToken,
  required IntakeOrganiserRecord record,
  required IntakeSubmissionSummary summary,
  required IntakeSubmissionLink? known,
  required DateTime now,
  required void Function() onWithdrawn,
}) async {
  final detail = await api.intakeSubmission(
    accessToken: accessToken,
    organizationId: record.organizationId,
    formId: record.formId,
    submissionId: summary.submissionId,
  );
  if (detail == null) return known?.sid;
  final value = detail.value;

  String? sid = known?.sid;
  if (value.revision > (known?.revision ?? 0) && value.revisions.isNotEmpty) {
    final latest = value.revisions.reduce(
      (a, b) => a.revision > b.revision ? a : b,
    );
    final bytes = await api.intakeRevisionContent(
      accessToken: accessToken,
      organizationId: record.organizationId,
      formId: record.formId,
      submissionId: value.submissionId,
      revision: latest.revision,
      expectedSha256: latest.sha256,
    );
    // Het pakketnummer is de lokale sid — de import legt dezelfde bytes onder
    // hetzelfde nummer als wanneer hij per bestand was binnengekomen.
    final opened = readFormPackage(bytes);
    if (opened is! FormPackageOpened) {
      throw const FormatException('revision is no form package');
    }
    sid = opened.manifest.submissionId;
    switch (await importFormPackage(workspace, bytes, now: now)) {
      case FormImported():
      case FormImportDuplicate():
        break; // duplicate = dezelfde revisie nogmaals; de link staat al goed
      case FormImportOutcome():
        throw const FormatException('revision refused by import');
    }
  }
  if (value.state == IntakeSubmissionState.withdrawn &&
      sid != null &&
      known?.state != IntakeSubmissionState.withdrawn) {
    await setSubmissionWithdrawal(workspace, sid, formDay(now));
    onWithdrawn();
  }
  return sid;
}
