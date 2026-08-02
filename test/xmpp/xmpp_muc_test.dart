import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/xmpp/xmpp_muc.dart';
import 'package:ocideck/xmpp/xmpp_session.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';

/// A scripted stanza channel: [inject] pushes a server presence, [sent] records
/// what the MUC layer sends, [drop] simulates the session ending.
class FakeChannel implements XmppStanzaChannel {
  final _inbound = StreamController<Stanza>.broadcast();
  final sent = <Stanza>[];

  @override
  String? boundJid = 'me@example.org/res';

  @override
  Stream<Stanza> get stanzas => _inbound.stream;

  @override
  void sendStanza(Stanza stanza) => sent.add(stanza);

  void inject(Stanza stanza) {
    if (!_inbound.isClosed) _inbound.add(stanza);
  }

  void drop() {
    if (!_inbound.isClosed) _inbound.close();
  }
}

const _room = 'room@conf.example.org';
const _mucUser = 'http://jabber.org/protocol/muc#user';

Stanza _presence(
  String nick, {
  String affiliation = 'member',
  String role = 'participant',
  List<String> codes = const [],
  String? type,
  String? realJid,
}) {
  final statuses = codes.map((c) => '<status code="$c"/>').join();
  final jid = realJid == null ? '' : ' jid="$realJid"';
  final typeAttr = type == null ? '' : ' type="$type"';
  return Stanza.parse(
    '<presence from="$_room/$nick"$typeAttr>'
    '<x xmlns="$_mucUser">'
    '<item affiliation="$affiliation" role="$role"$jid/>$statuses'
    '</x></presence>',
  );
}

Stanza _errorPresence(String condition) => Stanza.parse(
  '<presence from="$_room/me" type="error">'
  '<error type="cancel">'
  '<$condition xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/>'
  '</error></presence>',
);

void main() {
  XmppMuc mucOf(FakeChannel ch, {String nick = 'me', Duration? timeout}) =>
      XmppMuc(
        channel: ch,
        roomJid: _room,
        nick: nick,
        timeout: timeout ?? const Duration(seconds: 20),
      );

  test('join completes on self-presence and builds the roster', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();

    // The join presence went out to room/nick with the muc <x>.
    final join = ch.sent.single;
    expect(join.kind, StanzaKind.presence);
    expect(join.to, '$_room/me');

    ch.inject(_presence('alice', affiliation: 'owner', role: 'moderator'));
    ch.inject(_presence('me', codes: ['110']));
    final result = await joining;

    expect(result.ok, isTrue);
    expect(muc.roster.map((o) => o.nick).toSet(), {'alice', 'me'});
    expect(muc.roster.firstWhere((o) => o.nick == 'me').isSelf, isTrue);
    final alice = muc.roster.firstWhere((o) => o.nick == 'alice');
    expect(alice.affiliation, MucAffiliation.owner);
    expect(alice.role, MucRole.moderator);
    await muc.leave();
  });

  test('a non-anonymous room reveals the occupant real JID', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_presence('alice', realJid: 'alice@example.org/phone'));
    ch.inject(_presence('me', codes: ['110']));
    await joining;
    expect(
      muc.roster.firstWhere((o) => o.nick == 'alice').realJid,
      'alice@example.org/phone',
    );
    await muc.leave();
  });

  test('join fails with nickConflict on a conflict error', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch, nick: 'taken');
    final joining = muc.join();
    ch.inject(_errorPresence('conflict'));
    final result = await joining;
    expect(result.ok, isFalse);
    expect(result.failure, MucJoinFailure.nickConflict);
  });

  test('join maps a members-only registration error', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_errorPresence('registration-required'));
    final result = await joining;
    expect(result.failure, MucJoinFailure.membersOnly);
  });

  test('an occupant leaving is removed from the roster and emitted', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_presence('bob'));
    ch.inject(_presence('me', codes: ['110']));
    await joining;
    expect(muc.roster.map((o) => o.nick), contains('bob'));

    final seen = <List<String>>[];
    muc.occupants.listen((r) => seen.add(r.map((o) => o.nick).toList()));
    ch.inject(_presence('bob', type: 'unavailable'));
    await Future<void>.delayed(Duration.zero);

    expect(muc.roster.map((o) => o.nick), isNot(contains('bob')));
    expect(seen.last, isNot(contains('bob')));
    await muc.leave();
  });

  test('leave sends an unavailable presence and closes the roster', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_presence('me', codes: ['110']));
    await joining;

    var rosterClosed = false;
    muc.occupants.listen((_) {}, onDone: () => rosterClosed = true);
    await muc.leave();

    final unavailable = ch.sent.where((s) => s.type == 'unavailable').toList();
    expect(unavailable, hasLength(1));
    expect(unavailable.single.to, '$_room/me');
    await Future<void>.delayed(Duration.zero);
    expect(rosterClosed, isTrue);
  });

  test('a session drop before join fails with sessionClosed', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.drop();
    final result = await joining;
    expect(result.failure, MucJoinFailure.sessionClosed);
  });

  test('join times out when no self-presence arrives', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch, timeout: const Duration(milliseconds: 50));
    final result = await muc.join();
    expect(result.failure, MucJoinFailure.timeout);
  });

  test('join twice throws', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    unawaited(muc.join());
    expect(muc.join, throwsStateError);
    ch.drop();
  });

  test('a stray error presence after join does not tear down the roster', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_presence('me', codes: ['110']));
    await joining;

    var rosterClosed = false;
    muc.occupants.listen((_) {}, onDone: () => rosterClosed = true);
    // A buggy/hostile server must not be able to silently close a live roster.
    ch.inject(_errorPresence('conflict'));
    await Future<void>.delayed(Duration.zero);

    expect(rosterClosed, isFalse);
    expect(muc.roster.map((o) => o.nick), contains('me'));
    await muc.leave();
  });

  test('leave after a failed join sends no unavailable presence', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_errorPresence('conflict'));
    await joining; // failed
    ch.sent.clear();

    await muc.leave();
    expect(ch.sent.where((s) => s.type == 'unavailable'), isEmpty);
  });
}
