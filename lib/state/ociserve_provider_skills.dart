part of 'ociserve_provider.dart';

/// Vaardigheden en het badge-leesmodel (#2422): dunne doorgeeflaag naar de
/// gateway plus de vertaling van `skill_version_id` (wat een kwalificatie
/// oplevert) naar `skill_id` (waar het leesmodel aan hangt).
mixin _OciServeSkillMethods on OciServeNotifierBase {
  /// Het leesmodel van één badge voor deze cursist.
  Future<OciServeBadgeReadiness> badgeReadiness({
    required String organizationId,
    required String participantId,
    required String skillId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).badgeReadiness(
      accessToken: access,
      organizationId: organizationId,
      participantId: participantId,
      skillId: skillId,
    );
  }

  /// Haalt per kwalificatie het leesmodel van de bijbehorende badge op,
  /// teruggegeven op `skill_version_id`. De vertaling loopt via de
  /// vaardighedenlijst en haar versies — de enige contractvaste weg van
  /// versie naar vaardigheid. Een vaardigheid of versie die niet leest,
  /// levert simpelweg geen eisen op; de badgekaart toont dan alleen de
  /// kwalificatie zelf.
  Future<Map<String, OciServeBadgeReadiness>> badgeReadinessByVersion({
    required String organizationId,
    required String participantId,
    required Set<String> skillVersionIds,
  }) async {
    _requireMembership(organizationId);
    if (skillVersionIds.isEmpty) return const {};
    final access = await _accessToken();
    final gateway = _gatewayFactory(state.settings);
    final skills = await gateway.organizationSkills(
      accessToken: access,
      organizationId: organizationId,
    );
    final versionToSkill = <String, String>{};
    await Future.wait([
      for (final skill in skills)
        () async {
          try {
            for (final version in await gateway.skillVersions(
              accessToken: access,
              organizationId: organizationId,
              skillId: skill.id,
            )) {
              versionToSkill[version.id] = skill.id;
            }
            // Eén onleesbare versielijst mag de rest niet meenemen.
          } catch (error, stack) {
            logError(
              'OciServe: vaardigheidsversies lezen',
              error.runtimeType,
              stack,
            );
          }
        }(),
    ]);
    final readiness = <String, OciServeBadgeReadiness>{};
    await Future.wait([
      for (final versionId in skillVersionIds)
        () async {
          final skillId = versionToSkill[versionId];
          if (skillId == null) return;
          try {
            readiness[versionId] = await gateway.badgeReadiness(
              accessToken: access,
              organizationId: organizationId,
              participantId: participantId,
              skillId: skillId,
            );
          } catch (error, stack) {
            logError(
              'OciServe: badge-leesmodel lezen',
              error.runtimeType,
              stack,
            );
          }
        }(),
    ]);
    return readiness;
  }
}
