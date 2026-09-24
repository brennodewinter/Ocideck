part of 'ociserve_data_access.dart';

enum _DataGroupKind {
  profile,
  learning,
  assessment,
  results,
  privacy,
  security,
  other,
}

class _DataGroup {
  const _DataGroup(this.kind, this.categories);

  final _DataGroupKind kind;
  final List<_FilteredCategory> categories;

  int get recordCount =>
      categories.fold(0, (total, category) => total + category.records.length);
}

List<_DataGroup> _groupsFor(List<_FilteredCategory> categories) {
  final grouped = <_DataGroupKind, List<_FilteredCategory>>{};
  for (final category in categories) {
    grouped
        .putIfAbsent(_groupForCategory(category.sourceKey), () => [])
        .add(category);
  }
  return [
    for (final kind in _DataGroupKind.values)
      if (grouped[kind] case final categories?) _DataGroup(kind, categories),
  ];
}

_DataGroupKind _groupForCategory(String key) => switch (key) {
  'participant' || 'accounts' || 'memberships' => _DataGroupKind.profile,
  'enrollments' ||
  'lesson_progress' ||
  'playback_sessions' ||
  'participations' ||
  'session_bookings' ||
  'requirement_waivers' ||
  'voucher_redemptions' => _DataGroupKind.learning,
  'attempts' || 'attempt_items' || 'answers' => _DataGroupKind.assessment,
  'evidence_uploads' ||
  'qualifications' ||
  'qualification_events' ||
  'pe_awards' ||
  'pe_award_events' ||
  'certificates' => _DataGroupKind.results,
  'privacy_requests' ||
  'access_audit_events' ||
  'participant_data_access_history' ||
  'participant_data_access_history_metadata' ||
  'retention_policies' ||
  'deletion_ledger' => _DataGroupKind.privacy,
  'identity_operations' ||
  'installation_requests' ||
  'claim_attempts' ||
  'api_idempotency_requests' ||
  'installation_audit_events' ||
  'installation_ownership' ||
  'access_policy_changes' ||
  'invitations' ||
  'email_messages' ||
  'web_sessions' => _DataGroupKind.security,
  _ => _DataGroupKind.other,
};

class _DataGroupCard extends StatelessWidget {
  const _DataGroupCard({required this.group, required this.searching});

  final _DataGroup group;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final categoryCount = group.categories.length == 1
        ? l10n.d('1 onderdeel')
        : l10n
              .d('{aantal} onderdelen')
              .replaceAll('{aantal}', '${group.categories.length}');
    final recordCount = group.recordCount == 1
        ? l10n.d('1 registratie')
        : l10n
              .d('{aantal} registraties')
              .replaceAll('{aantal}', '${group.recordCount}');
    return Card(
      key: Key('data-group-${group.kind.name}'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: ValueKey(searching),
        initiallyExpanded: searching,
        leading: Icon(_groupIcon(group.kind)),
        title: Text(_groupLabel(context, group.kind)),
        subtitle: Text('$categoryCount · $recordCount'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(_groupDescription(context, group.kind)),
            ),
          ),
          for (final category in group.categories) ...[
            _DataCategory(
              sourceKey: category.sourceKey,
              records: category.records,
              searching: searching,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

String _groupLabel(BuildContext context, _DataGroupKind kind) => switch (kind) {
  _DataGroupKind.profile => context.l10n.d('Profiel en organisatie'),
  _DataGroupKind.learning => context.l10n.d('Cursussen en deelname'),
  _DataGroupKind.assessment => context.l10n.d('Toetsen en antwoorden'),
  _DataGroupKind.results => context.l10n.d('Resultaten en bewijsstukken'),
  _DataGroupKind.privacy => context.l10n.d('Privacy en toegang'),
  _DataGroupKind.security => context.l10n.d('Aanmelden en beveiliging'),
  _DataGroupKind.other => context.l10n.d('Overige gegevens'),
};

String _groupDescription(BuildContext context, _DataGroupKind kind) =>
    switch (kind) {
      _DataGroupKind.profile => _categoryDescription(context, 'participant'),
      _DataGroupKind.learning => _categoryDescription(context, 'enrollments'),
      _DataGroupKind.assessment => _categoryDescription(context, 'attempts'),
      _DataGroupKind.results => _categoryDescription(context, 'qualifications'),
      _DataGroupKind.privacy => _categoryDescription(
        context,
        'privacy_requests',
      ),
      _DataGroupKind.security => _categoryDescription(
        context,
        'identity_operations',
      ),
      _DataGroupKind.other => _categoryDescription(context, ''),
    };

IconData _groupIcon(_DataGroupKind kind) => switch (kind) {
  _DataGroupKind.profile => Icons.person_outline,
  _DataGroupKind.learning => Icons.school_outlined,
  _DataGroupKind.assessment => Icons.quiz_outlined,
  _DataGroupKind.results => Icons.workspace_premium_outlined,
  _DataGroupKind.privacy => Icons.policy_outlined,
  _DataGroupKind.security => Icons.security_outlined,
  _DataGroupKind.other => Icons.more_horiz,
};
