import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';

/// De uitnodigingsreis (#2425): serveradres + uitnodigingsnummer + eenmalige
/// code, dan naam en wachtwoord voor een nieuwe identiteit, en tot slot de
/// PKCE-aanmelding met `login_hint` + `prompt=login` zodat geen sessie van
/// de uitnodiger wordt hergebruikt.
///
/// Twee toetreders: niet-aangemeld = registreren; aangemeld = accepteren met
/// het bestaande account (extra organisatie erbij).
///
/// Het wachtwoord leeft alleen in de invoervelden en gaat na de aanroep leeg;
/// de uitnodigingscode gaat nooit in een URL, bestand of logregel.
class OciServeInvitationDialog extends ConsumerStatefulWidget {
  const OciServeInvitationDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: OciServeInvitationDialog(),
        ),
      ),
    );
  }

  @override
  ConsumerState<OciServeInvitationDialog> createState() =>
      _OciServeInvitationDialogState();
}

enum _InvitationStep { codes, credentials, signingIn, done }

class _OciServeInvitationDialogState
    extends ConsumerState<OciServeInvitationDialog> {
  final _server = TextEditingController();
  final _invitationId = TextEditingController();
  final _secret = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();

  /// Eén sleutel voor de hele schermsessie: dubbelklikken en een netwerk-
  /// hik met retry geven nooit een tweede account.
  final _idempotencyKey = const Uuid().v4();

  var _step = _InvitationStep.codes;
  var _busy = false;
  var _passwordVisible = false;
  String? _error;
  String _invitedEmail = '';

  @override
  void initState() {
    super.initState();
    _server.text = ref.read(ociServeProvider).settings.baseUrl;
  }

  @override
  void dispose() {
    // Het wachtwoord wordt gewist, niet bewaard — ook niet via een controller
    // die nog ergens in een listener achterblijft.
    _password.clear();
    _passwordConfirm.clear();
    _server.dispose();
    _invitationId.dispose();
    _secret.dispose();
    _displayName.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  bool get _acceptOnly => ref.read(ociServeProvider).authenticated;

  void _fail(String message) => setState(() {
    _busy = false;
    _error = message;
  });

  String _errorText(AppLocalizations l10n, Object error) {
    if (error is OciServeException) {
      if (error.statusCode == 429) {
        return l10n.d(
          'Te veel pogingen. Wacht even en probeer het dan opnieuw.',
        );
      }
      if (error.statusCode == 400) {
        return l10n.d(
          'De combinatie van uitnodigingsnummer en code klopt niet, of de uitnodiging is verlopen of al gebruikt.',
        );
      }
    }
    return l10n.d('Dat is niet gelukt. Probeer het opnieuw.');
  }

  /// Stap 1: server opslaan en de uitnodiging controleren. Alleen een geldige
  /// combinatie levert het uitgenodigde adres op — de server bevestigt
  /// bewust niets anders.
  Future<void> _checkInvitation() async {
    final l10n = context.l10n;
    final notifier = ref.read(ociServeProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Aangemeld accepteren vraagt geen publieke preview — de acceptatie zelf
      // is dezelfde generieke fout als een ongeldige combinatie.
      if (_acceptOnly) {
        await _accept();
        return;
      }
      await notifier.saveSettings(
        ref.read(ociServeProvider).settings.copyWith(baseUrl: _server.text),
      );
      final email = await notifier.previewInvitation(
        invitationId: _invitationId.text.trim(),
        secret: _secret.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _invitedEmail = email;
        _step = _InvitationStep.credentials;
        _busy = false;
      });
    } catch (error, stack) {
      logError('OciServe: uitnodiging controleren', error.runtimeType, stack);
      if (mounted) _fail(_errorText(l10n, error));
    }
  }

  /// Stap 2: registreren (nieuwe identiteit). Daarna meteen aanmelden; lukt
  /// de browser niet open, dan blijft een handmatige Aanmelden-knop — de
  /// registratie herhalen we nooit automatisch.
  Future<void> _register() async {
    final l10n = context.l10n;
    final password = _password.text;
    if (password.length < 12) {
      _fail(l10n.d('Kies een wachtwoord van minstens 12 tekens.'));
      return;
    }
    if (password != _passwordConfirm.text) {
      _fail(l10n.d('De wachtwoorden zijn niet hetzelfde.'));
      return;
    }
    if (_displayName.text.trim().isEmpty) {
      _fail(l10n.d('Vul uw naam in.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ociServeProvider.notifier)
          .registerInvitation(
            invitationId: _invitationId.text.trim(),
            secret: _secret.text.trim(),
            displayName: _displayName.text.trim(),
            password: password,
            idempotencyKey: _idempotencyKey,
          );
      _password.clear();
      _passwordConfirm.clear();
      if (!mounted) return;
      await _signIn();
    } catch (error, stack) {
      logError('OciServe: uitnodiging registreren', error.runtimeType, stack);
      if (mounted) _fail(_errorText(l10n, error));
    }
  }

  /// Stap 3: de PKCE-aanmelding met het uitgenodigde adres als hint en een
  /// verse aanmelding (geen hergebruikte sessie). Mag handmatig opnieuw —
  /// het is inloggen, geen registratie.
  Future<void> _signIn() async {
    final l10n = context.l10n;
    setState(() {
      _step = _InvitationStep.signingIn;
      _error = null;
      _busy = true;
    });
    try {
      final ok = await ref
          .read(ociServeProvider.notifier)
          .login(loginHint: _invitedEmail, forceLogin: true);
      if (!mounted) return;
      if (ok) {
        setState(() => _step = _InvitationStep.done);
      } else {
        _fail(
          l10n.d('Aanmelden is niet gelukt. Probeer het hieronder opnieuw.'),
        );
      }
    } catch (error, stack) {
      logError('OciServe: aanmelden na registratie', error.runtimeType, stack);
      if (mounted) {
        _fail(
          l10n.d('Aanmelden is niet gelukt. Probeer het hieronder opnieuw.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// De aangemelde variant: uitnodiging toevoegen aan het bestaande account.
  Future<void> _accept() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ociServeProvider.notifier)
          .acceptInvitation(
            invitationId: _invitationId.text.trim(),
            secret: _secret.text.trim(),
            displayName: null,
            idempotencyKey: _idempotencyKey,
          );
      if (!mounted) return;
      setState(() => _step = _InvitationStep.done);
    } catch (error, stack) {
      logError('OciServe: uitnodiging accepteren', error.runtimeType, stack);
      if (mounted) _fail(_errorText(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = AppPalette.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mail_outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.d('Uitnodiging gebruiken'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.t('cancel'),
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_step == _InvitationStep.codes) ..._codesStep(l10n),
            if (_step == _InvitationStep.credentials)
              ..._credentialsStep(l10n, palette),
            if (_step == _InvitationStep.signingIn)
              ..._signingInStep(l10n, palette),
            if (_step == _InvitationStep.done) ..._doneStep(l10n),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Stap 1: server (alleen voor nieuwe deelnemers), uitnodigingsnummer en
  /// code — daarmee haalt de preview op wie de uitnodiging betreft.
  List<Widget> _codesStep(AppLocalizations l10n) => [
    if (!_acceptOnly)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _server,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.d('eLearning-server'),
            hintText: l10n.d('https://leren.example.org'),
            isDense: true,
          ),
        ),
      ),
    TextField(
      controller: _invitationId,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: l10n.d('Uitnodigingsnummer'),
        isDense: true,
      ),
    ),
    const SizedBox(height: 10),
    TextField(
      controller: _secret,
      autocorrect: false,
      obscureText: true,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: l10n.d('Uitnodigingscode'),
        isDense: true,
      ),
    ),
    const SizedBox(height: 14),
    FilledButton(
      onPressed: _busy ? null : _checkInvitation,
      child: Text(_busy ? l10n.d('Bezig…') : l10n.d('Doorgaan')),
    ),
  ];

  /// Stap 2 (nieuwe deelnemer): naam en tweemaal wachtwoord voor de
  /// registratie. Het uitgenodigde adres staat erboven ter controle.
  List<Widget> _credentialsStep(AppLocalizations l10n, AppPalette palette) => [
    Text(
      l10n
          .d('Deze uitnodiging hoort bij {adres}.')
          .replaceAll('{adres}', _invitedEmail),
      style: TextStyle(color: palette.mutedText, fontSize: 12.5),
    ),
    const SizedBox(height: 10),
    TextField(
      controller: _displayName,
      autocorrect: true,
      decoration: InputDecoration(labelText: l10n.d('Uw naam'), isDense: true),
    ),
    const SizedBox(height: 10),
    _passwordField(l10n, _password, l10n.d('Wachtwoord')),
    const SizedBox(height: 10),
    _passwordField(l10n, _passwordConfirm, l10n.d('Wachtwoord herhalen')),
    const SizedBox(height: 14),
    FilledButton(
      onPressed: _busy ? null : _register,
      child: Text(
        _busy ? l10n.d('Bezig…') : l10n.d('Registreren en aanmelden'),
      ),
    ),
  ];

  /// Stap 3: na een geslaagde registratie meldt de deelnemer zich expliciet
  /// aan met de nieuwe inlog — die loopt met login_hint zodat een eventuele
  /// sessie van de uitnodiger niet stilletjes wordt hergebruikt.
  List<Widget> _signingInStep(AppLocalizations l10n, AppPalette palette) => [
    Text(
      l10n.d(
        'Uw account is aangemaakt. Meld u nu aan met het uitgenodigde adres en uw nieuwe wachtwoord.',
      ),
      style: TextStyle(color: palette.mutedText, fontSize: 12.5),
    ),
    const SizedBox(height: 14),
    FilledButton.icon(
      onPressed: _busy ? null : _signIn,
      icon: _busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login, size: 18),
      label: Text(l10n.d('Aanmelden')),
    ),
  ];

  /// Stap 4: gereed — bij acceptatie alleen sluiten, bij registratie is de
  /// deelnemer dan al aangemeld.
  List<Widget> _doneStep(AppLocalizations l10n) => [
    Row(
      children: [
        Icon(Icons.check_circle_outline, color: AppTheme.accentFg),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _acceptOnly
                ? l10n.d(
                    'De uitnodiging is geaccepteerd. De organisatie staat nu bij uw account.',
                  )
                : l10n.d('U bent geregistreerd en aangemeld. Welkom!'),
          ),
        ),
      ],
    ),
    const SizedBox(height: 14),
    FilledButton(
      onPressed: () => Navigator.pop(context),
      child: Text(l10n.d('Sluiten')),
    ),
  ];

  /// Wachtwoordveld met zichtbaarheidsknop en zonder autofill: het wachtwoord
  /// mag nergens belanden waar het niet voor bedoeld is.
  Widget _passwordField(
    AppLocalizations l10n,
    TextEditingController controller,
    String label,
  ) => TextField(
    controller: controller,
    obscureText: !_passwordVisible,
    enableSuggestions: false,
    autocorrect: false,
    autofillHints: const [],
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      suffixIcon: IconButton(
        tooltip: _passwordVisible
            ? l10n.d('Wachtwoord verbergen')
            : l10n.d('Wachtwoord tonen'),
        icon: Icon(
          _passwordVisible ? Icons.visibility_off : Icons.visibility,
          size: 18,
        ),
        onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
      ),
    ),
  );
}
