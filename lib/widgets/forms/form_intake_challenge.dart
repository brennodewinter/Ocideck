// De mailboxuitdaging die elke respondentactie voorafgaat (FORM_INTAKE.md §6.4):
// e-mailadres → de server mailt een eenmalige code → de code levert een
// kortlevende IntakeGrant. Wordt gedeeld door versturen, hervatten en
// intrekken — drie doelen, één scherm.
//
// Wat hier bewust níét gebeurt: de code gaat nergens heen behalve naar de
// server (geen log, geen bestand, geen opslag), en een mislukte poging zegt
// neutraal "dat lukte niet" — of het adres bestaat is niemands zaak.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_intake.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../services/ociserve/ociserve_intake_respondent.dart';

class IntakeChallengeFlow extends StatefulWidget {
  const IntakeChallengeFlow({
    super.key,
    required this.client,
    required this.purpose,
    required this.onGrant,
    this.formRef,
    this.locator,
  });

  final IntakeRespondentClient client;
  final IntakePurpose purpose;

  /// Voor [IntakePurpose.start]: het formulier dat de challenge betreft.
  final String? formRef;

  /// Voor de andere doelen: de inzending die de challenge betreft.
  final String? locator;

  /// De code klopte: [grant] is het bewijs voor de volgende stap.
  final void Function(IntakeGrant grant) onGrant;

  @override
  State<IntakeChallengeFlow> createState() => IntakeChallengeFlowState();
}

class IntakeChallengeFlowState extends State<IntakeChallengeFlow> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  IntakeChallenge? _challenge;
  bool _busy = false;
  String? _error;

  /// Tot wanneer "opnieuw sturen" wacht, zoals de server voorschrijft.
  DateTime? _resendAfter;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// De zin bij een mislukte stap. Voor de challenge en de code geldt dezelfde
  /// neutrale tekst: niets over bestaan of niet (§6.4).
  String _errorFor(Object error) {
    final l10n = context.l10n;
    if (error is OciServeException) {
      return switch (error.code) {
        'unavailable' || 'network_error' => l10n.d(
          'De server is nu niet bereikbaar. Probeer het later opnieuw; er is niets verstuurd.',
        ),
        'rate_limited' => l10n.d(
          'Te veel pogingen achter elkaar. Wacht even en probeer het opnieuw.',
        ),
        'invalid_request' => l10n.d(
          'Dit adres of deze code klopt niet zo. Controleer het en probeer het opnieuw.',
        ),
        _ => l10n.d(
          'Dat lukte niet. Er is niets verstuurd — probeer het opnieuw.',
        ),
      };
    }
    return l10n.d(
      'Dat lukte niet. Er is niets verstuurd — probeer het opnieuw.',
    );
  }

  Future<void> _request() async {
    final email = _email.text.trim();
    if (email.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await widget.client.requestChallenge(
        purpose: widget.purpose,
        email: email,
        formRef: widget.formRef,
        locator: widget.locator,
      );
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _busy = false;
        _resendAfter = DateTime.now().add(challenge.resendAfter);
      });
      _codeFocus.requestFocus();
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_resendAfter != null && DateTime.now().isAfter(_resendAfter!)) {
          _tick?.cancel();
        }
        setState(() {});
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorFor(error);
      });
    }
  }

  Future<void> _verify() async {
    final challenge = _challenge;
    if (challenge == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final grant = await widget.client.verifyChallenge(
        challengeId: challenge.challengeId,
        code: _code.text,
      );
      // De code is verbruikt: uit het veld en uit het geheugen van het
      // scherm, zodat er niets achterblijft om per ongeluk te bewaren.
      _code.clear();
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onGrant(grant);
    } on Object catch (error) {
      _code.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorFor(error);
      });
    }
  }

  bool get _resendWaiting =>
      _resendAfter != null && DateTime.now().isBefore(_resendAfter!);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.d(
            'Je e-mailadres bewijst alleen dat je bij de mailbox kunt — het is geen account en er wordt niets verstuurd voordat je zelf bevestigt.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          onSubmitted: (_) => _request(),
          decoration: InputDecoration(
            labelText: l10n.d('Je e-mailadres'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: _busy || _resendWaiting ? null : _request,
              child: Text(
                _challenge == null
                    ? l10n.d('Code aanvragen')
                    : l10n.d('Opnieuw versturen'),
              ),
            ),
            if (_challenge != null && _resendWaiting)
              Text(
                l10n
                    .d('Opnieuw versturen kan over {seconden} seconden.')
                    .replaceAll(
                      '{seconden}',
                      '${_resendAfter!.difference(DateTime.now()).inSeconds + 1}',
                    ),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        if (_challenge != null) ...[
          const SizedBox(height: 16),
          Text(
            l10n.d(
              'Er is een code onderweg naar dat adres (ook als het adres niet bestaat — dat hoor je hier niet).',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            focusNode: _codeFocus,
            enabled: !_busy,
            // Geen autofill, geen suggesties: de code komt uit de mail en
            // wordt verder nergens bewaard of aangeboden.
            autofillHints: const [],
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.text,
            onSubmitted: (_) => _verify(),
            decoration: InputDecoration(
              labelText: l10n.d('Code uit de e-mail'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _verify,
            child: Text(l10n.d('Code controleren')),
          ),
        ],
        if (_busy) ...[
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
      ],
    );
  }
}
