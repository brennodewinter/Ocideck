import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/xmpp/companion_room.dart';

void main() {
  const conf = 'https://meet.jit.si/OciDeckDemo';

  test('is deterministic — the same conference yields the same room', () {
    expect(companionRoomLocalpart(conf), companionRoomLocalpart(conf));
  });

  test('different conferences yield different rooms', () {
    expect(
      companionRoomLocalpart('https://meet.jit.si/RoomA'),
      isNot(companionRoomLocalpart('https://meet.jit.si/RoomB')),
    );
  });

  test('the room name is a valid, safe MUC localpart', () {
    expect(
      companionRoomLocalpart(conf),
      matches(RegExp(r'^ocideck-[0-9a-f]{32}$')),
    );
  });

  test('the name does not reveal the conference (one-way, no substring)', () {
    final name = companionRoomLocalpart('https://meet.jit.si/SecretStandup');
    expect(name.toLowerCase(), isNot(contains('secretstandup')));
    expect(name.toLowerCase(), isNot(contains('meet.jit.si')));
  });

  group('two clients holding the same link land in the same room', () {
    test('the ephemeral #config fragment is ignored', () {
      expect(
        companionRoomLocalpart('$conf#config.startWithAudioMuted=true'),
        companionRoomLocalpart(conf),
      );
    });

    test('a query string is ignored', () {
      expect(
        companionRoomLocalpart('$conf?jwt=abc'),
        companionRoomLocalpart(conf),
      );
    });

    test('a trailing slash is ignored', () {
      expect(companionRoomLocalpart('$conf/'), companionRoomLocalpart(conf));
    });

    test('host case is ignored', () {
      expect(
        companionRoomLocalpart('https://MEET.JIT.SI/OciDeckDemo'),
        companionRoomLocalpart(conf),
      );
    });
  });

  test('the room name is case-sensitive in the room part', () {
    // A different room (different case) is a different companion room — room
    // names can be case-sensitive, so they are not folded together.
    expect(
      companionRoomLocalpart('https://meet.jit.si/room'),
      isNot(companionRoomLocalpart('https://meet.jit.si/ROOM')),
    );
  });

  test('a bare (non-URL) reference is usable and stable', () {
    expect(
      companionRoomLocalpart('team-standup'),
      companionRoomLocalpart('  team-standup  '), // trimmed
    );
  });

  test('companionRoomJid appends the MUC service', () {
    expect(
      companionRoomJid(conf, 'conference.example.org'),
      '${companionRoomLocalpart(conf)}@conference.example.org',
    );
  });
}
