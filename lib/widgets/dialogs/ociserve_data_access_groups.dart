part of 'ociserve_data_access.dart';

class _DataGroup {
  const _DataGroup(this.kind, this.categories);

  final OciServePrivacyGroup kind;
  final List<_FilteredCategory> categories;

  int get recordCount =>
      categories.fold(0, (total, category) => total + category.records.length);
}

List<_DataGroup> _groupsFor(List<_FilteredCategory> categories) {
  final grouped = <OciServePrivacyGroup, List<_FilteredCategory>>{};
  for (final category in categories) {
    grouped
        .putIfAbsent(_groupForCategory(category.sourceKey), () => [])
        .add(category);
  }
  return [
    for (final kind in OciServePrivacyGroup.values)
      if (grouped[kind] case final categories?) _DataGroup(kind, categories),
  ];
}

OciServePrivacyGroup _groupForCategory(String key) =>
    ociservePrivacyCategories[key]?.group ?? OciServePrivacyGroup.other;

class _DataGroupCard extends StatelessWidget {
  const _DataGroupCard({
    required this.group,
    required this.searching,
    required this.omissionReasons,
  });

  final _DataGroup group;
  final bool searching;
  final Map<String, String> omissionReasons;

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
              omissionReasons: omissionReasons,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

String _groupLabel(
  BuildContext context,
  OciServePrivacyGroup kind,
) => switch (kind) {
  OciServePrivacyGroup.profile => context.l10n.d('Profiel en organisatie'),
  OciServePrivacyGroup.learning => context.l10n.d('Cursussen en deelname'),
  OciServePrivacyGroup.assessment => context.l10n.d('Toetsen en antwoorden'),
  OciServePrivacyGroup.results => context.l10n.d('Resultaten en bewijsstukken'),
  OciServePrivacyGroup.privacy => context.l10n.d('Privacy en toegang'),
  OciServePrivacyGroup.security => context.l10n.d('Aanmelden en beveiliging'),
  OciServePrivacyGroup.other => context.l10n.d('Overige gegevens'),
};

String _groupDescription(
  BuildContext context,
  OciServePrivacyGroup kind,
) => switch (kind) {
  OciServePrivacyGroup.profile => _categoryDescription(context, 'participant'),
  OciServePrivacyGroup.learning => _categoryDescription(context, 'enrollments'),
  OciServePrivacyGroup.assessment => _categoryDescription(context, 'attempts'),
  OciServePrivacyGroup.results => _categoryDescription(
    context,
    'qualifications',
  ),
  OciServePrivacyGroup.privacy => _categoryDescription(
    context,
    'privacy_requests',
  ),
  OciServePrivacyGroup.security => _categoryDescription(
    context,
    'identity_operations',
  ),
  OciServePrivacyGroup.other => _categoryDescription(context, ''),
};

IconData _groupIcon(OciServePrivacyGroup kind) => switch (kind) {
  OciServePrivacyGroup.profile => Icons.person_outline,
  OciServePrivacyGroup.learning => Icons.school_outlined,
  OciServePrivacyGroup.assessment => Icons.quiz_outlined,
  OciServePrivacyGroup.results => Icons.workspace_premium_outlined,
  OciServePrivacyGroup.privacy => Icons.policy_outlined,
  OciServePrivacyGroup.security => Icons.security_outlined,
  OciServePrivacyGroup.other => Icons.more_horiz,
};
