import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_models.dart';
import '../../models/ociserve_privacy_dictionary.dart';

part 'ociserve_data_access_groups.dart';
part 'ociserve_data_access_search.dart';

class OciServeDataAccess extends StatefulWidget {
  const OciServeDataAccess({
    super.key,
    required this.data,
    required this.organizationName,
  });

  final OciServePrivacyData data;
  final String organizationName;

  @override
  State<OciServeDataAccess> createState() => _OciServeDataAccessState();
}

class _OciServeDataAccessState extends State<OciServeDataAccess> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _showEmptyCategories = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final date = MaterialLocalizations.of(
      context,
    ).formatFullDate(widget.data.generatedAt.toLocal());
    final categories = _filteredCategories(context);
    final groups = _groupsFor(categories);
    final omissionReasons = {
      for (final omission in widget.data.omissions)
        omission.path: omission.reason,
    };
    final emptyCategoryCount = widget.data.data.values
        .where((value) => _recordsFor(value).isEmpty)
        .length;
    return CustomScrollView(
      key: const Key('ociserve-data-access'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
          sliver: SliverList.list(
            children: [
              _buildIntroduction(context, date),
              if (widget.data.omissions.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildOmissionNotice(context),
              ],
              const SizedBox(height: 14),
              Card(
                margin: EdgeInsets.zero,
                child: ExpansionTile(
                  leading: const Icon(Icons.help_outline),
                  title: Text(l10n.d('Begrippen uitgelegd')),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.d(
                        'Een categorie groepeert gegevens over hetzelfde onderwerp. Een registratie is één bewaard gegeven of één gebeurtenis.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.d(
                        'Een ID is een uniek technisch nummer waarmee eLearning gegevens aan elkaar koppelt. Het is geen beoordeling of status.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.d(
                        'Datums en tijden worden in uw lokale tijd getoond. Technische namen blijven zichtbaar wanneer de server een nog onbekend veld aanlevert.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.d(
                        'Bewijsstukken zijn bestanden die u aanlevert voor een badge. Het overzicht toont de bestandsnaam, controlecode, status en wie het heeft beoordeeld. De bestanden zelf staan niet in dit overzicht; een beoordelaar kan ze wel inzien.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.d(
                        'Het technische toegangslogboek laat zien wie uw gegevens heeft bekeken of gewijzigd, wanneer, en met welk doel.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.d(
                        'Vraagt u verwijdering aan, dan verdwijnen uw bewijsstukken en de bijbehorende beoordelingen. Bewaarregels in het verwijderingsregister laten zien of er nog een restant achterblijft voor een lopende bewaarplicht.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('privacy-data-search'),
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  labelText: l10n.d('Zoeken in uw gegevens'),
                  hintText: l10n.d(
                    'Zoek bijvoorbeeld op cursus, datum of status',
                  ),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('privacy-data-search-clear'),
                          tooltip: l10n.d('Zoekopdracht wissen'),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_query.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  categories.length == 1
                      ? l10n.d('1 categorie gevonden')
                      : l10n
                            .d('{aantal} categorieën gevonden')
                            .replaceAll('{aantal}', '${categories.length}'),
                  key: const Key('privacy-data-search-count'),
                  style: theme.textTheme.bodySmall,
                ),
              ] else if (emptyCategoryCount > 0) ...[
                const SizedBox(height: 8),
                _buildEmptyCategoriesToggle(context, emptyCategoryCount),
              ],
              const SizedBox(height: 18),
              if (categories.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(l10n.d('Geen gegevens gevonden')),
                      const SizedBox(height: 4),
                      Text(
                        l10n.d('Probeer een andere zoekterm.'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              else
                for (final group in groups) ...[
                  _DataGroupCard(
                    group: group,
                    searching: _query.isNotEmpty,
                    omissionReasons: omissionReasons,
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCategoriesToggle(BuildContext context, int count) {
    final l10n = context.l10n;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('privacy-data-empty-toggle'),
        onPressed: () =>
            setState(() => _showEmptyCategories = !_showEmptyCategories),
        icon: Icon(
          _showEmptyCategories
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
        ),
        label: Text(
          _showEmptyCategories
              ? l10n.d('Lege onderdelen verbergen')
              : l10n
                    .d('{aantal} lege onderdelen tonen')
                    .replaceAll('{aantal}', '$count'),
        ),
      ),
    );
  }

  Widget _buildIntroduction(BuildContext context, String date) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final organization = widget.organizationName.isEmpty
        ? l10n.d('uw organisatie')
        : widget.organizationName;
    return Container(
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
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n
                      .d(
                        'Het bevat alle categorieën die de server voor deze organisatie heeft aangeleverd. Voor informatie over doelen, ontvangers, herkomst, bewaartermijnen of uw andere privacyrechten kunt u terecht bij {organisatie}.',
                      )
                      .replaceAll('{organisatie}', organization),
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOmissionNotice(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(Icons.visibility_off_outlined),
      title: Text(context.l10n.d('Sommige waarden zijn niet getoond')),
      subtitle: Text(
        context.l10n.d(
          'OciServe schermt een waarde af wanneer deze ook over iemand anders gaat. Bij het betreffende veld staat waarom de waarde ontbreekt.',
        ),
      ),
    ),
  );

  List<_FilteredCategory> _filteredCategories(BuildContext context) {
    final query = _query.toLowerCase();
    return widget.data.data.entries
        .expand((entry) {
          final records = _recordsFor(entry.value);
          if (query.isEmpty) {
            return !_showEmptyCategories && records.isEmpty
                ? const <_FilteredCategory>[]
                : [_FilteredCategory(entry.key, records)];
          }
          final categoryText = [
            entry.key,
            _categoryLabel(context, entry.key),
            _categoryDescription(context, entry.key),
          ].join(' ').toLowerCase();
          if (categoryText.contains(query)) {
            return [_FilteredCategory(entry.key, records)];
          }
          final matching = records
              .where(
                (record) => _searchText(context, record.value).contains(query),
              )
              .toList(growable: false);
          return matching.isEmpty
              ? const <_FilteredCategory>[]
              : [_FilteredCategory(entry.key, matching)];
        })
        .toList(growable: false);
  }
}

class _FilteredCategory {
  const _FilteredCategory(this.sourceKey, this.records);

  final String sourceKey;
  final List<_IndexedRecord> records;
}

class _DataCategory extends StatefulWidget {
  const _DataCategory({
    required this.sourceKey,
    required this.records,
    required this.searching,
    required this.omissionReasons,
  });

  final String sourceKey;
  final List<_IndexedRecord> records;
  final bool searching;
  final Map<String, String> omissionReasons;

  @override
  State<_DataCategory> createState() => _DataCategoryState();
}

class _DataCategoryState extends State<_DataCategory> {
  static const _pageSize = 50;
  bool _expanded = false;
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    _expanded = widget.searching;
  }

  @override
  void didUpdateWidget(covariant _DataCategory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searching != widget.searching) {
      _expanded = widget.searching;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _visible.clamp(0, widget.records.length);
    final l10n = context.l10n;
    return Card(
      key: Key('data-category-${widget.sourceKey}'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: ValueKey(widget.searching),
        initiallyExpanded: _expanded,
        onExpansionChanged: (value) => setState(() => _expanded = value),
        title: Text(_categoryLabel(context, widget.sourceKey)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_categoryDescription(context, widget.sourceKey)),
            const SizedBox(height: 2),
            Text(
              widget.records.isEmpty
                  ? l10n.d('Geen gegevens geregistreerd')
                  : widget.records.length == 1
                  ? l10n.d('1 registratie')
                  : l10n
                        .d('{aantal} registraties')
                        .replaceAll('{aantal}', '${widget.records.length}'),
            ),
          ],
        ),
        children: _expanded
            ? [
                if (widget.records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.d('Geen gegevens geregistreerd')),
                    ),
                  )
                else
                  for (var index = 0; index < shown; index++)
                    _DataRecord(
                      categoryKey: widget.sourceKey,
                      record: widget.records[index],
                      omissionReasons: widget.omissionReasons,
                    ),
                if (shown < widget.records.length)
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
                                '${widget.records.length - shown}',
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
  const _DataRecord({
    required this.categoryKey,
    required this.record,
    required this.omissionReasons,
  });

  final String categoryKey;
  final _IndexedRecord record;
  final Map<String, String> omissionReasons;

  @override
  Widget build(BuildContext context) {
    final fields = record.value is Map
        ? Map<Object?, Object?>.from(record.value! as Map)
        : <Object?, Object?>{'value': record.value};
    final recordPath =
        '/data/${_jsonPointerSegment(categoryKey)}/${record.sourceIndex}';
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
              if (record.sourceIndex > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    context.l10n
                        .d('Registratie {nummer}')
                        .replaceAll('{nummer}', '${record.sourceIndex + 1}'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              for (final field in fields.entries)
                _DataField(
                  sourceKey: '${field.key}',
                  value: field.value,
                  path: '$recordPath/${_jsonPointerSegment(field.key)}',
                  omissionReasons: omissionReasons,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataField extends StatelessWidget {
  const _DataField({
    required this.sourceKey,
    required this.value,
    required this.path,
    required this.omissionReasons,
  });

  final String sourceKey;
  final Object? value;
  final String path;
  final Map<String, String> omissionReasons;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _fieldLabel(context, sourceKey),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        if (_knownLabel(context, sourceKey) == null)
          Text(
            context.l10n
                .d('Technische naam: {naam}')
                .replaceAll('{naam}', sourceKey),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 3),
        _ReadableValue(
          sourceKey: sourceKey,
          value: value,
          path: path,
          omissionReasons: omissionReasons,
        ),
      ],
    ),
  );
}

class _ReadableValue extends StatelessWidget {
  const _ReadableValue({
    required this.sourceKey,
    required this.value,
    required this.path,
    required this.omissionReasons,
  });

  final String sourceKey;
  final Object? value;
  final String path;
  final Map<String, String> omissionReasons;

  @override
  Widget build(BuildContext context) => switch (value) {
    Map() => Padding(
      padding: const EdgeInsets.only(left: 12, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in Map<Object?, Object?>.from(value! as Map).entries)
            _DataField(
              sourceKey: '${entry.key}',
              value: entry.value,
              path: '$path/${_jsonPointerSegment(entry.key)}',
              omissionReasons: omissionReasons,
            ),
        ],
      ),
    ),
    List() => Padding(
      padding: const EdgeInsets.only(left: 12, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < (value! as List).length; index++) ...[
            Text(
              context.l10n
                  .d('Onderdeel {nummer}')
                  .replaceAll('{nummer}', '${index + 1}'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 2),
            _ReadableValue(
              sourceKey: sourceKey,
              value: (value! as List)[index],
              path: '$path/$index',
              omissionReasons: omissionReasons,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
    _ => SelectableText(
      _display(
        context,
        sourceKey,
        value,
        omissionReason: omissionReasons[path],
      ),
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  };
}

String _categoryLabel(BuildContext context, String value) {
  final definition = ociservePrivacyCategories[value];
  return definition == null
      ? _fallbackLabel(value)
      : context.l10n.d(definition.dutchLabel);
}

String _label(BuildContext context, String value) =>
    _knownLabel(context, value) ?? _fallbackLabel(value);

String? _knownLabel(BuildContext context, String value) =>
    _knownLearningLabel(context, value) ??
    _knownAdministrativeLabel(context, value);

String? _knownLearningLabel(
  BuildContext context,
  String value,
) => switch (value) {
  'available_from' => context.l10n.d('Beschikbaar vanaf'),
  'earlier_history' => context.l10n.d('Historie vóór deze datum'),
  'time' => context.l10n.d('Tijdstip'),
  'retain_until' => context.l10n.d('Bewaard tot'),
  'operation' => context.l10n.d('Handeling'),
  'data_category' => context.l10n.d('Gegevensonderdeel'),
  'purpose' => context.l10n.d('Doel'),
  'actor_type' => context.l10n.d('Handelde als'),
  'actor_role' => context.l10n.d('Organisatorische rol'),
  'id' => context.l10n.d('Uniek nummer (ID)'),
  'account_id' => context.l10n.d('Accountnummer'),
  'organization_id' => context.l10n.d('Organisatienummer'),
  'oidc_subject' => context.l10n.d('Identificatienummer bij aanmeldprovider'),
  'oidc_issuer' => context.l10n.d('Aanmeldprovider'),
  'avatar_blob_hash' => context.l10n.d('Controlecode van profielfoto'),
  'display_name' => context.l10n.d('Naam'),
  'email' => context.l10n.d('E-mailadres'),
  'status' => context.l10n.d('Status'),
  'created_at' => context.l10n.d('Aangemaakt op'),
  'updated_at' => context.l10n.d('Laatst gewijzigd op'),
  'completed_at' => context.l10n.d('Afgerond op'),
  'started_at' => context.l10n.d('Gestart op'),
  'ended_at' => context.l10n.d('Beëindigd op'),
  'expires_at' => context.l10n.d('Verloopt op'),
  'issued_at' => context.l10n.d('Uitgegeven op'),
  'revoked_at' => context.l10n.d('Ingetrokken op'),
  'course_version_id' => context.l10n.d('Cursusversienummer'),
  'course_offering_id' => context.l10n.d('Cursusaanbodnummer'),
  'offering_id' => context.l10n.d('Cursusaanbodnummer'),
  'requirement_id' => context.l10n.d('Nummer van de deelname-eis'),
  'voucher_id' => context.l10n.d('Nummer van de inschrijfcode'),
  'redeemed_at' => context.l10n.d('Gebruikt op'),
  'enrollment_source' => context.l10n.d('Herkomst van inschrijving'),
  'version_policy' => context.l10n.d('Regels voor de cursusversie'),
  'enrolled_at' => context.l10n.d('Ingeschreven op'),
  'lesson_id' => context.l10n.d('Lesnummer'),
  'completion_source' => context.l10n.d('Manier van afronden'),
  'source_id' => context.l10n.d('Nummer van het brongegeven'),
  'revocation_reason' => context.l10n.d('Reden van intrekking'),
  'client_session_id' => context.l10n.d('Afspeelsessienummer'),
  'last_slide_anchor' => context.l10n.d('Laatst bekeken dia'),
  'slide_milliseconds' => context.l10n.d(
    'Getoonde tijd per dia in milliseconden',
  ),
  'blueprint_version_id' => context.l10n.d('Nummer van de toetsopzet'),
  'deadline_at' => context.l10n.d('Uiterste inlevermoment'),
  'submitted_at' => context.l10n.d('Ingeleverd op'),
  'scored_at' => context.l10n.d('Beoordeeld op'),
  'released_at' => context.l10n.d('Vrijgegeven op'),
  'attempt_id' => context.l10n.d('Toetspogingnummer'),
  'item_version_id' => context.l10n.d('Vraagversienummer'),
  'position' => context.l10n.d('Positie'),
  'content' => context.l10n.d('Inhoud'),
  'option_order' => context.l10n.d('Volgorde van antwoordopties'),
  'randomization_context' => context.l10n.d(
    'Gegevens over willekeurige volgorde',
  ),
  'attempt_item_id' => context.l10n.d('Vraagnummer binnen de toetspoging'),
  'answer_data' => context.l10n.d('Antwoordgegevens'),
  'selected_options' => context.l10n.d('Gekozen antwoorden'),
  'confidence' => context.l10n.d('Zekerheid'),
  'client_request_id' => context.l10n.d('Verzoeknummer van de app'),
  'revision' => context.l10n.d('Versie'),
  'uploaded_by_subject' => context.l10n.d('Uzelf als uploader'),
  'declared_type' => context.l10n.d('Opgegeven bestandstype'),
  'declared_size' => context.l10n.d('Opgegeven bestandsgrootte'),
  'declared_hash' => context.l10n.d('Opgegeven controlecode'),
  'blob_hash' => context.l10n.d('Opgeslagen controlecode'),
  'blob_size' => context.l10n.d('Opgeslagen bestandsgrootte'),
  'rejection_reason' => context.l10n.d('Reden van afwijzing'),
  'verification_attempts' => context.l10n.d('Aantal controles'),
  'max_verification_attempts' => context.l10n.d('Maximaal aantal controles'),
  'claimed_at' => context.l10n.d('In behandeling genomen op'),
  'next_attempt_at' => context.l10n.d('Volgende controle op'),
  'verified_at' => context.l10n.d('Gecontroleerd op'),
  'skill_version_id' => context.l10n.d('Vaardigheidsversienummer'),
  'snapshot' => context.l10n.d('Vastgelegde gegevens'),
  'qualification_id' => context.l10n.d('Kwalificatienummer'),
  'event_type' => context.l10n.d('Soort gebeurtenis'),
  'evidence_hashes' => context.l10n.d('Controlecodes van bewijsstukken'),
  'type' => context.l10n.d('Soort'),
  'activity_id' => context.l10n.d('Activiteitnummer'),
  'activity_label' => context.l10n.d('Naam van de activiteit'),
  'minutes' => context.l10n.d('Aantal minuten'),
  'confirmed' => context.l10n.d('Bevestigd'),
  'confirmed_at' => context.l10n.d('Bevestigd op'),
  'confirmation_reason' => context.l10n.d('Reden van bevestiging'),
  'training_session_id' => context.l10n.d('Bijeenkomstnummer'),
  'enrollment_id' => context.l10n.d('Inschrijvingsnummer'),
  'attendance_kind' => context.l10n.d('Soort aanwezigheid'),
  'session_id' => context.l10n.d('Bijeenkomstnummer'),
  'booked_at' => context.l10n.d('Gereserveerd op'),
  'session_title' => context.l10n.d('Naam van de bijeenkomst'),
  'starts_at' => context.l10n.d('Begint op'),
  'ends_at' => context.l10n.d('Eindigt op'),
  'timezone' => context.l10n.d('Tijdzone'),
  'location' => context.l10n.d('Locatie'),
  'session_status' => context.l10n.d('Status van de bijeenkomst'),
  'participation_id' => context.l10n.d('Deelnamenummer'),
  'pe_rule_version_id' => context.l10n.d('Versienummer van de PE-regel'),
  'points' => context.l10n.d('Punten'),
  'idempotency_key' => context.l10n.d('Uniek verwerkingskenmerk'),
  'calculated_at' => context.l10n.d('Berekend op'),
  'pe_award_id' => context.l10n.d('PE-toekenningnummer'),
  'certificate_number' => context.l10n.d('Certificaatnummer'),
  'pdf_blob_key' => context.l10n.d('Technische opslaglocatie van de PDF'),
  'pdf_blob_hash' => context.l10n.d('Controlecode van de PDF'),
  'decision_snapshot' => context.l10n.d('Vastgelegde beslisgegevens'),
  _ => null,
};

String? _knownAdministrativeLabel(
  BuildContext context,
  String value,
) => switch (value) {
  'request_type' => context.l10n.d('Soort privacyverzoek'),
  'requested_by_subject' => context.l10n.d('Door uzelf aangevraagd'),
  'actor_account_id' => context.l10n.d('Uw accountnummer als uitvoerder'),
  'target_account_id' => context.l10n.d(
    'Accountnummer waarop de actie gericht was',
  ),
  'target_participant_id' => context.l10n.d(
    'Cursistnummer waarop de actie gericht was',
  ),
  'action' => context.l10n.d('Actie'),
  'request_id' => context.l10n.d('Verzoeknummer'),
  'policy_version' => context.l10n.d('Beleidsversie'),
  'identity_op_id' => context.l10n.d('Identiteitsbewerkingnummer'),
  'step_up_level' => context.l10n.d('Niveau van extra aanmeldcontrole'),
  'provider_result' => context.l10n.d('Resultaat bij de aanmeldprovider'),
  'detail' => context.l10n.d('Details'),
  'authentication_time' => context.l10n.d('Tijdstip van aanmelding'),
  'subject_account_id' => context.l10n.d('Uw accountnummer'),
  'op_type' => context.l10n.d('Soort accountbewerking'),
  'subject_payload' => context.l10n.d('Gegevens over uw accountbewerking'),
  'attempt' => context.l10n.d('Poging'),
  'max_attempts' => context.l10n.d('Maximaal aantal pogingen'),
  'provider_op_id' => context.l10n.d('Bewerkingnummer bij aanmeldprovider'),
  'last_error' => context.l10n.d('Laatste fout'),
  'response_status' => context.l10n.d('Antwoordstatus'),
  'response_location' => context.l10n.d('Verwijzing naar het antwoord'),
  'challenge_id' => context.l10n.d('Beveiligingsvraagnummer'),
  'attempted_at' => context.l10n.d('Geprobeerd op'),
  'seq' => context.l10n.d('Volgnummer'),
  'object' => context.l10n.d('Onderwerp van de actie'),
  'remote_addr' => context.l10n.d('Netwerkadres'),
  'singleton_id' => context.l10n.d('Installatienummer'),
  'state' => context.l10n.d('Toestand'),
  'canonical_origin' => context.l10n.d('Vast internetadres van de installatie'),
  'initialized_at' => context.l10n.d('Ingericht op'),
  'required_acr' => context.l10n.d('Vereist niveau van aanmeldzekerheid'),
  'required_amr' => context.l10n.d('Vereiste aanmeldmethoden'),
  'max_auth_age' => context.l10n.d('Maximale leeftijd van de aanmelding'),
  'strict_mode' => context.l10n.d('Strenge beveiligingsmodus'),
  'invited_email' => context.l10n.d('Uitgenodigd e-mailadres'),
  'attempts' => context.l10n.d('Aantal pogingen'),
  'accepted_at' => context.l10n.d('Geaccepteerd op'),
  'accepted_account_id' => context.l10n.d('Gekoppeld accountnummer'),
  'to_address' => context.l10n.d('Ontvanger'),
  'sent_at' => context.l10n.d('Verzonden op'),
  'last_active_at' => context.l10n.d('Laatst actief op'),
  'idle_expires_at' => context.l10n.d('Verloopt bij inactiviteit op'),
  'absolute_expires_at' => context.l10n.d('Verloopt definitief op'),
  'category' => context.l10n.d('Gegevenscategorie'),
  'retention_period' => context.l10n.d('Bewaartermijn'),
  'ground' => context.l10n.d('Reden of grondslag'),
  'action_on_expiry' => context.l10n.d('Wat gebeurt na de bewaartermijn'),
  'legal_hold' => context.l10n.d('Bewaren wegens een juridische verplichting'),
  'legal_hold_reason' => context.l10n.d('Reden voor langer bewaren'),
  'table_name' => context.l10n.d('Technische opslagcategorie'),
  'subject_record_id' => context.l10n.d('Nummer van uw verwijderde gegeven'),
  'deleted_at' => context.l10n.d('Verwijderd op'),
  'actor_account_id_subject' => context.l10n.d(
    'Uw accountnummer als uitvoerder',
  ),
  'completed' => context.l10n.d('Afgerond'),
  'score' => context.l10n.d('Score'),
  'max_score' => context.l10n.d('Hoogst haalbare score'),
  'passed' => context.l10n.d('Geslaagd'),
  'title' => context.l10n.d('Titel'),
  'description' => context.l10n.d('Beschrijving'),
  'role' => context.l10n.d('Rol'),
  'result' => context.l10n.d('Resultaat'),
  'reason' => context.l10n.d('Reden'),
  'filename' => context.l10n.d('Bestandsnaam'),
  'subject' => context.l10n.d('Onderwerp'),
  'body' => context.l10n.d('Bericht'),
  'value' => context.l10n.d('Waarde'),
  _ => null,
};

String _fallbackLabel(String value) {
  final text = value.replaceAll('_', ' ').trim();
  return text.isEmpty ? value : '${text[0].toUpperCase()}${text.substring(1)}';
}

String _fieldLabel(BuildContext context, String value) =>
    _label(context, value);

String _categoryDescription(BuildContext context, String key) {
  final definition = ociservePrivacyCategories[key];
  return definition == null
      ? context.l10n.d(
          'Deze categorie is door de server aangeleverd. De technische namen blijven zichtbaar voor navraag bij uw organisatie.',
        )
      : context.l10n.d(definition.dutchDescription);
}

String _display(
  BuildContext context,
  String key,
  Object? value, {
  String? omissionReason,
}) {
  if (omissionReason == 'third_party_data') {
    return context.l10n.d(
      'Niet getoond omdat dit gegeven ook over iemand anders gaat',
    );
  }
  if (omissionReason != null) {
    return context.l10n
        .d('Niet getoond door de server (reden: {reden})')
        .replaceAll('{reden}', omissionReason);
  }
  if (value == null) return context.l10n.d('Niet opgenomen in dit overzicht');
  if (value is bool) {
    return value ? context.l10n.d('Ja') : context.l10n.d('Nee');
  }
  if (value is String) {
    if (value.trim().isEmpty) return context.l10n.d('Niet ingevuld');
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed != null && value.contains(RegExp(r'[-T:]'))) {
      final material = MaterialLocalizations.of(context);
      return '${material.formatFullDate(parsed)} '
          '${material.formatTimeOfDay(TimeOfDay.fromDateTime(parsed))}';
    }
  }
  final known = switch ('$key:$value') {
    'status:active' => context.l10n.d('Actief'),
    'status:inactive' => context.l10n.d('Niet actief'),
    'status:pending' => context.l10n.d('In afwachting'),
    'status:in_progress' => context.l10n.d('In behandeling'),
    'status:completed' => context.l10n.d('Afgerond'),
    'status:failed' => context.l10n.d('Mislukt'),
    'status:revoked' => context.l10n.d('Ingetrokken'),
    'status:rejected' => context.l10n.d('Afgewezen'),
    'status:accepted' => context.l10n.d('Geaccepteerd'),
    'status:submitted' => context.l10n.d('Ingeleverd'),
    'status:scored' => context.l10n.d('Beoordeeld'),
    'status:released' => context.l10n.d('Vrijgegeven'),
    'status:verified' => context.l10n.d('Gecontroleerd'),
    'status:quarantined' => context.l10n.d('In quarantaine'),
    'status:booked' => context.l10n.d('Gereserveerd'),
    'status:cancelled' => context.l10n.d('Geannuleerd'),
    'status:waitlisted' => context.l10n.d('Op de wachtlijst'),
    'status:no_show' => context.l10n.d('Niet verschenen'),
    'status:succeeded' => context.l10n.d('Geslaagd'),
    'status:expired' => context.l10n.d('Verlopen'),
    'result:success' => context.l10n.d('Gelukt'),
    'result:failed' => context.l10n.d('Mislukt'),
    'attendance_kind:attended' => context.l10n.d('Aanwezig'),
    'attendance_kind:absent' => context.l10n.d('Afwezig'),
    'attendance_kind:no_show' => context.l10n.d('Niet verschenen'),
    'request_type:access' => context.l10n.d('Inzage'),
    'request_type:erasure' => context.l10n.d('Verwijdering'),
    'request_type:rectification' => context.l10n.d('Correctie'),
    'request_type:restriction' => context.l10n.d('Beperking'),
    'request_type:portability' => context.l10n.d('Overdraagbaarheid'),
    'request_type:objection' => context.l10n.d('Bezwaar'),
    'request_type:delete' => context.l10n.d('Verwijdering'),
    'role:owner' => context.l10n.d('Eigenaar'),
    'role:instructor' => context.l10n.d('Docent'),
    'role:author' => context.l10n.d('Auteur'),
    'role:assessor' => context.l10n.d('Beoordelaar'),
    'role:participant' => context.l10n.d('Cursist'),
    'role:organization_admin' => context.l10n.d('Organisatiebeheerder'),
    'event_type:rejected' => context.l10n.d('Afgewezen'),
    'event_type:revoked' => context.l10n.d('Ingetrokken'),
    'action_on_expiry:delete' => context.l10n.d('Verwijderen'),
    'provider_result:pending' => context.l10n.d('In afwachting'),
    'provider_result:succeeded' => context.l10n.d('Gelukt'),
    'provider_result:failed' => context.l10n.d('Mislukt'),
    'provider_result:unavailable' => context.l10n.d('Niet beschikbaar'),
    'ground:contract' => context.l10n.d('Overeenkomst'),
    'ground:legal_obligation' => context.l10n.d('Wettelijke verplichting'),
    'ground:legitimate_interest' => context.l10n.d('Gerechtvaardigd belang'),
    'ground:consent' => context.l10n.d('Toestemming'),
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
  if (value is String && value.contains('_')) return _label(context, value);
  return '$value';
}
