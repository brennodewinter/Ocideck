import 'package:flutter/foundation.dart';

/// Een vaardigheid ("badge") van de organisatie, uit `SkillList`. De cursist
/// heeft hiervoor alleen de id nodig om zijn eigen leesmodel op te vragen —
/// de organisatie bepaalt welke badges bestaan.
@immutable
class OciServeSkill {
  const OciServeSkill({required this.id, required this.title});

  final String id;
  final String title;

  factory OciServeSkill.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('incomplete skill');
    return OciServeSkill(
      id: id,
      title: (json['title'] as String? ?? '').trim(),
    );
  }
}

/// Een gepubliceerde versie van een vaardigheid, uit `SkillVersionList`. De
/// kwalificatie van een cursist verwijst naar zo'n versie; het leesmodel voor
/// de badge hangt aan de vaardigheid zelf.
@immutable
class OciServeSkillVersion {
  const OciServeSkillVersion({required this.id});

  final String id;

  factory OciServeSkillVersion.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('incomplete skill version');
    return OciServeSkillVersion(id: id);
  }
}

/// Wat een badge-eis van de cursist vraagt — een cursus, een toets of een
/// bewijsstuk. Komt uit `SkillRequirement` in het leesmodel; `met` zegt of de
/// eis al is voldaan.
@immutable
class OciServeBadgeRequirement {
  const OciServeBadgeRequirement({
    required this.kind,
    required this.title,
    required this.met,
    this.evidenceType = '',
    this.courseId = '',
    this.blueprintId = '',
    this.minAssurance = '',
  });

  /// `course`, `evidence` of `exam`; een toekomstige soort blijft leesbaar.
  final String kind;
  final String title;
  final bool met;

  /// Slug van de gevraagde bewijssoort — alleen bij `kind == 'evidence'`.
  final String evidenceType;
  final String courseId;
  final String blueprintId;
  final String minAssurance;

  factory OciServeBadgeRequirement.fromJson(Map<String, Object?> json) =>
      OciServeBadgeRequirement(
        kind: (json['kind'] as String? ?? 'course').trim(),
        title: (json['title'] as String? ?? '').trim(),
        met: json['met'] == true,
        evidenceType: (json['evidence_type'] as String? ?? '').trim(),
        courseId: (json['course_id'] as String? ?? '').trim(),
        blueprintId: (json['blueprint_id'] as String? ?? '').trim(),
        minAssurance: (json['min_assurance'] as String? ?? '').trim(),
      );
}

/// Het leesmodel van een badge (`BadgeReadiness`, #2422): per eis of die al is
/// voldaan en of de badge klaar staat voor toekenning. De deelnemer mag zijn
/// eigen leesmodel lezen.
@immutable
class OciServeBadgeReadiness {
  const OciServeBadgeReadiness({
    required this.skillId,
    required this.skillTitle,
    required this.requirements,
    required this.ready,
    this.kwalificatiesoort = '',
    this.validityMonths,
  });

  final String skillId;
  final String skillTitle;
  final List<OciServeBadgeRequirement> requirements;
  final bool ready;
  final String kwalificatiesoort;
  final int? validityMonths;

  factory OciServeBadgeReadiness.fromJson(Map<String, Object?> json) {
    final skillId = (json['skill_id'] as String? ?? '').trim();
    if (skillId.isEmpty) {
      throw const FormatException('incomplete badge readiness');
    }
    final raw = json['requirements'];
    return OciServeBadgeReadiness(
      skillId: skillId,
      skillTitle: (json['skill_title'] as String? ?? '').trim(),
      kwalificatiesoort: (json['kwalificatiesoort'] as String? ?? '').trim(),
      validityMonths: (json['validity_months'] as num?)?.toInt(),
      requirements: List.unmodifiable([
        if (raw is List)
          for (final item in raw)
            OciServeBadgeRequirement.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
      ]),
      ready: json['ready'] == true,
    );
  }
}
