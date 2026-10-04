// De instap van de respondent (FORM_INTAKE.md §6.4): een uitnodigings- of
// terugkeerlink plakken, het formulier van de server halen — met de host in
// beeld vóórdat er iets heengaat — en het als gewoon document openen om in
// te vullen.
//
// De link zelf is nooit een sleutel: bij een terugkeerlink eist dit venster
// eerst een verse mailboxcode voordat de inzendingstoestand zichtbaar wordt.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_intake.dart';
import '../../services/file_service.dart' show pickDocumentExportDestination;
import '../../services/form/form_intake_context.dart';
import '../../services/form/form_intake_snapshot.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../services/ociserve/ociserve_intake_respondent.dart';
import '../../utils/atomic_file.dart';
import 'form_intake_challenge.dart';
import 'form_export_picker.dart' show rememberIntakeContext;

enum _Step { link, loading, landing, challenge, working, confirmWithdraw, done }

/// Opent de respondentreis. [onOpenPath] opent een opgeslagen bestand in een
/// tabblad, [onOpenText] een onopgeslagen document (het web); [pickDestination]
/// is het opslagvenster, in een test een nepkiezer.
Future<void> showFormIntakeInvitationDialog(
  BuildContext context, {
  required Future<void> Function(String path) onOpenPath,
  required void Function(String text) onOpenText,
  Future<String?> Function(String title, String fileName)? pickDestination,
  IntakeRespondentClient Function(String baseUrl)? clientFor,
}) => showDialog<void>(
  context: context,
  builder: (_) => FormIntakeInvitationDialog(
    onOpenPath: onOpenPath,
    onOpenText: onOpenText,
    pickDestination: pickDestination,
    clientFor: clientFor ?? (base) => IntakeRespondentClient(baseUrl: base),
  ),
);

class FormIntakeInvitationDialog extends StatefulWidget {
  const FormIntakeInvitationDialog({
    super.key,
    required this.onOpenPath,
    required this.onOpenText,
    this.pickDestination,
    required this.clientFor,
  });

  final Future<void> Function(String path) onOpenPath;
  final void Function(String text) onOpenText;
  final Future<String?> Function(String title, String fileName)?
  pickDestination;
  final IntakeRespondentClient Function(String baseUrl) clientFor;

  @override
  State<FormIntakeInvitationDialog> createState() =>
      _FormIntakeInvitationDialogState();
}

class _FormIntakeInvitationDialogState
    extends State<FormIntakeInvitationDialog> {
  final _link = TextEditingController();
  _Step _step = _Step.link;
  FormIntakeLink? _parsed;
  IntakePublicForm? _form;
  IntakeRespondentSubmission? _submission;
  IntakeGrant? _grant;
  String? _error;
  bool _withdrawing = false;
  bool _withdrawn = false;
  IntakeRespondentClient? _client;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  String _errorFor(Object error) {
    final l10n = context.l10n;
    if (error is OciServeException) {
      return switch (error.code) {
        'unavailable' || 'network_error' => l10n.d(
          'De server is nu niet bereikbaar. Controleer de link en probeer het later opnieuw.',
        ),
        _ => l10n.d(
          'De link werkte niet. Controleer hem en probeer het opnieuw.',
        ),
      };
    }
    return l10n.d(
      'De link werkte niet. Controleer hem en probeer het opnieuw.',
    );
  }

  Future<void> _openLink() async {
    final parsed = parseIntakeLink(_link.text);
    if (parsed == null || (parsed.formRef == null && parsed.locator == null)) {
      setState(
        () => _error = context.l10n.d(
          'Dat is geen uitnodigings- of terugkeerlink die OciDeck kent. Een link begint met https://.',
        ),
      );
      return;
    }
    setState(() {
      _parsed = parsed;
      _error = null;
      _step = _Step.loading;
    });
    _client ??= widget.clientFor(parsed.baseUrl);
    try {
      if (parsed.formRef != null) {
        final form = await _client!.publicForm(parsed.formRef!);
        if (!mounted) return;
        setState(() {
          _form = form;
          _step = _Step.landing;
        });
      } else {
        // Terugkeerlink: eerst een verse code, dan pas de toestand.
        setState(() => _step = _Step.challenge);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorFor(error);
        _step = _Step.link;
      });
    }
  }

  Future<void> _onGrant(IntakeGrant grant) async {
    if (_withdrawing) {
      // De verse code is geen bevestiging van onomkeerbaarheid: eerst
      // expliciet waarschuwen, pas daarna intrekken (§6.6).
      setState(() {
        _grant = grant;
        _step = _Step.confirmWithdraw;
      });
      return;
    }
    setState(() {
      _grant = grant;
      _step = _Step.working;
    });
    try {
      final fetched = await _client!.submission(grant: grant);
      final formRef = grant.formRef;
      IntakePublicForm? form;
      if (formRef != null) form = await _client!.publicForm(formRef);
      if (!mounted) return;
      setState(() {
        _submission = fetched?.value;
        _form = form;
        _parsed = FormIntakeLink(
          baseUrl: _parsed!.baseUrl,
          formRef: formRef,
          locator: _parsed!.locator,
        );
        _step = _Step.landing;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorFor(error);
        _step = _Step.link;
      });
    }
  }

  Future<void> _withdraw() async {
    try {
      await _client!.withdraw(
        grant: _grant!,
        idempotencyKey: const Uuid().v4(),
      );
      if (!mounted) return;
      setState(() {
        _withdrawn = true;
        _step = _Step.done;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorFor(error);
        _step = _Step.landing;
      });
    }
  }

  /// Het formulier als invulbaar document openen: de template-markdown uit
  /// de snapshot wordt een gewoon `.md`, met de intake-context ernaast.
  Future<void> _fill() async {
    final form = _form;
    if (form == null) return;
    final markdown = intakeFormMarkdown(form.snapshot);
    if (markdown == null) {
      setState(
        () => _error = context.l10n.d(
          'Deze publicatie bevat geen formulier dat OciDeck kan invullen.',
        ),
      );
      return;
    }
    final spec = switch (parseForm(markdown)) {
      ParsedForm(:final spec, canFill: true) => spec,
      _ => null,
    };
    if (spec == null) {
      setState(
        () => _error = context.l10n.d(
          'Deze publicatie bevat geen formulier dat OciDeck kan invullen.',
        ),
      );
      return;
    }
    final intake = FormIntakeContext(
      baseUrl: _parsed!.baseUrl,
      formRef: _parsed!.formRef ?? _grant?.formRef ?? '',
      locator: _parsed!.locator ?? _grant?.locator,
      revision: _submission?.revision,
      lastState: _submission?.state,
    );

    // Desktop: het bestand eerst opslaan, dan openen — de sidecar staat er
    // meteen naast. Het web kent geen paden: het sessiegeheugen draagt de
    // context tot de eerste bewuste opslag.
    final pick = widget.pickDestination;
    if (!kIsWeb) {
      final destination =
          pick ??
          (title, fileName) => pickDocumentExportDestination(
            dialogTitle: title,
            fileName: fileName,
          );
      final path = await destination(
        context.l10n.d('Bewaar het formulier om in te vullen'),
        'inzending.md',
      );
      if (path == null || !mounted) return;
      await writeStringAtomic(File(path), markdown);
      await rememberIntakeContext(
        spec: spec,
        context: intake,
        documentPath: path,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onOpenPath(path);
      return;
    }
    await rememberIntakeContext(spec: spec, context: intake);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onOpenText(markdown);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
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
                    l10n.d('Formulieruitnodiging'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                ..._body(l10n, theme),
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
                      onPressed: () => Navigator.of(context).pop(),
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
    _Step.link => [
      Text(
        l10n.d(
          'Plak de uitnodigings- of terugkeerlink die je kreeg. De link zelf is geen sleutel — voor je inzending is altijd een nieuwe code nodig.',
        ),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _link,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [],
        onSubmitted: (_) => _openLink(),
        decoration: InputDecoration(
          labelText: l10n.d('Uitnodigings- of terugkeerlink'),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _openLink, child: Text(l10n.d('Link openen'))),
    ],
    _Step.loading || _Step.working => [const LinearProgressIndicator()],
    _Step.challenge => [
      if (_parsed?.locator != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n
                .d(
                  'Deze link wijst naar jouw inzending op {server}. Om hem te openen is een nieuwe code nodig — de link alleen is nooit genoeg.',
                )
                .replaceAll('{server}', _parsed!.baseUrl),
          ),
        ),
      IntakeChallengeFlow(
        client: _client!,
        purpose: _withdrawing ? IntakePurpose.withdraw : IntakePurpose.resume,
        locator: _parsed!.locator,
        onGrant: _onGrant,
      ),
    ],
    _Step.landing => _landing(l10n, theme),
    _Step.confirmWithdraw => [
      Text(
        l10n.d(
          'Intrekken haalt je inzending weg bij de organisator en kan niet ongedaan worden gemaakt. Wil je doorgaan?',
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () {
          setState(() => _step = _Step.working);
          _withdraw();
        },
        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
        child: Text(l10n.d('Inzending intrekken')),
      ),
    ],
    _Step.done => [
      Text(
        _withdrawn ? l10n.d('Je inzending is ingetrokken.') : l10n.d('Klaar.'),
      ),
    ],
  };

  List<Widget> _landing(AppLocalizations l10n, ThemeData theme) {
    final form = _form;
    final submission = _submission;
    return [
      Text(
        l10n
            .d('Deze link wijst naar {server}.')
            .replaceAll('{server}', _parsed!.baseUrl),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      if (form != null) ...[
        Text(form.snapshot.title, style: theme.textTheme.titleSmall),
        if (form.snapshot.purposes.isNotEmpty)
          Text(
            l10n
                .d('Doel: {doelen}')
                .replaceAll('{doelen}', form.snapshot.purposes.join(' · ')),
          ),
        if (form.snapshot.privacyText.isNotEmpty)
          Text(form.snapshot.privacyText, style: theme.textTheme.bodySmall),
        Text(
          l10n
              .d('Bewaren: {dagen} dagen na indienen.')
              .replaceAll('{dagen}', '${form.snapshot.retentionSubmittedDays}'),
          style: theme.textTheme.bodySmall,
        ),
        if (!form.accepting)
          Text(
            l10n.d('Dit formulier neemt nu geen nieuwe inzendingen aan.'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
      ] else if (submission != null)
        // Het contract laat `form_ref` in een grant optioneel: zonder hem is
        // er niets om in te vullen — intrekken kan dan nog wel.
        Text(
          l10n.d(
            'De server gaf niet aan welk formulier bij deze inzending hoort — invullen is hier niet mogelijk.',
          ),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      if (submission != null) ...[
        const SizedBox(height: 8),
        Text(switch (submission.state) {
          IntakeSubmissionState.draft =>
            l10n
                .d('Je hebt hier een ontwerp staan (revisie {n}).')
                .replaceAll('{n}', '${submission.revision}'),
          IntakeSubmissionState.submitted =>
            l10n
                .d('Je inzending is binnen (revisie {n}).')
                .replaceAll('{n}', '${submission.revision}'),
          IntakeSubmissionState.correctionOpen =>
            l10n
                .d(
                  'De organisator vroeg een correctie: jouw wijziging wordt revisie {n}.',
                )
                .replaceAll('{n}', '${submission.revision + 1}'),
          IntakeSubmissionState.withdrawn => l10n.d(
            'Deze inzending is ingetrokken.',
          ),
        }),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (form != null &&
              (submission == null ||
                  submission.state != IntakeSubmissionState.withdrawn))
            FilledButton(
              onPressed: _fill,
              child: Text(l10n.d('Formulier invullen')),
            ),
          if (submission != null &&
              submission.allowedActions.contains(IntakeAllowedAction.withdraw))
            OutlinedButton(
              onPressed: () => setState(() {
                _withdrawing = true;
                _step = _Step.challenge;
              }),
              child: Text(l10n.d('Inzending intrekken…')),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        l10n.d(
          'Je vult in op je eigen apparaat; er wordt pas iets verstuurd als je dat zelf bevestigt.',
        ),
        style: theme.textTheme.bodySmall,
      ),
    ];
  }
}
