import 'package:flutter/foundation.dart';

import '../../models/ociserve_badge_readiness.dart';
import '../../models/ociserve_evidence.dart';
import '../../models/ociserve_evidence_item.dart';
import '../../state/ociserve_provider.dart';
import '../../utils/log.dart';

/// Alles wat het bewijsscherm van de server nodig heeft, in één keer geladen.
///
/// Uploads en badges zijn het hart van het scherm: lukt dat laden niet, dan
/// is er niets te tonen en volgt de fout. De bewijssoorten en bewijsstukken
/// voegen alleen de beoordelingsstatus toe; ontbreken die, dan blijft het
/// scherm bruikbaar en zegt een upload eerlijk dat hij nog niet is ingediend.
/// Ze komen mee in dezelfde laadronde, zodat een upload nooit eerst als "nog
/// niet ingediend" verschijnt en pas daarna de echte status krijgt.
@immutable
class OciServeEvidenceData {
  const OciServeEvidenceData({
    this.uploads = const [],
    this.qualifications = const [],
    this.types = const [],
    this.items = const [],
    this.readiness = const {},
  });

  final List<EvidenceUpload> uploads;
  final List<OciServeQualification> qualifications;
  final List<OciServeEvidenceType> types;
  final List<OciServeEvidenceItem> items;

  /// Het leesmodel per badge, op de `skill_version_id` van de kwalificatie.
  /// Leeg als de server het leesmodel niet geeft — het scherm toont dan alleen
  /// de badges zelf.
  final Map<String, OciServeBadgeReadiness> readiness;

  static Future<OciServeEvidenceData> load(
    OciServeNotifier notifier, {
    required String organizationId,
    required String participantId,
  }) async {
    final results = await Future.wait<Object>([
      notifier.listEvidence(
        organizationId: organizationId,
        participantId: participantId,
      ),
      notifier.listQualifications(
        organizationId: organizationId,
        participantId: participantId,
      ),
    ]);
    final qualifications = results[1] as List<OciServeQualification>;
    var types = const <OciServeEvidenceType>[];
    var items = const <OciServeEvidenceItem>[];
    var readiness = const <String, OciServeBadgeReadiness>{};
    try {
      types = await notifier.evidenceTypes(organizationId);
      items = await notifier.evidenceItems(
        organizationId: organizationId,
        participantId: participantId,
      );
    } catch (error, stack) {
      logError('OciServe: bewijsstukken laden', error.runtimeType, stack);
      types = const [];
      items = const [];
    }
    try {
      readiness = await notifier.badgeReadinessByVersion(
        organizationId: organizationId,
        participantId: participantId,
        skillVersionIds: {
          for (final qual in qualifications) qual.skillVersionId,
        },
      );
    } catch (error, stack) {
      // Het leesmodel is versiering op de badgekaart; zonder server ervoor
      // blijft het scherm volledig bruikbaar.
      logError('OciServe: badge-leesmodellen laden', error.runtimeType, stack);
    }
    return OciServeEvidenceData(
      uploads: results[0] as List<EvidenceUpload>,
      qualifications: qualifications,
      types: types,
      items: items,
      readiness: readiness,
    );
  }
}
