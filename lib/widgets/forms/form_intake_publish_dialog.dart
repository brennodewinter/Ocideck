// Een formulier publiceren als immutable snapshot op OciServe
// (FORM_INTAKE.md §6.2, §7.8). Vóór de bevestiging staat op het scherm wat er
// waar naartoe gaat: server, organisatie, versie en de beloftes die de
// snapshot draagt (doel, privacy, bewaartermijn, correctiebeleid). Een
// gewijzigde tekst wordt altijd een nieuwe versie — bestaande versies zijn
// onaantastbaar.
//
// De organisator-auth gaat via de OciServe-sessie (OIDC + lidmaatschap);
// respondenten gaan een heel andere ketting in (§6.6) en komen hier nooit aan
// te pas.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_intake.dart';
import '../../models/ociserve_models.dart';
import '../../services/form/form_intake_organiser.dart';
import '../../services/form/form_intake_snapshot.dart';
import '../../services/form/form_intake_context.dart';
import '../../services/form/form_workspace.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';

enum _Step { edit, working, done }

/// Opent de publicatiedialoog voor de formulieren in [workspace]. Geeft `true`
/// terug als er gepubliceerd is, zodat de Inbox zijn gegevens ververst.
Future<bool?> showFormIntakePublishDialog(
  BuildContext context, {
  required FormWorkspace workspace,
  required List<PublishedForm> forms,
}) => showDialog<bool>(
  context: context,
  builder: (_) => FormIntakePublishDialog(workspace: workspace, forms: forms),
);

class FormIntakePublishDialog extends ConsumerStatefulWidget {
  const FormIntakePublishDialog({
    super.key,
    required this.workspace,
    required this.forms,
  });

  final FormWorkspace workspace;
  final List<PublishedForm> forms;

  @override
  ConsumerState<FormIntakePublishDialog> createState() =>
      _FormIntakePublishDialogState();
}

class _FormIntakePublishDialogState
    extends ConsumerState<FormIntakePublishDialog> {
  _Step _step = _Step.edit;
  String? _error;

  PublishedForm? _form;
  String? _organizationId;
  IntakeOrganiserRecord? _record;

  final _name = TextEditingController();
  final _title = TextEditingController();
  final _purposes = TextEditingController();
  final _privacy = TextEditingController();
  final _draftDays = TextEditingController(text: '30');
  final _submittedDays = TextEditingController(text: '365');
  final _deadlineDays = TextEditingController(text: '14');
  bool _correctionAllowed = true;

  IntakeForm? _created;
  int? _publishedVersion;
  String? _invitationLink;

  @override
  void initState() {
    super.initState();
    if (widget.forms.isNotEmpty) _chooseForm(widget.forms.first);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _title,
      _purposes,
      _privacy,
      _draftDays,
      _submittedDays,
      _deadlineDays,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseForm(PublishedForm form) async {
    final record = await readIntakeRecord(widget.workspace, form.id);
    if (!mounted) return;
    setState(() {
      _form = form;
      _record = record;
      if (_name.text.isEmpty) _name.text = '${form.id} v${form.version}';
    });
  }

  String? get _fieldError {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty || _title.text.trim().isEmpty) {
      return l10n.d('Vul een naam en een titel in.');
    }
    final purposes = _purposeList;
    if (purposes.isEmpty) {
      return l10n.d('Vul minstens één doel in — per regel één.');
    }
    final draft = int.tryParse(_draftDays.text.trim());
    final submitted = int.tryParse(_submittedDays.text.trim());
    if (draft == null ||
        draft < 1 ||
        draft > intakeDraftDaysMax ||
        submitted == null ||
        submitted < 1 ||
        submitted > intakeSubmittedDaysMax) {
      return l10n
          .d(
            'De bewaartermijnen kloppen niet: een ontwerp maximaal {draft} dagen, een inzending maximaal {submitted} dagen.',
          )
          .replaceAll('{draft}', '$intakeDraftDaysMax')
          .replaceAll('{submitted}', '$intakeSubmittedDaysMax');
    }
    if (_correctionAllowed) {
      final deadline = int.tryParse(_deadlineDays.text.trim());
      if (deadline != null && deadline < 1) {
        return l10n.d('De correctietermijn klopt niet.');
      }
    }
    return null;
  }

  List<String> get _purposeList => [
    for (final line in _purposes.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  IntakeFormSnapshot _snapshot() => buildIntakeSnapshot(
    markdown: _form!.text,
    title: _title.text.trim(),
    purposes: _purposeList,
    privacyText: _privacy.text.trim(),
    retentionDraftDays: int.parse(_draftDays.text.trim()),
    retentionSubmittedDays: int.parse(_submittedDays.text.trim()),
    correctionAllowed: _correctionAllowed,
    correctionDeadlineDays: _correctionAllowed
        ? int.tryParse(_deadlineDays.text.trim())
        : null,
  );

  Future<void> _publish() async {
    final form = _form;
    final organizationId = _organizationId;
    if (form == null || organizationId == null || _step == _Step.working) {
      return;
    }
    setState(() {
      _step = _Step.working;
      _error = null;
    });
    try {
      final snapshot = _snapshot();
      final record = _record;
      final notifier = ref.read(ociServeProvider.notifier);
      if (record == null) {
        final created = await notifier.withIntakeGateway(
          organizationId,
          (api, token) => api.createIntakeForm(
            accessToken: token,
            organizationId: organizationId,
            name: _name.text.trim(),
            snapshot: snapshot,
            idempotencyKey: const Uuid().v4(),
          ),
        );
        await _finish(
          IntakeOrganiserRecord(
            baseUrl: ref.read(ociServeProvider).settings.normalizedBaseUrl,
            organizationId: organizationId,
            formId: created.formId,
            formRef: created.formRef,
            activeVersion: created.activeVersion,
          ),
          created.activeVersion,
          created,
        );
      } else {
        final version = await notifier.withIntakeGateway(
          organizationId,
          (api, token) => api.publishIntakeFormVersion(
            accessToken: token,
            organizationId: organizationId,
            formId: record.formId,
            snapshot: snapshot,
            idempotencyKey: const Uuid().v4(),
          ),
        );
        await _finish(
          record.copyWith(activeVersion: version.version),
          version.version,
          null,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _step = _Step.edit;
        _error = _errorFor(error);
      });
    }
  }

  Future<void> _finish(
    IntakeOrganiserRecord record,
    int version,
    IntakeForm? created,
  ) async {
    await writeIntakeRecord(widget.workspace, _form!.id, record);
    if (!mounted) return;
    setState(() {
      _record = record;
      _created = created;
      _publishedVersion = version;
      _invitationLink = intakeInvitationLink(record.baseUrl, record.formRef);
      _step = _Step.done;
    });
  }

  String _errorFor(Object error) {
    final l10n = context.l10n;
    if (error is OciServeException) {
      return switch (error.code) {
        'unauthorized' || 'forbidden' => l10n.d(
          'Je mag dit formulier daar niet publiceren. Controleer de organisatie en je rechten.',
        ),
        'unavailable' || 'network_error' => l10n.d(
          'De server is nu niet bereikbaar. Er is niets gepubliceerd — probeer het later opnieuw.',
        ),
        _ => l10n.d(
          'Publiceren lukte niet. Er is niets veranderd op de server.',
        ),
      };
    }
    return l10n.d('Publiceren lukte niet. Er is niets veranderd op de server.');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.d('Publiceren via OciServe'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                ..._body(l10n, theme),
                if (_step == _Step.working) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _step == _Step.working
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(_step == _Step.done ? true : null),
                      child: Text(l10n.d('Sluiten')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n, ThemeData theme) => switch (_step) {
    _Step.edit => _edit(l10n, theme),
    _Step.working => [const SizedBox.shrink()],
    _Step.done => [
      Text(
        _created != null
            ? l10n
                  .d('Formulier gepubliceerd als versie {n}.')
                  .replaceAll('{n}', '$_publishedVersion')
            : l10n
                  .d('Nieuwe versie {n} gepubliceerd.')
                  .replaceAll('{n}', '$_publishedVersion'),
      ),
      const SizedBox(height: 8),
      Text(
        l10n.d(
          'Deel deze uitnodigingslink met wie je het formulier wilt laten invullen. De link verwijst alleen naar het formulier — hij opent geen inzendingen.',
        ),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: SelectableText(
              _invitationLink ?? '',
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: l10n.d('Link kopiëren'),
            icon: const Icon(Icons.copy_outlined),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _invitationLink ?? '')),
          ),
        ],
      ),
    ],
  };

  List<Widget> _edit(AppLocalizations l10n, ThemeData theme) {
    final memberships = ref.watch(ociServeProvider).memberships;
    final server = ref.watch(ociServeProvider).settings.normalizedBaseUrl;
    final fieldError = _fieldError;
    return [
      _picker<PublishedForm>(
        label: l10n.d('Formulier'),
        value: _form,
        items: [
          for (final form in widget.forms)
            DropdownMenuItem(value: form, child: Text(_label(form))),
        ],
        onChanged: (form) => form == null ? null : _chooseForm(form),
      ),
      const SizedBox(height: 12),
      _picker<String>(
        label: l10n.d('Organisatie'),
        value: _organizationId,
        items: [
          for (final membership in memberships)
            DropdownMenuItem(
              value: membership.organizationId,
              child: Text(
                membership.name.isEmpty
                    ? membership.organizationId
                    : membership.name,
              ),
            ),
        ],
        onChanged: (id) => setState(() => _organizationId = id),
      ),
      const SizedBox(height: 12),
      _field(_name, l10n.d('Naam voor de organisatie')),
      _field(_title, l10n.d('Titel die de invuller ziet')),
      _field(_purposes, l10n.d('Doelen (één per regel)'), maxLines: 3),
      _field(_privacy, l10n.d('Privacytekst'), maxLines: 3),
      Row(
        children: [
          Expanded(
            child: _field(
              _draftDays,
              l10n.d('Ontwerp bewaren (dagen)'),
              number: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _field(
              _submittedDays,
              l10n.d('Inzending bewaren (dagen)'),
              number: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.d('Correctie achteraf toestaan')),
        value: _correctionAllowed,
        onChanged: (value) =>
            setState(() => _correctionAllowed = value ?? false),
      ),
      if (_correctionAllowed)
        _field(
          _deadlineDays,
          l10n.d('Correctietermijn (dagen, leeg = geen einde)'),
          number: true,
        ),
      const SizedBox(height: 16),
      _summary(l10n, theme, server, memberships),
      const SizedBox(height: 8),
      if (fieldError != null)
        Text(fieldError, style: TextStyle(color: theme.colorScheme.error)),
      const SizedBox(height: 8),
      FilledButton(
        onPressed:
            fieldError != null || _organizationId == null || _form == null
            ? null
            : _publish,
        child: Text(
          _record == null
              ? l10n.d('Publiceren')
              : l10n.d('Als nieuwe versie publiceren'),
        ),
      ),
    ];
  }

  Widget _summary(
    AppLocalizations l10n,
    ThemeData theme,
    String server,
    List<OciServeMembership> memberships,
  ) {
    // Alleen een geldige invoer levert een vingerafdruk; anders zou de
    // dagen-parse hier gooien terwijl _fieldError dat net netjes meldt.
    final snapshot = _form == null || _fieldError != null ? null : _snapshot();
    final hash = snapshot == null
        ? null
        : sha256.convert(utf8.encode(jsonEncode(snapshot.toJson()))).toString();
    final version = (_record?.activeVersion ?? 0) + 1;
    final org = memberships
        .where((m) => m.organizationId == _organizationId)
        .firstOrNull;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Dit gaat er naartoe'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.d('Server: {server}').replaceAll('{server}', server),
            style: theme.textTheme.bodySmall,
          ),
          if (org != null)
            Text(
              l10n
                  .d('Organisatie: {organisatie}')
                  .replaceAll(
                    '{organisatie}',
                    org.name.isEmpty ? org.organizationId : org.name,
                  ),
              style: theme.textTheme.bodySmall,
            ),
          Text(
            l10n
                .d('Versie: {versie} — vorige versies blijven onaantastbaar.')
                .replaceAll('{versie}', '$version'),
            style: theme.textTheme.bodySmall,
          ),
          if (hash != null)
            Text(
              l10n
                  .d('Vingerafdruk: {hash}…')
                  .replaceAll('{hash}', hash.substring(0, 12)),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  /// Het label van een formulierkeuze — id en versie, zoals de Inbox ze
  /// ook onder elkaar zet.
  String _label(PublishedForm form) => '${form.id} · v${form.version}';

  Widget _picker<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => DropdownButtonFormField<T>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: items,
    onChanged: _step == _Step.working ? null : onChanged,
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: _step != _Step.working,
      maxLines: maxLines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
