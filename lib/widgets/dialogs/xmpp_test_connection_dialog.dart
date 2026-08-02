// The "test XMPP connection" dialog (F2, `NATIVE_CALLS.md` §5): the first
// consumer of the XMPP connection layer, and the thing that makes it reachable
// from the app. The user enters a server, a Jabber-ID and a password; pressing
// test opens a NetGuard-pinned wss stream and authenticates (SASL), then shows
// whether it worked. Nothing is stored — this only proves the account works, the
// groundwork the real calls path (F3) builds on.
//
// The connection call is injectable so the widget test drives it without a socket;
// the failure code is mapped to a translated message here (the connection layer
// carries no l10n).

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/xmpp_settings.dart';
import '../../theme/app_theme.dart';
import '../../xmpp/xmpp_connection.dart';
import '../../xmpp/xmpp_frame_transport.dart';
import '../../xmpp/xmpp_frame_transport_platform.dart';

/// Opens a guarded wss stream to [settings] and authenticates. Injected in tests.
typedef XmppConnectTest =
    Future<XmppAuthResult> Function(XmppSettings settings, String password);

Future<XmppAuthResult> _liveConnectTest(
  XmppSettings settings,
  String password,
) async {
  final XmppFrameTransport transport;
  try {
    transport = await openXmppFrameTransport(settings);
  } on XmppConnectException catch (e) {
    return XmppAuthResult.failed(
      XmppAuthFailure.transportRefused,
      detail: e.message,
    );
  }
  return XmppConnection(
    transport: transport,
    settings: settings,
    password: password,
  ).authenticate();
}

class XmppTestConnectionDialog extends StatefulWidget {
  const XmppTestConnectionDialog({super.key, this.connect = _liveConnectTest});

  final XmppConnectTest connect;

  @override
  State<XmppTestConnectionDialog> createState() =>
      _XmppTestConnectionDialogState();
}

class _XmppTestConnectionDialogState extends State<XmppTestConnectionDialog> {
  final _server = TextEditingController();
  final _jid = TextEditingController();
  final _password = TextEditingController();
  bool _testing = false;
  XmppAuthResult? _result;

  @override
  void dispose() {
    _server.dispose();
    _jid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final settings = XmppSettings(
      serverUrl: _server.text.trim(),
      jid: _jid.text.trim(),
    );
    final result = await widget.connect(settings, _password.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('XMPP-server testen')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Voer een XMPP-server, een Jabber-ID en een wachtwoord in en test de verbinding. Er wordt niets bewaard; dit controleert alleen of het account werkt. Laat de Jabber-ID leeg voor anonieme toegang.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _server,
              decoration: InputDecoration(
                labelText: l10n.d('Serveradres (wss://…)'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _jid,
              decoration: InputDecoration(
                labelText: l10n.d('Jabber-ID (gebruiker@domein)'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.d('Wachtwoord')),
            ),
            if (_result != null) ...[
              const SizedBox(height: 14),
              _ResultLine(l10n: l10n, result: _result!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
        FilledButton(
          onPressed: _testing ? null : _test,
          child: Text(
            _testing ? l10n.d('Verbinden…') : l10n.d('Verbinding testen'),
          ),
        ),
      ],
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.l10n, required this.result});

  final AppLocalizations l10n;
  final XmppAuthResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.ok;
    final color = ok ? AppTheme.successFg : AppTheme.dangerFg;
    final text = ok
        ? '${l10n.d('Verbonden — authenticatie geslaagd via')} ${result.mechanism}'
        : _failureText(l10n, result.failure!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    );
  }
}

String _failureText(AppLocalizations l10n, XmppAuthFailure failure) =>
    switch (failure) {
      XmppAuthFailure.noUsableMechanism => l10n.d(
        'De server biedt geen inlogmethode die OciDeck ondersteunt.',
      ),
      XmppAuthFailure.badCredentials => l10n.d(
        'De gebruikersnaam of het wachtwoord werd niet geaccepteerd.',
      ),
      XmppAuthFailure.mutualAuthFailed => l10n.d(
        'De server kon zich niet bewijzen (wederzijdse verificatie mislukt).',
      ),
      XmppAuthFailure.serverRedirect => l10n.d(
        'De server wilde de verbinding omleiden naar een andere host; geweigerd.',
      ),
      XmppAuthFailure.timeout => l10n.d('De server reageerde niet op tijd.'),
      XmppAuthFailure.transportRefused => l10n.d(
        'Kon geen verbinding maken met de server. Gebruik wss:// en een geldig adres.',
      ),
      XmppAuthFailure.serverError ||
      XmppAuthFailure.streamClosed ||
      XmppAuthFailure.handshake => l10n.d('De verbinding met de server mislukte.'),
    };
