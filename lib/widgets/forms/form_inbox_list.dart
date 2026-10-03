// De lijst van de Inbox (FORM_INTAKE.md §7.2, §7.3): een regel per inzending uit het
// register, en per inzending — als je hem openklapt — wat er tegen het gepubliceerde
// formulier mis mee is, in gewone woorden.
//
// Wat hier staat is de stand van nu. De punten komen niet uit een bewaarde lijst maar
// uit een nieuwe beoordeling van wat in de werkmap staat (`reviewStored`): een
// correctie in de werkkopie haalt een punt weg zonder dat iets anders bijgewerkt hoeft
// te worden.

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/form_issue_localization.dart';
import '../../services/form/form_submission_actions.dart'
    show FormDeleteOutcome, deleteSubmission;
import '../../services/form/form_workspace.dart';
import 'form_inbox_actions.dart';
import 'form_text_helpers.dart' show formFieldTitle;

/// Een inzending in de lijst: haar nummer en, als het register haar kent, haar rij.
class _Entry {
  const _Entry(this.sid, this.row);

  final String sid;
  final FormRegisterRow? row;
}

/// Wat de lijst van de werkmap weet.
class _Loaded {
  const _Loaded(this.entries, {required this.registerDamaged});

  final List<_Entry> entries;
  final bool registerDamaged;
}

class FormInboxList extends StatefulWidget {
  const FormInboxList({
    super.key,
    required this.workspace,
    this.version = 0,
    this.now,
    this.delete = deleteSubmission,
    this.onOpenFile,
  });

  final FormWorkspace workspace;

  /// Opent een bestand van de werkmap (de werkkopie van een inzending). `null`: de
  /// knop ontbreekt.
  final ValueChanged<String>? onOpenFile;

  /// Het verwijderen zelf; een naad voor de test (zie [FormInboxActions.delete]).
  final Future<FormDeleteOutcome> Function(
    FormWorkspace workspace,
    String sid, {
    List<String> keep,
  })
  delete;

  /// De klok voor de voorgestelde dag bij intrekken; in een test een vaste waarde.
  final DateTime Function()? now;

  /// Verandert als er iets is binnengekomen: dan wordt de lijst opnieuw gelezen.
  final int version;

  @override
  State<FormInboxList> createState() => _FormInboxListState();
}

class _FormInboxListState extends State<FormInboxList> {
  Future<_Loaded>? _loaded;

  /// De zin over wat de organisator het laatst deed ("Status gewijzigd naar …").
  String? _notice;

  /// De beoordelingen die al zijn opgevraagd, zodat openklappen niet elke keer
  /// opnieuw leest. Ze gaan weg als de lijst opnieuw wordt gelezen.
  final Map<String, Future<FormStoredReviewResult>> _reviews = {};

  @override
  void initState() {
    super.initState();
    _loaded = _load();
  }

  @override
  void didUpdateWidget(FormInboxList old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version ||
        old.workspace.root != widget.workspace.root) {
      _reviews.clear();
      _loaded = _load();
    }
  }

  Future<_Loaded> _load() async {
    final ids = await widget.workspace.submissionIds();
    final register = await widget.workspace.readRegister();
    final rows = switch (register) {
      FormRegisterParsed(:final register) => register.rows,
      _ => const <FormRegisterRow>[],
    };
    final listed = {for (final row in rows) row.sid};
    return _Loaded([
      // Het register houdt de volgorde van binnenkomst; de nieuwste staat bovenaan.
      for (final row in rows.reversed) _Entry(row.sid, row),
      for (final sid in ids)
        if (!listed.contains(sid)) _Entry(sid, null),
    ], registerDamaged: register is FormRegisterDamaged);
  }

  /// Er is iets gedaan met een inzending: zeg hoe het ging en lees de lijst opnieuw.
  void _done(String message) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _reviews.clear();
      _loaded = _load();
    });
  }

  Future<FormStoredReviewResult> _review(String sid) =>
      _reviews.putIfAbsent(sid, () => widget.workspace.reviewStored(sid));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Loaded>(
      future: _loaded,
      builder: (context, snapshot) {
        final l10n = context.l10n;
        final loaded = snapshot.data;
        if (loaded == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(liveRegion: true, child: Text(_notice!)),
              ),
            if (loaded.registerDamaged)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.d(
                    'Het register kan niet worden gelezen. Herstel overview.md; de inzendingen staan hieronder zonder gegevens uit het register.',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (loaded.entries.isEmpty)
              Text(l10n.d('Nog geen inzendingen.'))
            else
              for (final entry in loaded.entries)
                _EntryTile(
                  entry: entry,
                  workspace: widget.workspace,
                  review: () => _review(entry.sid),
                  onDone: _done,
                  now: widget.now,
                  delete: widget.delete,
                  onOpenFile: widget.onOpenFile,
                ),
          ],
        );
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.workspace,
    required this.review,
    required this.onDone,
    required this.delete,
    this.onOpenFile,
    this.now,
  });

  final _Entry entry;
  final ValueChanged<String>? onOpenFile;
  final FormWorkspace workspace;
  final Future<FormStoredReviewResult> Function() review;
  final ValueChanged<String> onDone;
  final DateTime Function()? now;
  final Future<FormDeleteOutcome> Function(
    FormWorkspace workspace,
    String sid, {
    List<String> keep,
  })
  delete;

  static const _fixed = {
    'sid',
    'received',
    'status',
    'consent',
    'withdrawn',
    'delete-after',
  };

  /// De naam van de inzending in de lijst: de overzichtskolommen van het formulier,
  /// anders het begin van het nummer.
  String _title() {
    final row = entry.row;
    final shown = [
      if (row != null)
        for (final MapEntry(:key, :value) in row.cells.entries)
          if (!_fixed.contains(key) && value.trim().isNotEmpty) value.trim(),
    ];
    return shown.isEmpty ? '${entry.sid.substring(0, 8)}…' : shown.join(' · ');
  }

  String _status(AppLocalizations l10n, String status) => switch (status) {
    kFormStateNeedsFixing => l10n.d('Om na te lopen'),
    kFormStateDeleted => l10n.d('Verwijderd'),
    _ => status,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final row = entry.row;
    final fixing = row?.status == kFormStateNeedsFixing;
    final subtitle = [
      if (row == null)
        l10n.d('Zonder regel in het register')
      else ...[
        _status(l10n, row.status),
        if (row.received.isNotEmpty)
          l10n.d('Ontvangen {datum}').replaceAll('{datum}', row.received),
        if (row.isWithdrawn)
          l10n.d('Ingetrokken {datum}').replaceAll('{datum}', row.withdrawn),
      ],
    ].join(' · ');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: Icon(
        row?.isDeleted == true
            ? Icons.delete_outline
            : fixing
            ? Icons.error_outline
            : Icons.check_circle_outline,
        color: fixing ? scheme.error : null,
      ),
      title: Text(_title()),
      subtitle: Text(subtitle),
      childrenPadding: const EdgeInsets.fromLTRB(40, 0, 0, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Detail(
          review: review,
          workspace: workspace,
          entry: entry,
          onDone: onDone,
          now: now,
          delete: delete,
          onOpenFile: onOpenFile,
        ),
      ],
    );
  }
}

/// Wat er tegen het gepubliceerde formulier mis is met één inzending. Wordt pas
/// gebouwd — en dus pas gelezen — als de regel wordt opengeklapt.
class _Detail extends StatelessWidget {
  const _Detail({
    required this.review,
    required this.workspace,
    required this.entry,
    required this.onDone,
    required this.delete,
    this.onOpenFile,
    this.now,
  });

  final ValueChanged<String>? onOpenFile;
  final Future<FormStoredReviewResult> Function() review;
  final FormWorkspace workspace;
  final _Entry entry;
  final ValueChanged<String> onDone;
  final DateTime Function()? now;
  final Future<FormDeleteOutcome> Function(
    FormWorkspace workspace,
    String sid, {
    List<String> keep,
  })
  delete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<FormStoredReviewResult>(
      future: review(),
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            switch (result) {
              FormStoredUnavailable(deleted: true) => Text(
                l10n.d(
                  'De inhoud van deze inzending is verwijderd; alleen het record staat er nog.',
                ),
              ),
              FormStoredUnavailable() => Text(
                l10n.d(
                  'Deze inzending kan niet worden gelezen. Controleer de bestanden in de werkmap.',
                ),
              ),
              FormStoredReview(:final review, :final edited) => FormReviewView(
                review: review,
                edited: edited,
              ),
            },
            FormInboxActions(
              workspace: workspace,
              sid: entry.sid,
              row: entry.row,
              spec: result is FormStoredReview ? result.review.spec : null,
              onDone: onDone,
              now: now,
              delete: delete,
              onOpenFile: onOpenFile,
              canEdit: result is FormStoredReview,
              hasWorkingCopy: switch (result) {
                FormStoredReview(:final edited) => edited,
                FormStoredUnavailable(:final edited) => edited,
              },
            ),
          ],
        );
      },
    );
  }
}

/// De punten van één beoordeling, elk bij de naam van het veld waar het over gaat.
class FormReviewView extends StatelessWidget {
  const FormReviewView({super.key, required this.review, required this.edited});

  final FormReview review;
  final bool edited;

  /// De naam van het veld waar een punt over gaat: het eerste label, anders de id.
  String? _field(FormProblem problem) {
    final id = problem.fieldId;
    if (id == null) return null;
    final spec = review.spec;
    final text = review.published;
    final field = spec?.fieldById(id);
    if (field == null || text == null) return id;
    return formFieldTitle(
      text.substring(field.label.start, field.label.end).trim(),
      id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final spec = review.spec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (spec != null)
          Text(
            l10n
                .d('Beoordeeld tegen {formulier}.')
                .replaceAll('{formulier}', '${spec.id} · v${spec.version}'),
            style: theme.textTheme.bodySmall,
          ),
        if (edited)
          Text(
            l10n.d(
              'De beoordeling gaat over de werkkopie (submission.edit.md).',
            ),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 6),
        if (review.problems.isEmpty)
          Text(l10n.d('Geen punten om na te lopen.'))
        else
          for (final problem in review.problems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (problem.severity) {
                      FormSeverity.error => Icons.error_outline,
                      FormSeverity.warning => Icons.warning_amber_outlined,
                      FormSeverity.info => Icons.info_outline,
                    },
                    size: 18,
                    color: problem.isError ? theme.colorScheme.error : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (_field(problem) case final field?)
                            TextSpan(
                              text: '$field: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          TextSpan(text: formOrganiserMessage(l10n, problem)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        if (review.unreferencedImages.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            l10n
                .d('Foto’s die geen antwoord noemt: {n}.')
                .replaceAll('{n}', '${review.unreferencedImages.length}'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
