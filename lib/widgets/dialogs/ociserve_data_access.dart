import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_models.dart';

class OciServeDataAccess extends StatelessWidget {
  const OciServeDataAccess({
    super.key,
    required this.data,
    required this.organizationName,
  });

  final OciServePrivacyData data;
  final String organizationName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final date = MaterialLocalizations.of(
      context,
    ).formatFullDate(data.generatedAt.toLocal());
    return CustomScrollView(
      key: const Key('ociserve-data-access'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
          sliver: SliverList.list(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.policy_outlined,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.d('Uw geregistreerde gegevens'),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n
                                .d(
                                  'Dit overzicht is op {datum} rechtstreeks opgehaald bij eLearning en wordt niet door OciDeck bewaard.',
                                )
                                .replaceAll('{datum}', date),
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n
                                .d(
                                  'Het bevat alle categorieën die de server voor deze organisatie heeft aangeleverd. Voor informatie over doelen, ontvangers, herkomst, bewaartermijnen of uw andere privacyrechten kunt u terecht bij {organisatie}.',
                                )
                                .replaceAll(
                                  '{organisatie}',
                                  organizationName.isEmpty
                                      ? l10n.d('uw organisatie')
                                      : organizationName,
                                ),
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final entry in data.data.entries) ...[
                _DataCategory(sourceKey: entry.key, value: entry.value),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DataCategory extends StatefulWidget {
  const _DataCategory({required this.sourceKey, required this.value});

  final String sourceKey;
  final Object? value;

  @override
  State<_DataCategory> createState() => _DataCategoryState();
}

class _DataCategoryState extends State<_DataCategory> {
  static const _pageSize = 50;
  bool _expanded = false;
  int _visible = _pageSize;

  List<Object?> get _records => switch (widget.value) {
    List<Object?> list => list,
    Map<Object?, Object?> map => [map],
    _ => [widget.value],
  };

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final shown = _visible.clamp(0, records.length);
    final l10n = context.l10n;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: Key('data-category-${widget.sourceKey}'),
        onExpansionChanged: (value) => setState(() => _expanded = value),
        title: Text(_label(context, widget.sourceKey)),
        subtitle: Text(
          records.isEmpty
              ? l10n.d('Geen gegevens geregistreerd')
              : l10n
                    .d('{aantal} registraties')
                    .replaceAll('{aantal}', '${records.length}'),
        ),
        children: _expanded
            ? [
                if (records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.d('Geen gegevens geregistreerd')),
                    ),
                  )
                else
                  for (var index = 0; index < shown; index++)
                    _DataRecord(index: index, value: records[index]),
                if (shown < records.length)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _visible += _pageSize),
                        icon: const Icon(Icons.expand_more),
                        label: Text(
                          l10n
                              .d('Meer tonen ({aantal} resterend)')
                              .replaceAll(
                                '{aantal}',
                                '${records.length - shown}',
                              ),
                        ),
                      ),
                    ),
                  ),
              ]
            : const [],
      ),
    );
  }
}

class _DataRecord extends StatelessWidget {
  const _DataRecord({required this.index, required this.value});

  final int index;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final fields = value is Map
        ? Map<Object?, Object?>.from(value! as Map)
        : <Object?, Object?>{'value': value};
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (index > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '#${index + 1}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              for (final field in fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fieldLabel(context, '${field.key}'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        _display(context, '${field.key}', field.value),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _label(BuildContext context, String value) {
  final known = switch (value) {
    'participant_data_access_history' => context.l10n.d(
      'Inzage en wijzigingen',
    ),
    'participant_data_access_history_metadata' => context.l10n.d(
      'Beschikbaarheid van het inzagespoor',
    ),
    'available_from' => context.l10n.d('Beschikbaar vanaf'),
    'earlier_history' => context.l10n.d('Historie vóór deze datum'),
    'time' => context.l10n.d('Tijdstip'),
    'retain_until' => context.l10n.d('Bewaard tot'),
    'operation' => context.l10n.d('Handeling'),
    'data_category' => context.l10n.d('Gegevensonderdeel'),
    'purpose' => context.l10n.d('Doel'),
    'actor_type' => context.l10n.d('Handelde als'),
    'actor_role' => context.l10n.d('Organisatorische rol'),
    _ => null,
  };
  if (known != null) return known;
  final text = value.replaceAll('_', ' ').trim();
  return text.isEmpty ? value : '${text[0].toUpperCase()}${text.substring(1)}';
}

String _fieldLabel(BuildContext context, String value) => switch (value) {
  'available_from' ||
  'earlier_history' ||
  'time' ||
  'retain_until' ||
  'operation' ||
  'data_category' ||
  'purpose' ||
  'actor_type' ||
  'actor_role' => _label(context, value),
  _ => '${_label(context, value)} ($value)',
};

String _display(BuildContext context, String key, Object? value) {
  if (value == null) return '—';
  if ((key == 'time' || key == 'available_from' || key == 'retain_until') &&
      value is String) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed != null) {
      final material = MaterialLocalizations.of(context);
      return '${material.formatFullDate(parsed)} '
          '${material.formatTimeOfDay(TimeOfDay.fromDateTime(parsed))}';
    }
  }
  final known = switch ('$key:$value') {
    'operation:viewed' => context.l10n.d('Bekeken'),
    'operation:edited' => context.l10n.d('Gewijzigd'),
    'actor_type:self' => context.l10n.d('Uzelf'),
    'actor_type:staff' => context.l10n.d('Medewerker'),
    'actor_type:system' => context.l10n.d('Systeem'),
    'actor_role:unknown' => context.l10n.d('Onbekend'),
    'actor_role:participant' => context.l10n.d('Cursist'),
    'actor_role:instructor' => context.l10n.d('Docent'),
    'actor_role:author' => context.l10n.d('Auteur'),
    'actor_role:assessor' => context.l10n.d('Beoordelaar'),
    'actor_role:organization_admin' => context.l10n.d('Organisatiebeheerder'),
    'actor_role:owner' => context.l10n.d('Eigenaar'),
    'earlier_history:not_available' => context.l10n.d('Niet beschikbaar'),
    'purpose:data_subject_access' => context.l10n.d(
      'Uitoefening van privacyrechten',
    ),
    'purpose:assessment_and_certification' => context.l10n.d(
      'Beoordeling en certificering',
    ),
    'purpose:learning_delivery' => context.l10n.d(
      'Uitvoering van het leertraject',
    ),
    'purpose:learner_administration' => context.l10n.d(
      'Cursistenadministratie',
    ),
    'data_category:profile' => context.l10n.d('Cursistprofiel'),
    'data_category:membership' => context.l10n.d('Lidmaatschap'),
    'data_category:privacy_data' => context.l10n.d('Privacy-inzage'),
    'data_category:learning_statistics' => context.l10n.d('Leerstatistieken'),
    'data_category:enrollment' => context.l10n.d('Inschrijving'),
    'data_category:attendance' => context.l10n.d('Aanwezigheid'),
    'data_category:attempt' => context.l10n.d('Toetspoging'),
    'data_category:attempt_score' => context.l10n.d('Beoordeling'),
    'data_category:answer' => context.l10n.d('Antwoord'),
    'data_category:evidence' => context.l10n.d('Bewijsstuk'),
    'data_category:qualification' => context.l10n.d('Kwalificatie'),
    'data_category:participation' => context.l10n.d('Deelname'),
    'data_category:pe_award' => context.l10n.d('PE-punten'),
    'data_category:certificate' => context.l10n.d('Certificaat'),
    'data_category:privacy' => context.l10n.d('Privacyverzoek'),
    _ => null,
  };
  if (known != null) return known;
  return switch (value) {
    Map() || List() => const JsonEncoder.withIndent('  ').convert(value),
    _ => '$value',
  };
}
