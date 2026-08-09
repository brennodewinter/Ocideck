import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/xmpp/xmpp_muc.dart';
import 'package:ocideck/xmpp/xmpp_session.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';

/// A scripted stanza channel: [inject] pushes a server presence, [sent] records
/// what the MUC layer sends, [drop] simulates the session ending.
class FakeChannel implements XmppStanzaChannel {
  StreamController<Stanza> _inbound = StreamController<Stanza>.broadcast();
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

  /// Simuleer een reconnect: maak een verse inbound-stream. De MUC's
  /// re-subscription in join() ziet een levende stream.
  void reconnect() {
    if (_inbound.isClosed) _inbound = StreamController<Stanza>.broadcast();
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

  test('join to a non-existent room fails with notAllowed (#1434)', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_errorPresence('item-not-found'));
    final result = await joining;
    expect(result.ok, isFalse);
    expect(result.failure, MucJoinFailure.notAllowed);
  });

  test(
    'a presence with malformed MUC-user XML is dropped, not fatal (#1434)',
    () async {
      final ch = FakeChannel();
      final muc = mucOf(ch);
      final joining = muc.join();
      ch.inject(_presence('me', codes: ['110']));
      await joining;

      // Inject een presence met ongeldig MUC-user XML — de parser moet dit
      // gracelijk afhandelen, niet crashen.
      ch.inject(
        Stanza.parse(
          '<presence from="$_room/bob">'
          '<x xmlns="$_mucUser">'
          '<item affiliation="INVALID_ROLE" role=""/>'
          '</x></presence>',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // De sessie is nog live — geen crash.
      expect(muc.roster.any((o) => o.nick == 'bob'), isTrue);
      await muc.leave();
    },
  );

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

  test(
    'join with historyLimit sends a <history maxstanzas=N/> element (#1425)',
    () async {
      final ch = FakeChannel();
      final muc = mucOf(ch);
      unawaited(muc.join(historyLimit: 20));

      // De join-presence bevat een <history maxstanzas="20"/> child.
      final join = ch.sent.single;
      expect(join.kind, StanzaKind.presence);
      final history = join.children.firstWhere(
        (c) => c.getAttribute('maxstanzas') != null,
        orElse: () =>
            throw TestFailure('no <history> element in join presence'),
      );
      expect(history.getAttribute('maxstanzas'), '20');
      ch.drop();
    },
  );

  test(
    'join without historyLimit sends no <history> element (#1425)',
    () async {
      final ch = FakeChannel();
      final muc = mucOf(ch);
      unawaited(muc.join());

      final join = ch.sent.single;
      expect(
        join.children.any((c) => c.getAttribute('maxstanzas') != null),
        isFalse,
        reason: 'no <history> element when historyLimit is 0',
      );
      ch.drop();
    },
  );

  test(
    'leave during a pending join cancels the join future, not hang (#1427)',
    () async {
      final ch = FakeChannel();
      final muc = mucOf(ch, timeout: const Duration(seconds: 30));
      final joining = muc.join();

      // leave() terwijl de join nog loopt (geen self-presence ontvangen).
      // De oude code liet de join-future hangen tot de 30s timeout.
      await muc.leave();

      // De join-future is voltooid met cancelled, niet hangend.
      final result = await joining.timeout(const Duration(seconds: 1));
      expect(result.ok, isFalse);
      expect(result.failure, MucJoinFailure.cancelled);
    },
  );

  test(
    'a presence without a resource/nick is dropped, not added to the roster (#1426)',
    () async {
      final ch = FakeChannel();
      final muc = mucOf(ch);
      final joining = muc.join();
      ch.inject(_presence('me', codes: ['110']));
      await joining;

      // Een presence van room@conf (zonder /nick) — misvormd, geen occupant.
      ch.inject(
        Stanza.parse(
          '<presence from="$_room">'
          '<x xmlns="$_mucUser">'
          '<item affiliation="member" role="participant"/>'
          '</x></presence>',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Geen phantom-entry met nick "" in het roster.
      expect(muc.roster.any((o) => o.nick.isEmpty), isFalse);
      await muc.leave();
    },
  );

  test('rejoin after leave succeeds — XmppMuc is reusable (#1421)', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);

    // Eerste join — slaagt.
    final firstJoin = muc.join();
    ch.inject(_presence('me', codes: ['110']));
    final firstResult = await firstJoin;
    expect(firstResult.ok, isTrue);
    await muc.leave();

    // Re-join na een leave — de oude code gooide StateError; nu moet hij
    // de kamer opnieuw betreden (de reconnect-machinery moet dit kunnen).
    final secondJoin = muc.join();
    ch.inject(_presence('me', codes: ['110']));
    final secondResult = await secondJoin;
    expect(secondResult.ok, isTrue);
    expect(muc.roster.map((o) => o.nick), contains('me'));
    await muc.leave();
  });

  test(
    'rejoin after session drop succeeds — XmppMuc is reusable (#1421)',
    () async {
      final ch = FakeChannel();
      final muc = mucOf(ch);

      // Join slaagt, dan valt de sessie weg.
      final firstJoin = muc.join();
      ch.inject(_presence('me', codes: ['110']));
      final firstResult = await firstJoin;
      expect(firstResult.ok, isTrue);
      ch.drop();
      // Wacht tot de onDone-callback (_onSessionDropped → _teardown) heeft
      // gevuuurd — anders is _left nog niet gezet en join() gooit.
      await Future<void>.delayed(Duration.zero);

      // Simuleer een reconnect: de sessie is hersteld met een verse stream.
      ch.reconnect();

      // Re-join na een session drop — de MUC moet opnieuw kunnen betreden.
      final secondJoin = muc.join();
      ch.inject(_presence('me', codes: ['110']));
      final secondResult = await secondJoin;
      expect(secondResult.ok, isTrue);
      await muc.leave();
    },
  );

  test(
    'a stray error presence after join does not tear down the roster',
    () async {
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
    },
  );

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

  test('an oversized nick is refused (DoS guard)', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_presence('me', codes: ['110']));
    await joining;

    final hugeNick = 'a' * 2000;
    ch.inject(_presence(hugeNick));
    await Future<void>.delayed(Duration.zero);

    expect(muc.roster.map((o) => o.nick), isNot(contains(hugeNick)));
    await muc.leave();
  });

  test('an oversized realJid is refused (DoS guard)', () async {
    final ch = FakeChannel();
    final muc = mucOf(ch);
    final joining = muc.join();
    ch.inject(_presence('me', codes: ['110']));
    await joining;

    final hugeJid = '${'a' * 4000}@example.org';
    ch.inject(_presence('alice', realJid: hugeJid));
    await Future<void>.delayed(Duration.zero);

    final alice = muc.roster.firstWhere((o) => o.nick == 'alice');
    expect(alice.realJid, isNull);
    await muc.leave();
  });
}
