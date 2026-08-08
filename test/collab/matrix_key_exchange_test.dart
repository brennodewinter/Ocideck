// End-to-end tests for key establishment over the wire
// (`lib/collab/matrix_key_exchange.dart`, SELF_ENCRYPTED_RELAY.md phase P-D). Two
// parties establish their session keys **entirely over the fake homeserver** —
// publishing device keys as room state, learning each other through the directory,
// and the authority handing the epoch key to the member via a to-device key-share
// — with no pre-shared epoch and no static directory (the crutches the P-C test
// used). Then they co-author over the relay, proving the established keys work.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_device_directory.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/collab/matrix_key_exchange.dart';
import 'package:ocideck/collab/matrix_relay_transport.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

import 'fake_homeserver.dart';

void main() {
  const room = '!deck:hs.example';
  late FakeHomeserver hs;
  late _Party owner;
  late _Party peer;

  setUp(() async {
    hs = FakeHomeserver();
    hs.addUser('owner', 'pw', userId: '@owner:hs.example');
    hs.addUser('peer', 'pw', userId: '@peer:hs.example');
    owner = await _Party.create(hs, 'owner', 'pw', room);
    peer = await _Party.create(hs, 'peer', 'pw', room);
  });

  tearDown(() async {
    await owner.dispose();
    await peer.dispose();
  });

  /// Both publish device keys, learn each other, then the authority hands the
  /// epoch key to the peer. After this both hold epoch 0 and each other's keys.
  Future<void> establish() async {
    await owner.exchange.publishDeviceKeys();
    await peer.exchange.publishDeviceKeys();
    await owner.transport.syncOnce(); // owner learns peer's device
    await peer.transport.syncOnce(); // peer learns owner's device
    await owner.exchange.distributeEpoch([peer.publicKeys]);
    await peer.transport.syncOnce(); // peer receives + installs the key-share
  }

  test('two parties establish keys over the wire, then co-author', () async {
    await establish();

    expect(owner.crypto.currentEpoch, 0);
    expect(peer.crypto.currentEpoch, 0, reason: 'peer installed the key-share');
    expect(owner.directory.resolve('peer')?.deviceId, 'peer');
    expect(peer.directory.resolve('owner')?.deviceId, 'owner');

    final slide = Slide.create(SlideType.bullets).copyWith(title: 'start');
    owner.startSession(_deckWith(slide), isAuthority: true);
    peer.startSession(_deckWith(slide), isAuthority: false);

    await owner.session.submit(
      SetSlideField(
        version: 0,
        authorId: 'owner',
        slideId: slide.id,
        field: SlideField.title,
        value: 'established',
      ),
    );
    await _settle();
    await peer.transport.syncOnce();
    await _settle();

    expect(peer.session.deck.slides.single.title, 'established');
  });

  test('a device with an unverifiable binding is not trusted', () async {
    // A relay swaps the agreement key: the identity signature no longer covers
    // it, so the directory refuses to store it.
    final good = await owner.publicKeysObject();
    final other = await peer.publicKeysObject();
    final swapped = DevicePublicKeys(
      deviceId: good.deviceId,
      identityKey: good.identityKey,
      agreementKey: other.agreementKey,
      agreementSignature: good.agreementSignature,
    );
    final dir = CollabDeviceDirectory();
    await dir.ingest(peerAddress: '@owner:hs.example', keys: swapped);
    expect(dir.resolve(good.deviceId), isNull);
  });

  test('a key-share from an unknown sender is dropped', () async {
    // The owner never publishes its device keys, so when its key-share reaches the
    // peer the peer cannot verify who it is from — and drops it rather than trust
    // the sender keys carried in the (relay-deliverable) message itself.
    await peer.exchange.publishDeviceKeys();
    await owner.transport.syncOnce(); // owner learns peer, to address the share
    await owner.exchange.distributeEpoch([peer.publicKeys]);
    await peer.transport.syncOnce(); // key-share arrives, its sender unknown

    expect(peer.crypto.currentEpoch, isNull, reason: 'no key installed');
  });

  test('a device event filed under the wrong state key is ignored', () async {
    final dir = CollabDeviceDirectory();
    final exchange = MatrixKeyExchange(
      client: owner.client,
      crypto: owner.crypto,
      roomId: room,
      directory: dir,
      ownKeys: await owner.publicKeysObject(),
    );
    final keys = await peer.publicKeysObject();
    await exchange.handleSystemEvent(
      MatrixTimelineEvent(
        roomId: room,
        eventId: r'$x',
        type: MatrixKeyExchange.deviceEventType,
        sender: '@peer:hs.example',
        content: keys.toJson(),
        stateKey: 'not-the-right-device',
      ),
    );
    expect(dir.resolve(keys.deviceId), isNull);
  });
}

Deck _deckWith(Slide s) => Deck(title: 'deck', slides: [s]);

Future<void> _settle() => pumpEventQueue(times: 100);

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

/// A participant: logged-in client, crypto, directory, key exchange and the relay
/// transport wired to feed the exchange — the shape a live session uses.
class _Party {
  _Party({
    required this.client,
    required this.crypto,
    required this.publicKeys,
    required this.directory,
    required this.exchange,
    required this.transport,
    required this.keys,
  });

  final MatrixClient client;
  final CollabCrypto crypto;
  final DevicePublicKeys publicKeys;
  final CollabDeviceDirectory directory;
  final MatrixKeyExchange exchange;
  final MatrixRelayTransport transport;
  final CollabDeviceKeys keys;
  CollabSession? _session;

  CollabSession get session => _session!;

  static Future<_Party> create(
    FakeHomeserver hs,
    String label,
    String password,
    String room,
  ) async {
    final client = MatrixClient(
      transport: hs,
      homeserver: Uri.parse('https://hs.example'),
    );
    await client.login(user: label, password: password);
    final keys = await _device(label);
    final crypto = CollabCrypto(keys);
    final publicKeys = await keys.publicKeys();
    final directory = CollabDeviceDirectory();
    final exchange = MatrixKeyExchange(
      client: client,
      crypto: crypto,
      roomId: room,
      directory: directory,
      ownKeys: publicKeys,
    );
    final transport = MatrixRelayTransport(
      client: client,
      crypto: crypto,
      roomId: room,
      resolvePeer: (id) async => directory.resolve(id),
      onSystemEvent: exchange.handleSystemEvent,
      onToDevice: exchange.handleToDevice,
    );
    return _Party(
      client: client,
      crypto: crypto,
      publicKeys: publicKeys,
      directory: directory,
      exchange: exchange,
      transport: transport,
      keys: keys,
    );
  }

  Future<DevicePublicKeys> publicKeysObject() => keys.publicKeys();

  void startSession(Deck deck, {required bool isAuthority}) {
    _session = CollabSession(
      initialDeck: deck,
      transport: transport,
      isAuthority: isAuthority,
    );
  }

  Future<void> dispose() async {
    if (_session != null) {
      await _session!.dispose();
    } else {
      await transport.dispose();
    }
  }
}
