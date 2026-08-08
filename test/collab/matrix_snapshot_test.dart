// Tests for the snapshot channel (`lib/collab/matrix_snapshot.dart`,
// SELF_ENCRYPTED_RELAY.md phase P-D): a baseline is sealed once, chunked across
// events, and reassembled + opened on the far side — with the slide ids preserved
// (the whole reason a snapshot exists, §5.5). Fail-closed: a tampered or missing
// chunk yields no snapshot rather than a half-built one.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_device_directory.dart';
import 'package:ocideck/collab/collab_snapshot.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/collab/matrix_snapshot.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

import 'fake_homeserver.dart';

void main() {
  const room = '!deck:hs.example';
  late FakeHomeserver hs;
  late MatrixSnapshotChannel authorityChannel;
  late MatrixClient receiverClient;
  late CollabDeviceDirectory receiverDirectory;
  late CollabCrypto receiverCrypto;
  late CollabSnapshot sent;

  setUp(() async {
    hs = FakeHomeserver();
    hs.addUser('auth', 'pw', userId: '@auth:hs.example');
    hs.addUser('recv', 'pw', userId: '@recv:hs.example');

    final authKeys = await _device('auth');
    final recvKeys = await _device('recv');
    final authCrypto = CollabCrypto(authKeys);
    receiverCrypto = CollabCrypto(recvKeys);
    final authPub = await authKeys.publicKeys();
    final recvPub = await recvKeys.publicKeys();
    final rk = await authCrypto.rekey([recvPub]);
    await receiverCrypto.installEpochKey(rk.wraps.single, authPub);

    receiverDirectory = CollabDeviceDirectory();
    await receiverDirectory.ingest(
      peerAddress: '@auth:hs.example',
      keys: authPub,
    );

    final authClient = MatrixClient(
      transport: hs,
      homeserver: Uri.parse('https://hs.example'),
    );
    await authClient.login(user: 'auth', password: 'pw');
    receiverClient = MatrixClient(
      transport: hs,
      homeserver: Uri.parse('https://hs.example'),
    );
    await receiverClient.login(user: 'recv', password: 'pw');

    // A small chunk size forces the blob across several events.
    authorityChannel = MatrixSnapshotChannel(
      client: authClient,
      crypto: authCrypto,
      roomId: room,
      directory: CollabDeviceDirectory(),
      maxChunkChars: 200,
    );

    final slides = [
      for (var i = 0; i < 4; i++)
        Slide.create(SlideType.bullets).copyWith(
          title: 'slide $i with enough text to grow the payload a bit',
        ),
    ];
    sent = CollabSnapshot.capture(Deck(title: 't', slides: slides), 3, 0);
  });

  MatrixSnapshotChannel receiverChannel() => MatrixSnapshotChannel(
    client: receiverClient,
    crypto: receiverCrypto,
    roomId: room,
    directory: receiverDirectory,
    maxChunkChars: 200,
  );

  Future<List<MatrixTimelineEvent>> chunkEvents() async {
    final result = await receiverClient.sync();
    return result.timeline
        .where((e) => e.type == MatrixSnapshotChannel.chunkEventType)
        .toList();
  }

  test('a chunked snapshot reassembles with slide ids preserved', () async {
    await authorityChannel.sendSnapshot(sent);
    final chunks = await chunkEvents();
    expect(chunks.length, greaterThan(1), reason: 'the blob was chunked');

    final channel = receiverChannel();
    for (final e in chunks) {
      await channel.handleSystemEvent(e);
    }
    final received = await channel.firstSnapshot;

    expect(received.version, 3);
    expect(received.slides.map((s) => s.id), sent.slides.map((s) => s.id));
    expect(received.slides.first.title, sent.slides.first.title);
  });

  test('a tampered chunk yields no snapshot (fail-closed)', () async {
    await authorityChannel.sendSnapshot(sent);
    final chunks = await chunkEvents();

    final tampered = [
      MatrixTimelineEvent(
        roomId: chunks.first.roomId,
        eventId: chunks.first.eventId,
        type: chunks.first.type,
        sender: chunks.first.sender,
        content: {
          ...chunks.first.content,
          'data': 'xx${chunks.first.content['data']}',
        },
      ),
      ...chunks.skip(1),
    ];

    final channel = receiverChannel();
    var completed = false;
    unawaited(channel.firstSnapshot.then((_) => completed = true));
    for (final e in tampered) {
      await channel.handleSystemEvent(e);
    }
    await pumpEventQueue();
    expect(completed, isFalse);
  });

  test('a missing chunk yields no snapshot', () async {
    await authorityChannel.sendSnapshot(sent);
    final chunks = await chunkEvents();

    final channel = receiverChannel();
    var completed = false;
    unawaited(channel.firstSnapshot.then((_) => completed = true));
    for (final e in chunks.skip(1)) {
      // drop the first chunk
      await channel.handleSystemEvent(e);
    }
    await pumpEventQueue();
    expect(completed, isFalse);
  });
}

Future<CollabDeviceKeys> _device(String label) {
  List<int> seed(int salt) {
    final bytes = Uint8List(32);
    final name = label.codeUnits;
    for (var i = 0; i < 32; i++) {
      bytes[i] = (name[i % name.length] + salt + i) & 0xff;
    }
    return bytes;
  }

  return CollabDeviceKeys.fromSeeds(
    deviceId: label,
    ed25519Seed: seed(1),
    x25519Seed: seed(2),
  );
}
