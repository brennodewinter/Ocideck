// De Inbox van een organisator, eerste vorm (FORM_INTAKE.md §7.2): een werkmap kiezen,
// de gepubliceerde formulieren erin zetten, inzendpakketten binnenhalen en zien wat
// er van elk geworden is. Wat er daarna mee gebeurt — status bijhouden, redigeren,
// samenstellen — gebeurt in het register (`overview.md`), dat een gewoon document is.
//
// Alleen desktop: de werkmap zijn bestanden op schijf.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart' show FormUnsealIssue;

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../services/form/form_import.dart';
import '../../services/form/form_intake_organiser.dart';
import '../../services/form/form_keys.dart' show FormKeyProblem;
import '../../services/form/form_workspace.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/form_keys_provider.dart';
import '../../state/forms_provider.dart';
import '../../state/ociserve_provider.dart';
import '../../state/tabs_provider.dart';
import 'form_book_dialog.dart';
import 'form_bundle_dialog.dart';
import 'form_inbox_list.dart';
import 'form_intake_publish_dialog.dart';
import 'form_intake_row_actions.dart';
import 'form_keys_dialog.dart';
import 'form_team_dialog.dart';
import 'form_text_helpers.dart' show formTextOf;

/// De kiezers van de Inbox: wat het systeem laat kiezen, als naad voor de test.
class FormInboxPickers {
  const FormInboxPickers({
    required this.folder,
    required this.form,
    required this.packages,
  });

  /// Een map, of `null` bij annuleren.
  final Future<String?> Function(String title) folder;

  /// De hele tekst van een formulierbestand, of `null` bij annuleren of als het geen
  /// UTF-8 is.
  final Future<String?> Function(String title) form;

  /// De gekozen pakketten: naam en bytes.
  final Future<List<({String name, Uint8List bytes})>> Function(String title)
  packages;
}

final FormInboxPickers systemFormInboxPickers = FormInboxPickers(
  // De werkmap zijn bestanden op schijf: in de browser bestaat `getDirectoryPath`
  // niet en geeft het stil null, en dan doet de knop zonder uitleg niets.
  folder: (title) async => supportsLocalProjectFolders
      ? FilePicker.getDirectoryPath(dialogTitle: title)
      : null,
  form: (title) async {
    final file = await FilePicker.pickFile(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: const ['md', 'markdown'],
    );
    return file == null ? null : formTextOf(await file.readAsBytes());
  },
  packages: (title) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: const ['zip', 'age'],
    );
    return [
      for (final file in files)
        (name: file.name, bytes: Uint8List.fromList(await file.readAsBytes())),
    ];
  },
);

/// Wat er van één binnengehaald bestand is geworden, als een regel voor de lijst.
class _Line {
  const _Line(this.ok, this.text);

  final bool ok;
  final String text;
}

Future<void> showFormInboxDialog(
  BuildContext context, {
  FormInboxPickers? pickers,
  DateTime Function()? now,
}) => showDialog<void>(
  context: context,
  builder: (_) => FormInboxDialog(pickers: pickers, now: now),
);

class FormInboxDialog extends ConsumerStatefulWidget {
  const FormInboxDialog({super.key, this.pickers, this.now});

  final FormInboxPickers? pickers;
  final DateTime Function()? now;

  @override
  ConsumerState<FormInboxDialog> createState() => _FormInboxDialogState();
}

class _FormInboxDialogState extends ConsumerState<FormInboxDialog> {
  FormInboxPickers get _pickers => widget.pickers ?? systemFormInboxPickers;

  List<PublishedForm> _forms = const [];
  int _submissions = 0;

  /// De Managed-Intake-publicaties van deze werkmap, lokaal formulier-id →
  /// record. Leeg: de werkmap kent alleen de lokale route.
  Map<String, IntakeOrganiserRecord> _records = const {};

  /// Telt op bij elke verversing, zodat de lijst opnieuw wordt gelezen.
  int _version = 0;
  bool _busy = false;
  String? _formMessage;
  final List<_Line> _lines = [];

  FormWorkspace? get _workspace {
    final root = ref.read(formsWorkspaceProvider);
    return root == null ? null : FormWorkspace(root);
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final workspace = _workspace;
    if (workspace == null) return;
    final forms = (await workspace.publishedForms()).forms;
    final submissions = (await workspace.submissionIds()).length;
    final records = await readIntakeRecords(workspace);
    if (!mounted) return;
    setState(() {
      _forms = forms;
      _submissions = submissions;
      _records = records;
      _version++;
    });
  }

  Future<void> _chooseFolder() async {
    final path = await _pickers.folder(
      context.l10n.d('Kies de werkmap voor inzendingen'),
    );
    if (path == null || !mounted) return;
    await ref.read(formsWorkspaceProvider.notifier).choose(path);
    _lines.clear();
    _formMessage = null;
    await _refresh();
  }

  Future<void> _addForm() async {
    final workspace = _workspace;
    final l10n = context.l10n;
    if (workspace == null) return;
    final text = await _pickers.form(
      l10n.d('Kies het formulier om toe te voegen'),
    );
    if (text == null || !mounted) return;
    final outcome = await workspace.publishForm(text);
    if (!mounted) return;
    setState(() {
      _formMessage = switch (outcome) {
        FormPublished(:final form) =>
          l10n
              .d('Formulier toegevoegd: {naam}.')
              .replaceAll('{naam}', _label(form)),
        FormPublishedAlready() => l10n.d('Dit formulier stond er al.'),
        FormPublishConflict() => l10n.d(
          'Dit formulier staat er al met een andere tekst. Een andere tekst is een nieuwe versie: geef het formulier een hoger versienummer.',
        ),
        FormPublishRefused() => l10n.d(
          'Dit bestand is geen formulier dat gepubliceerd kan worden.',
        ),
        FormPublishFailed() => l10n.d(
          'Het formulier kon niet worden opgeslagen.',
        ),
      };
    });
    await _refresh();
  }

  Future<void> _importPackages() async {
    final workspace = _workspace;
    final l10n = context.l10n;
    if (workspace == null) return;
    final files = await _pickers.packages(
      l10n.d('Kies de pakketten om binnen te halen'),
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _lines.clear();
    });
    for (final file in files) {
      final outcome = await importFormFile(
        workspace,
        file.bytes,
        now: (widget.now ?? DateTime.now)(),
        keys: ref.read(formKeyServiceProvider),
      );
      if (!mounted) return;
      setState(() => _lines.add(_describe(l10n, file.name, outcome)));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  _Line _describe(
    AppLocalizations l10n,
    String name,
    FormImportOutcome outcome,
  ) {
    String say(String translated) => translated.replaceAll('{naam}', name);
    return switch (outcome) {
      FormImported(registerSaved: false) => _Line(
        false,
        say(
          l10n.d(
            '{naam}: binnengehaald, maar het register kon niet worden bijgewerkt. Controleer overview.md.',
          ),
        ),
      ),
      FormImported(needsFixing: true) => _Line(
        false,
        say(
          l10n.d('{naam}: binnengehaald, maar er zijn punten om na te lopen.'),
        ),
      ),
      FormImported(wasSealed: true) => _Line(
        true,
        say(l10n.d('{naam}: verzegeld pakket geopend en binnengehaald.')),
      ),
      FormImported() => _Line(true, say(l10n.d('{naam}: binnengehaald.'))),
      FormImportDuplicate() => _Line(
        false,
        say(l10n.d('{naam}: stond er al.')),
      ),
      FormImportNotAPackage() => _Line(
        false,
        say(l10n.d('{naam}: geen inzendpakket dat OciDeck kan lezen.')),
      ),
      FormImportUnknownForm() => _Line(
        false,
        say(
          l10n.d(
            '{naam}: dit formulier is niet toegevoegd, of niet in deze versie. Voeg het formulier eerst toe.',
          ),
        ),
      ),
      FormImportFailed() => _Line(
        false,
        say(l10n.d('{naam}: kon niet worden opgeslagen in de werkmap.')),
      ),
      FormImportNeedsKey(:final problem) => _Line(
        false,
        say(_needsKey(l10n, problem)),
      ),
      FormImportNotOpened(:final issue) => _Line(
        false,
        say(_notOpened(l10n, issue)),
      ),
    };
  }

  String _needsKey(
    AppLocalizations l10n,
    FormKeyProblem problem,
  ) => switch (problem) {
    FormKeyProblem.unavailable => l10n.d(
      '{naam}: dit pakket is verzegeld en dit platform heeft geen sleutelhanger voor de redactiesleutel.',
    ),
    FormKeyProblem.absent => l10n.d(
      '{naam}: dit pakket is verzegeld en er is nog geen redactiesleutel om het te openen. Maak er een aan onder Redactiesleutel… of herstel hem uit je herstelsleutel.',
    ),
    FormKeyProblem.unreadable => l10n.d(
      '{naam}: dit pakket is verzegeld en de sleutelhanger is niet te lezen. Er is niets geprobeerd.',
    ),
    FormKeyProblem.damaged => l10n.d(
      '{naam}: dit pakket is verzegeld en de bewaarde redactiesleutel is niet te lezen. Verwijder hem onder Redactiesleutel… en herstel hem uit je herstelsleutel.',
    ),
  };

  String _notOpened(
    AppLocalizations l10n,
    FormUnsealIssue issue,
  ) => switch (issue) {
    FormUnsealIssue.noIdentityMatched => l10n.d(
      '{naam}: dit pakket is niet voor jouw redactiesleutel verzegeld.',
    ),
    FormUnsealIssue.tampered => l10n.d(
      '{naam}: dit pakket is veranderd of afgebroken en wordt niet geopend.',
    ),
    FormUnsealIssue.tooLarge => l10n.d(
      '{naam}: dit pakket is groter dan een inzending kan zijn.',
    ),
    FormUnsealIssue.badIdentity => l10n.d(
      '{naam}: de bewaarde redactiesleutel is geen sleutel die OciDeck kan gebruiken.',
    ),
    FormUnsealIssue.notAge ||
    FormUnsealIssue.notAPackage ||
    FormUnsealIssue.wrongSubmission ||
    FormUnsealIssue.wrongForm => l10n.d(
      '{naam}: geen verzegeld pakket dat OciDeck kan lezen.',
    ),
  };

  /// Sluit het venster en opent [path] in een tabblad: wie een bestand van de
  /// werkmap wil lezen of verbeteren wil het in de editor zien, niet achter een
  /// venster.
  Future<void> _open(String path) async {
    final tabs = ref.read(tabsProvider.notifier);
    Navigator.of(context).pop();
    await tabs.openFileByPath(path);
  }

  Future<void> _compileBook() async {
    final workspace = _workspace;
    if (workspace == null) return;
    await showFormBookDialog(
      context,
      workspace: workspace,
      forms: _forms,
      onOpenFile: _open,
    );
  }

  Future<void> _openTeam() async {
    final workspace = _workspace;
    if (workspace == null) return;
    await showFormTeamDialog(
      context,
      workspace: workspace,
      keys: ref.read(formKeyServiceProvider),
    );
  }

  Future<void> _makeInvitationPackage() async {
    final workspace = _workspace;
    if (workspace == null) return;
    await showFormBundleDialog(
      context,
      workspace: workspace,
      forms: _forms,
      keys: ref.read(formKeyServiceProvider),
      now: widget.now,
    );
  }

  Future<void> _openRegister() async {
    final workspace = _workspace;
    if (workspace != null) await _open(workspace.registerPath);
  }

  String _label(PublishedForm form) =>
      '${form.id} · v${form.version}${form.lang == null ? '' : ' · ${form.lang}'}';

  /// Onder de lijst met formulieren: een formulier toevoegen, een bundel voor
  /// wat er staat, en — als OciServe gekoppeld is — publiceren naar de server.
  Widget _formButtons(AppLocalizations l10n) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton(
        onPressed: _busy ? null : _addForm,
        child: Text(l10n.d('Formulier toevoegen…')),
      ),
      Tooltip(
        message: l10n.d(
          'Maak en onderteken de bundel die een invuller van jullie redactie gelooft.',
        ),
        child: OutlinedButton(
          onPressed: _busy || _forms.isEmpty ? null : _makeInvitationPackage,
          child: Text(l10n.d('Offline uitnodigingspakket maken…')),
        ),
      ),
      if (ref.watch(ociServeAuthenticatedProvider))
        Tooltip(
          message: l10n.d(
            'Publiceer een formulier als vastgelegde versie op jullie OciServe en deel de uitnodigingslink.',
          ),
          child: OutlinedButton(
            onPressed: _busy || _forms.isEmpty ? null : _publishToServer,
            child: Text(l10n.d('Publiceren via OciServe…')),
          ),
        ),
    ],
  );

  Future<void> _publishToServer() async {
    final workspace = _workspace;
    if (workspace == null) return;
    final published = await showFormIntakePublishDialog(
      context,
      workspace: workspace,
      forms: _forms,
    );
    if (published == true) await _refresh();
  }

  /// Haalt expliciet de toegewezen inzendingen op (§7.8): een knop, nooit een
  /// achtergrondtaak. Per gepubliceerd formulier één ronde; de regels onder
  /// de knop vertellen wat er binnenkwam.
  Future<void> _fetchFromServer() async {
    final workspace = _workspace;
    if (workspace == null || _busy) return;
    setState(() {
      _busy = true;
      _lines.clear();
    });
    for (final MapEntry(key: formId, value: record) in _records.entries) {
      try {
        final result = await ref
            .read(ociServeProvider.notifier)
            .withIntakeGateway(
              record.organizationId,
              (api, token) => fetchIntakeSubmissions(
                workspace: workspace,
                api: api,
                accessToken: token,
                record: record,
                now: (widget.now ?? DateTime.now)(),
                recordChanged: (updated) =>
                    writeIntakeRecord(workspace, formId, updated),
              ),
            );
        if (!mounted) return;
        setState(
          () => _lines.add(
            _Line(
              result.failed == 0,
              context.l10n
                  .d(
                    '{naam}: {nieuw} nieuw, {bijgewerkt} bijgewerkt, {ingetrokken} ingetrokken{mislukt}.',
                  )
                  .replaceAll('{naam}', formId)
                  .replaceAll('{nieuw}', '${result.fetched}')
                  .replaceAll('{bijgewerkt}', '${result.updated}')
                  .replaceAll('{ingetrokken}', '${result.withdrawn}')
                  .replaceAll(
                    '{mislukt}',
                    result.failed == 0
                        ? ''
                        : context.l10n
                              .d(', {n} niet binnengehaald')
                              .replaceAll('{n}', '${result.failed}'),
                  ),
            ),
          ),
        );
      } on Object catch (error) {
        if (!mounted) return;
        setState(
          () => _lines.add(
            _Line(
              false,
              context.l10n
                  .d('{naam}: {fout}')
                  .replaceAll('{naam}', formId)
                  .replaceAll('{fout}', _fetchError(error)),
            ),
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  String _fetchError(Object error) {
    final l10n = context.l10n;
    if (error is OciServeException) {
      return switch (error.code) {
        'unauthorized' || 'forbidden' => l10n.d(
          'je mag deze inzendingen daar niet lezen — controleer de organisatie en je rechten.',
        ),
        'unavailable' || 'network_error' => l10n.d(
          'de server is nu niet bereikbaar; er is niets veranderd.',
        ),
        _ => l10n.d('ophalen lukte niet; er is niets veranderd.'),
      };
    }
    return l10n.d('ophalen lukte niet; er is niets veranderd.');
  }

  /// Onderaan: de redactiesleutel (die ook zonder werkmap open moet kunnen) en Sluiten.
  Widget _bottomRow(AppLocalizations l10n) => Row(
    children: [
      Tooltip(
        message: l10n.d(
          'De sleutel waarmee verzegelde inzendingen worden geopend en bundels worden ondertekend.',
        ),
        child: OutlinedButton(
          onPressed: _busy ? null : () => showFormKeysDialog(context),
          child: Text(l10n.d('Redactiesleutel…')),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton(
        onPressed: _busy || _workspace == null ? null : _openTeam,
        child: Text(l10n.d('Team…')),
      ),
      const Spacer(),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.d('Sluiten')),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final root = ref.watch(formsWorkspaceProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
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
                    l10n.d('Inzendingen'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                _section(theme, l10n.d('Werkmap')),
                Text(
                  root ??
                      l10n.d(
                        'Nog geen werkmap gekozen. Kies een map waarin de inzendingen en het register komen te staan.',
                      ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _chooseFolder,
                  child: Text(l10n.d('Werkmap kiezen…')),
                ),
                if (root != null) ...[
                  const SizedBox(height: 20),
                  _section(theme, l10n.d('Formulieren')),
                  if (_forms.isEmpty)
                    Text(
                      l10n.d(
                        'Nog geen formulier toegevoegd. Voeg het formulier toe zoals je het hebt gepubliceerd: een inzending wordt daartegen gehouden.',
                      ),
                    )
                  else
                    for (final form in _forms) Text(_label(form)),
                  const SizedBox(height: 8),
                  _formButtons(l10n),
                  if (_formMessage != null) ...[
                    const SizedBox(height: 8),
                    Semantics(liveRegion: true, child: Text(_formMessage!)),
                  ],
                  const SizedBox(height: 20),
                  _section(theme, l10n.d('Inzendingen')),
                  ..._submissionSection(l10n, theme, root),
                ],
                const SizedBox(height: 20),
                _bottomRow(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Het deel onder de sectiekop *Inzendingen*: teller, waarschuwing, de
  /// actieknoppen (inclusief OciServe als er records zijn), de
  /// resultaatregels van de laatste ronde en de lijst zelf.
  List<Widget> _submissionSection(
    AppLocalizations l10n,
    ThemeData theme,
    String root,
  ) => [
    Text(
      l10n
          .d('Inzendingen in de werkmap: {n}')
          .replaceAll('{n}', '$_submissions'),
    ),
    const SizedBox(height: 4),
    Text(
      '${l10n.d('Een gewone zip is onderweg niet versleuteld.')} ${l10n.d('Een verzegeld bestand (.zip.age) opent met je redactiesleutel.')}',
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: _busy || _forms.isEmpty ? null : _importPackages,
          child: Text(l10n.d('Pakketten binnenhalen…')),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _openRegister,
          child: Text(l10n.d('Register openen')),
        ),
        OutlinedButton(
          onPressed: _busy || _forms.isEmpty ? null : _compileBook,
          child: Text(l10n.d('Boek samenstellen…')),
        ),
        if (_records.isNotEmpty && ref.watch(ociServeAuthenticatedProvider))
          OutlinedButton(
            onPressed: _busy ? null : _fetchFromServer,
            child: Text(l10n.d('Ophalen van OciServe')),
          ),
      ],
    ),
    if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
    if (_lines.isNotEmpty) ...[
      const SizedBox(height: 12),
      Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in _lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      line.ok
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 18,
                      color: line.ok
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(line.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
    const SizedBox(height: 12),
    FormInboxList(
      workspace: FormWorkspace(root),
      version: _version,
      onOpenFile: _open,
      extraActions: _records.isEmpty
          ? null
          : (sid) => FormIntakeRowActions(
              workspace: FormWorkspace(root),
              sid: sid,
              onDone: (message) {
                setState(() {
                  _formMessage = message;
                  _version++;
                });
              },
            ),
    ),
  ];

  Widget _section(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Semantics(
      header: true,
      child: Text(title, style: theme.textTheme.titleSmall),
    ),
  );
}
