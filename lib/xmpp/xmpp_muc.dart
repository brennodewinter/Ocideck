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

  /// Max occupants tracked — a hostile room can flood presence for fake
  /// occupants to exhaust memory. 500 is well above any real meeting.
  static const _maxOccupants = 500;

  /// Max length for a JID (RFC 6120 §3: 3071 bytes) or nick from presence.
  static const _maxJidLength = 3071;
  static const _maxNickLength = 1024;

  final _occupants = <String, MucOccupant>{};
  StreamController<List<MucOccupant>> _roster =
      StreamController<List<MucOccupant>>.broadcast();
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
  ///
  /// [presenceExtensions] zijn extra child-elementen die op de join-presence
  /// meereizen — bijv. de `<x xmlns="nl.ocideck.device">`-extensie die de
  /// device-keys publiceert (§5 brick 10, `XMPP_COLLAB_TRANSPORT.md` §6).
  /// De MUC-`<x>` blijft altijd het eerste child; de extensies komen erna.
  ///
  /// [historyLimit] vraagt de laatste N chat-berichten uit de MUC-geschiedenis
  /// op (XEP-0045 §7.2.16 `<history maxstanzas=N>`). De server honourneert dit
  /// als onderdeel van de join-sequentie — een late joiner ziet dan recente
  /// chat. 0 (default) vraagt geen geschiedenis. De server kan minder sturen
  /// of de request negeren; dit is een hint, geen eis (#1425).
  Future<MucJoinResult> join({
    List<XmlElement>? presenceExtensions,
    int historyLimit = 0,
  }) {
    // Sta een re-join toe na een teardown (_left = true) — de reconnect-
    // machinery (onRejoin) moet de kamer opnieuw kunnen betreden zonder een
    // nieuwe XmppMuc aan te maken (#1421). Een join terwijl er al één loopt
    // of de kamer al live is, blijft een StateError.
    if (_joining != null || (_joined && !_left)) {
      throw StateError('XmppMuc.join() called more than once');
    }
    // Reset de state voor een re-join: de oude roster is gesloten in
    // _teardown, de occupants zijn stale, _left is gezet.
    if (_left) {
      _occupants.clear();
      _joined = false;
      _left = false;
      if (_roster.isClosed) {
        _roster = StreamController<List<MucOccupant>>.broadcast();
      }
    }
    final completer = _joining = Completer<MucJoinResult>();
    _sub = channel.stanzas.listen(_onStanza, onDone: _onSessionDropped);
    _joinTimer = Timer(
      timeout,
      () => _finishJoin(const MucJoinResult.failed(MucJoinFailure.timeout)),
    );
    // <presence to="room@service/nick"><x xmlns="…/muc"/><history …/>…extensies…</presence>
    final historyChildren = <XmlElement>[
      xmppElement('x', namespace: _mucNs),
      if (historyLimit > 0)
        xmppElement('history', attributes: {'maxstanzas': '$historyLimit'}),
      ...?presenceExtensions,
    ];
    channel.sendStanza(
      Stanza(
        kind: StanzaKind.presence,
        to: _selfInRoom,
        children: historyChildren,
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
      // Only an error DURING join is a join failure. A stray error-presence
      // after we are in is ignored — a buggy or hostile server must not be able
      // to silently tear down a live roster.
      if (!_joined) _finishJoin(MucJoinResult.failed(_joinErrorOf(stanza)));
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

    // Refuse an oversized nick — a hostile server can send a multi-MB
    // string to exhaust memory. Drop the presence silently.
    if (occNick.length > _maxNickLength) return;
    // An oversized realJid is nullified, not dropped: the occupant is still
    // tracked, just without the hostile JID.
    final rawRealJid = item?.getAttribute('jid');
    final realJid = (rawRealJid != null && rawRealJid.length <= _maxJidLength)
        ? rawRealJid
        : null;

    // Cap the roster: a hostile room flooding fake occupants must not
    // grow the map unbounded. Drop new entries past the cap.
    if (_occupants.length >= _maxOccupants &&
        !_occupants.containsKey(occNick)) {
      return;
    }

    _occupants[occNick] = MucOccupant(
      nick: occNick,
      affiliation: _affiliationOf(item?.getAttribute('affiliation')),
      role: _roleOf(item?.getAttribute('role')),
      realJid: realJid,
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
    // Once torn down (join failure, session drop, or leave) a later leave() must
    // not send a fresh presence to a room we are no longer in.
    _left = true;
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
