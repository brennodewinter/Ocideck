part of 'ociserve_gateway.dart';

/// Het vaardigheidsdeel van [OciServeApi] (#2422): de badges van de
/// organisatie, hun versies en het leesmodel dat per badge zegt wat de
/// cursist nog nodig heeft. De deelnemersrol mag zijn eigen leesmodel lezen
/// en de vaardighedenlijst gebruiken om een `skill_version_id` uit zijn
/// kwalificatie naar de bijbehorende `skill_id` te vertalen.
abstract class OciServeSkillsApi {
  /// De vaardigheden van de organisatie.
  Future<List<OciServeSkill>> organizationSkills({
    required String accessToken,
    required String organizationId,
  });

  /// De gepubliceerde versies van een vaardigheid.
  Future<List<OciServeSkillVersion>> skillVersions({
    required String accessToken,
    required String organizationId,
    required String skillId,
  });

  /// Het leesmodel van een badge voor deze deelnemer: per eis of die al is
  /// voldaan en of de badge klaar staat.
  Future<OciServeBadgeReadiness> badgeReadiness({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String skillId,
  });
}

mixin _OciServeSkills on OciServeGatewayBase {
  @override
  Future<List<OciServeSkill>> organizationSkills({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'skills']),
      accessToken: accessToken,
    );
    try {
      final raw = _jsonObject(response)['skills'];
      if (raw is! List) throw const FormatException('skills');
      return List.unmodifiable([
        for (final item in raw)
          OciServeSkill.fromJson(Map<String, Object?>.from(item as Map)),
      ]);
    } catch (error, stack) {
      logError('OciServe: vaardigheden lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<List<OciServeSkillVersion>> skillVersions({
    required String accessToken,
    required String organizationId,
    required String skillId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'skills',
        skillId,
        'versions',
      ]),
      accessToken: accessToken,
    );
    try {
      final raw = _jsonObject(response)['versions'];
      if (raw is! List) throw const FormatException('skill versions');
      return List.unmodifiable([
        for (final item in raw)
          OciServeSkillVersion.fromJson(Map<String, Object?>.from(item as Map)),
      ]);
    } catch (error, stack) {
      logError('OciServe: vaardigheidsversies lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeBadgeReadiness> badgeReadiness({
    required String accessToken,
    required String organizationId,
    required String participantId,
    required String skillId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'skills',
        skillId,
        'badge-readiness',
      ]),
      accessToken: accessToken,
    );
    try {
      return OciServeBadgeReadiness.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: badge-leesmodel lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }
}
