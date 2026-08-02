// The "test XMPP connection" dialog (F2/F3, `NATIVE_CALLS.md` §5): the first
// consumer of the XMPP client, and the thing that makes it reachable from the
// app. The user enters a server, a Jabber-ID and a password; pressing test opens
// a NetGuard-pinned wss stream, authenticates (SASL) and binds a resource. If a
// room JID is given, it also joins that MUC (XEP-0045) and reports who is present,
// then leaves. Nothing is stored, and the session is closed again right away —
// this only proves the account (and, optionally, a room) works, the groundwork
// the real calls path (F3 Jingle) builds on.
//
// The connection call is injectable so the widget test drives it without a socket;
// the failure codes are mapped to translated messages here (the session and MUC
// layers carry no l10n).

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/xmpp_settings.dart';
import '../../theme/app_theme.dart';
import '../../xmpp/xmpp_frame_transport.dart';
import '../../xmpp/xmpp_frame_transport_platform.dart';
import '../../xmpp/xmpp_muc.dart';
import '../../xmpp/xmpp_session.dart';

/// The result of a test: the session outcome, plus — if a room was given — who
/// was present (nicks) or why joining failed.
class XmppTestOutcome {
  const XmppTestOutcome({required this.result, this.occupants, this.joinFailure});
  final XmppSessionResult result;

  /// Room nicks, non-null iff a room was joined successfully.
  final List<String>? occupants;

  /// Non-null iff joining the given room failed.
  final MucJoinFailure? joinFailure;
}

/// Opens a guarded wss session to [settings], binds a resource, optionally joins
/// [room], and closes everything again. Injected in tests.
typedef XmppConnectTest =
    Future<XmppTestOutcome> Function(
      XmppSettings settings,
      String password,
      String? room,
    );

Future<XmppTestOutcome> _liveConnectTest(
  XmppSettings settings,
  String password,
  String? room,
) async {
  final XmppFrameTransport transport;
  try {
    transport = await openXmppFrameTransport(settings);
  } on XmppConnectException catch (e) {
    return XmppTestOutcome(
      result: XmppSessionResult.failed(
        XmppSessionFailure.transportRefused,
        detail: e.message,
      ),
    );
  }
  final session = XmppSession(
    transport: transport,
    settings: settings,
    password: password,
  );
  final result = await session.connect();
  final trimmedRoom = room?.trim() ?? '';
  if (!result.ok || trimmedRoom.isEmpty) {
    await session.close();
    return XmppTestOutcome(result: result);
  }
  final muc = XmppMuc(
    channel: session,
    roomJid: trimmedRoom,
    nick: _nickFrom(result.boundJid),
  );
  final joinResult = await muc.join();
  final occupants = joinResult.ok
      ? muc.roster.map((o) => o.nick).toList()
      : null;
  await muc.leave();
  await session.close();
  return XmppTestOutcome(
    result: result,
    occupants: occupants,
    joinFailure: joinResult.failure,
  );
}

/// The room nick to enter with: the account localpart, or a fallback for an
/// anonymous login with no localpart of its own.
String _nickFrom(String? boundJid) {
  if (boundJid == null) return 'ocideck';
  final at = boundJid.indexOf('@');
  final local = at > 0 ? boundJid.substring(0, at) : '';
  return local.isEmpty ? 'ocideck' : local;
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
  final _room = TextEditingController();
  bool _testing = false;
  XmppTestOutcome? _outcome;

  @override
  void dispose() {
    _server.dispose();
    _jid.dispose();
    _password.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _outcome = null;
    });
    final settings = XmppSettings(
      serverUrl: _server.text.trim(),
      jid: _jid.text.trim(),
    );
    final outcome = await widget.connect(
      settings,
      _password.text,
      _room.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true, // four fields plus a multi-line result can be tall
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
            const SizedBox(height: 8),
            TextField(
              controller: _room,
              decoration: InputDecoration(
                labelText: l10n.d('Kamer testen (optioneel): kamer@service'),
              ),
            ),
            if (_outcome != null) ...[
              const SizedBox(height: 14),
              _OutcomeView(l10n: l10n, outcome: _outcome!),
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

class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.l10n, required this.outcome});

  final AppLocalizations l10n;
  final XmppTestOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final result = outcome.result;
    final ok = result.ok;
    final color = ok ? AppTheme.successFg : AppTheme.dangerFg;
    final sessionText = ok
        ? '${l10n.d('Verbonden — authenticatie geslaagd via')} ${result.mechanism}'
              '\n${l10n.d('Sessie actief als')} ${result.boundJid}'
        : _failureText(l10n, result.failure!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(ok ? Icons.check_circle_outline : Icons.error_outline, color,
            sessionText),
        if (outcome.occupants != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _line(
              Icons.groups_outlined,
              AppTheme.slate600,
              '${l10n.d('Aanwezig in de kamer')}: ${outcome.occupants!.join(', ')}',
            ),
          ),
        if (outcome.joinFailure != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _line(
              Icons.error_outline,
              AppTheme.dangerFg,
              _joinFailureText(l10n, outcome.joinFailure!),
            ),
          ),
      ],
    );
  }

  Widget _line(IconData icon, Color color, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
      ),
    ],
  );
}

String _failureText(AppLocalizations l10n, XmppSessionFailure failure) =>
    switch (failure) {
      XmppSessionFailure.noUsableMechanism => l10n.d(
        'De server biedt geen inlogmethode die OciDeck ondersteunt.',
      ),
      XmppSessionFailure.badCredentials => l10n.d(
        'De gebruikersnaam of het wachtwoord werd niet geaccepteerd.',
      ),
      XmppSessionFailure.mutualAuthFailed => l10n.d(
        'De server kon zich niet bewijzen (wederzijdse verificatie mislukt).',
      ),
      XmppSessionFailure.serverRedirect => l10n.d(
        'De server wilde de verbinding omleiden naar een andere host; geweigerd.',
      ),
      XmppSessionFailure.resourceBindFailed => l10n.d(
        'Ingelogd, maar de server kon geen sessie opzetten (resource-binding mislukt).',
      ),
      XmppSessionFailure.timeout => l10n.d('De server reageerde niet op tijd.'),
      XmppSessionFailure.transportRefused => l10n.d(
        'Kon geen verbinding maken met de server. Gebruik wss:// en een geldig adres.',
      ),
      XmppSessionFailure.serverError || XmppSessionFailure.handshake => l10n.d(
        'De verbinding met de server mislukte.',
      ),
    };

String _joinFailureText(AppLocalizations l10n, MucJoinFailure failure) =>
    switch (failure) {
      MucJoinFailure.nickConflict => l10n.d(
        'De bijnaam is al in gebruik in de kamer.',
      ),
      MucJoinFailure.membersOnly => l10n.d(
        'Deze kamer is alleen voor leden.',
      ),
      MucJoinFailure.passwordRequired => l10n.d(
        'Deze kamer vereist een wachtwoord.',
      ),
      MucJoinFailure.timeout => l10n.d('De server reageerde niet op tijd.'),
      MucJoinFailure.banned ||
      MucJoinFailure.roomFull ||
      MucJoinFailure.notAllowed ||
      MucJoinFailure.sessionClosed => l10n.d('De kamer kon niet worden betreden.'),
    };
