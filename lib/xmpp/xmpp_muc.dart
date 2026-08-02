// XEP-0045 Multi-User Chat, on top of a live [XmppStanzaChannel] (F3,
// `NATIVE_CALLS.md` §5.1). A room is entered by sending a `<presence>` to
// `room@service/nick`; the server answers with one presence per existing
// occupant and, last, our own — the self-presence (status code 110) that
// confirms the join. Occupants are tracked from these presences (available adds/
// updates, `unavailable` removes), and exposed as a live [occupants] roster.
//
// This is the primitive both native-calls rooms ride: the Jitsi conference MUC
// (media occupants) and OciDeck's own companion MUC (§5.1, where OciDeck users
// discover each other). It carries no media and no OciDeck control payload — only
// presence/roster — so it stays a thin, testable XEP-0045 layer over the session.
//
// It depends on the channel INTERFACE, not on `XmppSession`, so the join logic is
// unit-tested against a scripted fake channel — no socket, no real session.

import 'dart:async';

import 'package:xml/xml.dart';

import 'xmpp_session.dart' show XmppStanzaChannel;
import 'xmpp_stanza.dart';

const _mucNs = 'http://jabber.org/protocol/muc';
const _mucUserNs = 'http://jabber.org/protocol/muc#user';

/// An occupant's long-term standing in the room (XEP-0045 §5.2).
enum MucAffiliation { owner, admin, member, outcast, none }

/// An occupant's current in-room role (XEP-0045 §5.1).
enum MucRole { moderator, participant, visitor, none }

/// One occupant of a joined room, as last seen in its presence.
class MucOccupant {
  const MucOccupant({
    required this.nick,
    required this.affiliation,
    required this.role,
    this.realJid,
    this.isSelf = false,
  });

  /// The room nick — the resource of the occupant's in-room JID.
  final String nick;
  final MucAffiliation affiliation;
  final MucRole role;

  /// The occupant's real JID, if the room reveals it (non-anonymous rooms, or a
  /// moderator's view); null in an anonymous room.
  final String? realJid;

  /// True for our own occupant (self-presence, status code 110).
  final bool isSelf;
}

/// Why entering a room did not succeed (XEP-0045 §7.2 error conditions).
enum MucJoinFailure {
  /// The nick is already in use in the room (409 conflict).
  nickConflict,

  /// We are banned from the room (403 forbidden).
  banned,

  /// The room is members-only and we are not a member (407).
  membersOnly,

  /// The room is password-protected and none/the wrong one was given (401).
  passwordRequired,

  /// The room is full (503).
  roomFull,

  /// Entry is not allowed for another reason (405, or an unmapped condition).
  notAllowed,

  /// No self-presence arrived in time.
  timeout,

  /// The session dropped before the join completed.
  sessionClosed,
}

/// The outcome of [XmppMuc.join].
class MucJoinResult {
  const MucJoinResult.ok() : failure = null;
  const MucJoinResult.failed(this.failure);
  bool get ok => failure == null;
  final MucJoinFailure? failure;
}

/// One joined (or joining) room over a live [XmppStanzaChannel].
class XmppMuc {
  XmppMuc({
    required this.channel,
    required this.roomJid,
    required this.nick,
    this.timeout = const Duration(seconds: 20),
  });

  final XmppStanzaChannel channel;

  /// The bare room JID, `room@conference.server`.
  final String roomJid;

  /// Our chosen room nick.
  final String nick;
  final Duration timeout;

  final _occupants = <String, MucOccupant>{};
  final _roster = StreamController<List<MucOccupant>>.broadcast();
  StreamSubscription<Stanza>? _sub;
  Completer<MucJoinResult>? _joining;
  Timer? _joinTimer;
  bool _joined = false;
  bool _left = false;

  String get _selfInRoom => '$roomJid/$nick';

  /// The occupant roster, emitted afresh on every change while joined. Completes
  /// when the room is left or the session drops.
  Stream<List<MucOccupant>> get occupants => _roster.stream;

  /// The occupants known right now.
  List<MucOccupant> get roster => _occupants.values.toList(growable: false);

  /// Enter the room. Resolves once our self-presence arrives (ok) or on an error
  /// presence / timeout / dropped session (failed). On success the roster stays
  /// live until [leave]; on failure everything is torn down.
  Future<MucJoinResult> join() {
    if (_joining != null || _joined) {
      throw StateError('XmppMuc.join() called more than once');
    }
    final completer = _joining = Completer<MucJoinResult>();
    _sub = channel.stanzas.listen(_onStanza, onDone: _onSessionDropped);
    _joinTimer = Timer(
      timeout,
      () => _finishJoin(const MucJoinResult.failed(MucJoinFailure.timeout)),
    );
    // <presence to="room@service/nick"><x xmlns="…/muc"/></presence>
    channel.sendStanza(
      Stanza(
        kind: StanzaKind.presence,
        to: _selfInRoom,
        children: [xmppElement('x', namespace: _mucNs)],
      ),
    );
    return completer.future;
  }

  void _onStanza(Stanza stanza) {
    if (stanza.kind != StanzaKind.presence) return;
    final from = stanza.from;
    if (from == null || _bareJid(from) != roomJid) return; // only this room
    final occNick = _resourceOf(from);

    if (stanza.type == 'error') {
      _finishJoin(MucJoinResult.failed(_joinErrorOf(stanza)));
      return;
    }

    final userX = _childNs(stanza.children, 'x', _mucUserNs);
    final item = userX == null ? null : _childLocal(userX, 'item');
    final codes = userX == null
        ? const <String>{}
        : {
            for (final s in userX.childElements)
              if (s.name.local == 'status') s.getAttribute('code'),
          }.whereType<String>().toSet();
    // A room enforces unique nicks, so our own nick coming back IS us; code 110
    // confirms it explicitly (RFC-preferred).
    final isSelf = codes.contains('110') || occNick == nick;

    if (stanza.type == 'unavailable') {
      _occupants.remove(occNick);
      if (isSelf) _left = true;
      _emit();
      return;
    }

    _occupants[occNick] = MucOccupant(
      nick: occNick,
      affiliation: _affiliationOf(item?.getAttribute('affiliation')),
      role: _roleOf(item?.getAttribute('role')),
      realJid: item?.getAttribute('jid'),
      isSelf: isSelf,
    );
    _emit();

    if (isSelf && !_joined) {
      _joined = true;
      _finishJoin(const MucJoinResult.ok());
    }
  }

  MucJoinFailure _joinErrorOf(Stanza stanza) {
    final error = _childLocal2(stanza.children, 'error');
    final condition = error == null
        ? 'not-allowed'
        : error.childElements
              .map((e) => e.name.local)
              .firstWhere((n) => n != 'text', orElse: () => 'not-allowed');
    return switch (condition) {
      'conflict' => MucJoinFailure.nickConflict,
      'forbidden' => MucJoinFailure.banned,
      'registration-required' => MucJoinFailure.membersOnly,
      'not-authorized' => MucJoinFailure.passwordRequired,
      'service-unavailable' => MucJoinFailure.roomFull,
      _ => MucJoinFailure.notAllowed,
    };
  }

  void _finishJoin(MucJoinResult result) {
    _joinTimer?.cancel();
    _joinTimer = null;
    final completer = _joining;
    _joining = null;
    if (completer != null && !completer.isCompleted) completer.complete(result);
    if (!result.ok) unawaited(_teardown());
  }

  void _onSessionDropped() {
    _finishJoin(const MucJoinResult.failed(MucJoinFailure.sessionClosed));
    unawaited(_teardown());
  }

  void _emit() {
    if (!_roster.isClosed) _roster.add(roster);
  }

  /// Leave the room (send `unavailable`) and tear down. Idempotent.
  Future<void> leave() async {
    if (_left) {
      await _teardown();
      return;
    }
    _left = true;
    channel.sendStanza(
      Stanza(kind: StanzaKind.presence, to: _selfInRoom, type: 'unavailable'),
    );
    await _teardown();
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    if (!_roster.isClosed) await _roster.close();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  static String _bareJid(String jid) => jid.split('/').first;

  static String _resourceOf(String jid) {
    final slash = jid.indexOf('/');
    return slash < 0 ? '' : jid.substring(slash + 1);
  }

  static bool _hasNs(XmlElement e, String ns) =>
      e.getAttribute('xmlns') == ns || e.name.namespaceUri == ns;

  static XmlElement? _childNs(
    Iterable<XmlElement> children,
    String local,
    String ns,
  ) {
    for (final e in children) {
      if (e.name.local == local && _hasNs(e, ns)) return e;
    }
    return null;
  }

  static XmlElement? _childLocal(XmlElement parent, String local) {
    for (final e in parent.childElements) {
      if (e.name.local == local) return e;
    }
    return null;
  }

  static XmlElement? _childLocal2(Iterable<XmlElement> children, String local) {
    for (final e in children) {
      if (e.name.local == local) return e;
    }
    return null;
  }

  static MucAffiliation _affiliationOf(String? s) => switch (s) {
    'owner' => MucAffiliation.owner,
    'admin' => MucAffiliation.admin,
    'member' => MucAffiliation.member,
    'outcast' => MucAffiliation.outcast,
    _ => MucAffiliation.none,
  };

  static MucRole _roleOf(String? s) => switch (s) {
    'moderator' => MucRole.moderator,
    'participant' => MucRole.participant,
    'visitor' => MucRole.visitor,
    _ => MucRole.none,
  };
}
