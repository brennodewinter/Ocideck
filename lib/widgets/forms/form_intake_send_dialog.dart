// De verzendweg van de respondent (FORM_INTAKE.md §6.4): bestemming en doel
// tonen → mailboxcode → bevestigen → pakket en instemming naar OciServe.
// Alles blijft een expliciete keuze: er wordt nooit automatisch verstuurd, en
// "opslaan als bestand" blijft ernaast gewoon bestaan — bij elke fout staat
// die uitweg er weer.
//
// De code en de grant leven alleen in dit venster en in de transportclient;
// wat er na afloop overblijft is de bijgewerkte intake-context (locator en
// revisie — verwijzingen, geen sleutels).
library;

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_intake.dart';
import '../../services/form/form_intake_context.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../services/ociserve/ociserve_intake_respondent.dart';
import 'form_intake_challenge.dart';

enum _Step {
  loading,
  intro,
  challenge,
  confirm,
  confirmWithdraw,
  working,
  done,
}

/// Opent de verzendweg voor [package] naar de intake-context [intakeContext].
/// Geeft de bijgewerkte context terug (locator, revisie, laatste toestand) als
/// er iets verstuurd of opgehaald is, anders `null`.
///
/// [clientFor] is de naad voor de test: hij maakt de transportclient bij de
/// basis-URL uit de context — nooit bij de OciServe-instelling van dit
/// apparaat.
Future<FormIntakeContext?> showFormIntakeSendDialog(
  BuildContext context, {
  required FormIntakeContext intakeContext,
  required List<int> package,
  IntakeRespondentClient Function(String baseUrl)? clientFor,
}) => showDialog<FormIntakeContext>(
  context: context,
  builder: (_) => FormIntakeSendDialog(
    intakeContext: intakeContext,
    package: package,
    clientFor:
        clientFor ?? (baseUrl) => IntakeRespondentClient(baseUrl: baseUrl),
  ),
);

class FormIntakeSendDialog extends StatefulWidget {
  const FormIntakeSendDialog({
    super.key,
    required this.intakeContext,
    required this.package,
    required this.clientFor,
  });

  final FormIntakeContext intakeContext;

  /// Het gebouwde inzendpakket — dezelfde bytes als "opslaan als zip".
  final List<int> package;

  final IntakeRespondentClient Function(String baseUrl) clientFor;

  @override
  State<FormIntakeSendDialog> createState() => _FormIntakeSendDialogState();
}

class _FormIntakeSendDialogState extends State<FormIntakeSendDialog> {
  _Step _step = _Step.loading;
  IntakePublicForm? _form;
  IntakeGrant? _grant;
  IntakeRespondentSubmission? _submission;
  IntakeSubmitReceipt? _receipt;
  String? _error;
  String? _notice;

  /// Of de lopende challenge voor intrekken is; bepaalt waar [onGrant]
  /// naartoe gaat.
  bool _withdrawing = false;
  late final IntakeRespondentClient _client = widget.clientFor(
    widget.intakeContext.baseUrl,
  );

  FormIntakeContext get _context => widget.intakeContext;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final form = await _client.publicForm(_context.formRef);
      if (!mounted) return;
      setState(() {
        _form = form;
        _step = _Step.intro;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorFor(error);
        _step = _Step.intro;
      });
    }
  }

  /// Welke challenge-purpose de verzendweg vraagt (§6.4): een nieuwe
  /// inzending start, een open correctieronde corrigeert, al het andere is
  /// hervatten.
  IntakePurpose get _purpose =>
      switch ((_context.locator, _context.lastState)) {
        (null, _) => IntakePurpose.start,
        (_, IntakeSubmissionState.correctionOpen) => IntakePurpose.correct,
        _ => IntakePurpose.resume,
      };

  void _startChallenge({required bool withdraw}) => setState(() {
    _withdrawing = withdraw;
    _step = _Step.challenge;
    _error = null;
  });

  Future<void> _onGrant(IntakeGrant grant) async {
    if (_withdrawing) {
      setState(() {
        _grant = grant;
        _step = _Step.confirmWithdraw;
      });
      return;
    }
    setState(() {
      _grant = grant;
      _step = _Step.working;
      _notice = null;
    });
    try {
      final fetched = await _client.submission(grant: grant);
      final submission = fetched?.value;
      if (!mounted) return;
      if (submission == null ||
          submission.state == IntakeSubmissionState.withdrawn ||
          !submission.allowedActions.contains(IntakeAllowedAction.submit)) {
        setState(() {
          _submission = submission;
          _error = context.l10n.d(
            'Deze inzending kan nu niet worden verstuurd — hij is gesloten, ingetrokken of er loopt geen correctieronde. Je werk staat veilig in dit bestand; sla het op als zip om het mee te sturen.',
          );
          _step = _Step.intro;
        });
        return;
      }
      setState(() {
        _submission = submission;
        _step = _Step.confirm;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorFor(error);
        _step = _Step.intro;
      });
    }
  }

  Future<void> _submit() async {
    final grant = _grant;
    if (grant == null || _step == _Step.working) return;
    setState(() {
      _step = _Step.working;
      _notice = context.l10n.d('Het pakket wordt verstuurd…');
      _error = null;
    });
    try {
      await _client.putDraft(grant: grant, bytes: widget.package);
      if (!mounted) return;
      setState(
        () => _notice = context.l10n.d('De inzending wordt vastgelegd…'),
      );
      final receipt = await _client.submit(
        grant: grant,
        idempotencyKey: const Uuid().v4(),
        expectedSha256: sha256.convert(widget.package).toString(),
        expectedSize: widget.package.length,
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _notice = null;
        _step = _Step.done;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = null;
        _error = _errorFor(error);
        _step = _Step.intro;
      });
    }
  }

  Future<void> _withdraw() async {
    final grant = _grant;
    if (grant == null || _step == _Step.working) return;
    setState(() {
      _step = _Step.working;
      _notice = context.l10n.d('De inzending wordt ingetrokken…');
      _error = null;
    });
    try {
      await _client.withdraw(grant: grant, idempotencyKey: const Uuid().v4());
      if (!mounted) return;
      setState(() {
        _notice = null;
        _step = _Step.done;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = null;
        _error = _errorFor(error);
        _step = _Step.intro;
      });
    }
  }

  /// De zin bij een mislukte netwerkstap — herstelbaar benoemd, nooit HTTP.
  String _errorFor(Object error) {
    final l10n = context.l10n;
    if (error is OciServeException) {
      return switch (error.code) {
        'unauthorized' => l10n.d(
          'De toegang is verlopen. Vraag via de terugkeerlink een nieuwe code aan; je werk staat veilig in dit bestand.',
        ),
        'package_too_large' => l10n.d(
          'Het pakket is te groot om te versturen. Haal een foto weg en probeer het opnieuw — of sla het op als zip en stuur dat mee.',
        ),
        'intake_digest_mismatch' => l10n.d(
          'De server ontving niet precies wat er verstuurd is. Er is niets vastgelegd; probeer het opnieuw.',
        ),
        'invalid_response' => l10n.d(
          'De server antwoordde iets onverwachts. Er is niets vastgelegd; probeer het later opnieuw.',
        ),
        'unavailable' || 'network_error' => l10n.d(
          'De server is nu niet bereikbaar. Er is niets verstuurd — je werk staat veilig in dit bestand.',
        ),
        'rate_limited' => l10n.d(
          'Te veel pogingen achter elkaar. Wacht even en probeer het opnieuw.',
        ),
        _ => l10n.d(
          'Versturen lukte niet. Er is niets vastgelegd — je werk staat veilig in dit bestand; sla het op als zip om het mee te sturen.',
        ),
      };
    }
    return l10n.d(
      'Versturen lukte niet. Er is niets vastgelegd — je werk staat veilig in dit bestand; sla het op als zip om het mee te sturen.',
    );
  }

  /// De context zoals die na dit venster geldt: de uitstaande
  /// challenge/grant blijft binnen; locator, revisie en toestand gaan mee.
  FormIntakeContext get _result => switch ((_receipt, _step)) {
    (final receipt?, _) => _context.copyWith(
      locator: _grant?.locator,
      revision: receipt.revision,
      lastState: IntakeSubmissionState.submitted,
    ),
    (null, _Step.done) => _context.copyWith(
      locator: _grant?.locator,
      lastState: IntakeSubmissionState.withdrawn,
    ),
    _ when _submission != null => _context.copyWith(
      locator: _grant?.locator ?? _context.locator,
      lastState: _submission!.state,
    ),
    _ => _context.copyWith(locator: _grant?.locator ?? _context.locator),
  };

  void _close() => Navigator.of(context).pop(_result);

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
                    l10n.d('Verzenden via OciServe'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                ..._body(l10n, theme),
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Semantics(liveRegion: true, child: Text(_notice!)),
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
                      onPressed: _step == _Step.working ? null : _close,
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

  List<Widget> _body(AppLocalizations l10n, ThemeData theme) {
    final form = _form;
    return switch (_step) {
      _Step.loading => [const LinearProgressIndicator()],
      _Step.intro => [
        Text(
          l10n
              .d('Bestemming: {server}')
              .replaceAll('{server}', _context.baseUrl),
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
          Text(
            l10n
                .d('Bewaren: {dagen} dagen na indienen.')
                .replaceAll(
                  '{dagen}',
                  '${form.snapshot.retentionSubmittedDays}',
                ),
          ),
          if (!form.accepting)
            Text(
              l10n.d('Dit formulier neemt nu geen nieuwe inzendingen aan.'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          const SizedBox(height: 8),
        ],
        if (form == null && _error != null)
          Text(
            l10n.d(
              'Het formulier kon niet worden opgehaald. Je kunt je werk alsnog opslaan als zip.',
            ),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'Er wordt pas iets verstuurd als je hieronder bevestigt. Opslaan als zipbestand blijft altijd mogelijk.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (form != null && form.accepting)
              FilledButton(
                onPressed: () => _startChallenge(withdraw: false),
                child: Text(
                  _context.locator == null
                      ? l10n.d('Insturen…')
                      : _context.lastState ==
                            IntakeSubmissionState.correctionOpen
                      ? l10n.d('Correctie insturen…')
                      : l10n.d('Inzending bijwerken…'),
                ),
              ),
            if (_context.locator != null)
              OutlinedButton(
                onPressed: () => _startChallenge(withdraw: true),
                child: Text(l10n.d('Inzending intrekken…')),
              ),
          ],
        ),
      ],
      _Step.challenge => [
        IntakeChallengeFlow(
          client: _client,
          purpose: _withdrawing ? IntakePurpose.withdraw : _purpose,
          formRef: _context.formRef,
          locator: _context.locator ?? _grant?.locator,
          onGrant: _onGrant,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _step = _Step.intro),
          child: Text(l10n.d('Terug')),
        ),
      ],
      _Step.confirm => [
        Text(
          l10n
              .d(
                'Dit wordt revisie {n} van je inzending op {server}. Na het insturen kun je hem niet meer aanpassen — een fout herstel je met een nieuwe correctieronde.',
              )
              .replaceAll('{n}', '${(_submission?.revision ?? 0) + 1}')
              .replaceAll('{server}', _context.baseUrl),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.d('Definitief insturen')),
        ),
      ],
      _Step.confirmWithdraw => [
        Text(
          l10n.d(
            'Intrekken haalt je inzending weg bij de organisator en kan niet ongedaan worden gemaakt. Wil je doorgaan?',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _withdraw,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
          ),
          child: Text(l10n.d('Inzending intrekken')),
        ),
      ],
      _Step.working => [const SizedBox.shrink()],
      _Step.done => [
        if (_receipt != null) ...[
          Text(
            l10n
                .d('Verstuurd als revisie {n}.')
                .replaceAll('{n}', '${_receipt!.revision}'),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.d(
              'Je krijgt een terugkeerlink per mail. Die link opent je inzending alleen samen met een nieuwe code — de link alleen is geen sleutel.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ] else ...[
          Text(l10n.d('Je inzending is ingetrokken.')),
        ],
      ],
    };
  }
}
