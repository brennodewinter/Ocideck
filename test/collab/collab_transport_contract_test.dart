// Draait het gedeelde CollabTransport-contract over Loopback en Matrix — de
// twee implementaties die vandaag bestaan. XMPP draait in zijn eigen test
// (`test/xmpp/xmpp_transport_test.dart`) omdat het de `FakeMucHub`-testhelper
// nodig heeft die onder `test/xmpp/` leeft. Het contract zelf is één keer
// gedefinieerd in `collab_transport_contract.dart` en hier alleen aangeroepen,
// zodat een nieuw transport (XMPP, later WebDAV) hetzelfde bewijs levert als de
// bestaande twee.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_transport.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/collab/matrix_relay_transport.dart';

import 'collab_transport_contract.dart';
import 'fake_homeserver.dart';

void main() {
  runCollabTransportContract('Loopback', _createLoopback);
  runCollabTransportContract('Matrix', _createMatrix);
}

// ── Loopback ─────────────────────────────────────────────────────────────────

Future<CollabTransportPair> _createLoopback() async {
  final hub = LoopbackHub();
  final a = hub.connect('alice');
  final b = hub.connect('bob');
  return CollabTransportPair(
    a: a,
    b: b,
    pump: () => pumpEventQueue(times: 50),
    dispose: () async {
      await a.dispose();
      await b.dispose();
    },
  );
}

// ── Matrix ───────────────────────────────────────────────────────────────────

Future<CollabTransportPair> _createMatrix() async {
  const room = '!contract:hs.example';
  final hs = FakeHomeserver()
    ..addUser('alice', 'pw', userId: '@alice:hs.example')
    ..addUser('bob', 'pw', userId: '@bob:hs.example');

  // Twee device-identiteiten die al epoch 0 delen (sleutels vooraf gedeeld —
  // de key-exchange-distributie is buiten dit contract's scope).
  final aliceKeys = await _device('alice');
  final bobKeys = await _device('bob');
  final aliceCrypto = CollabCrypto(aliceKeys);
  final bobCrypto = CollabCrypto(bobKeys);
  final alicePub = await aliceKeys.publicKeys(rot: 0);
  final bobPub = await bobKeys.publicKeys(rot: 0);
  final rk = await aliceCrypto.rekey([bobPub]);
  await bobCrypto.installEpochKey(rk.wraps.single, alicePub);
  final directory = {'alice': alicePub, 'bob': bobPub};
  Future<DevicePublicKeys?> resolve(String id) async => directory[id];

  final aliceClient = MatrixClient(
    transport: hs,
    homeserver: Uri.parse('https://hs.example'),
  );
  await aliceClient.login(user: 'alice', password: 'pw');
  final aliceTransport = MatrixRelayTransport(
    client: aliceClient,
    crypto: aliceCrypto,
    roomId: room,
    resolvePeer: resolve,
  );

  final bobClient = MatrixClient(
    transport: hs,
    homeserver: Uri.parse('https://hs.example'),
  );
  await bobClient.login(user: 'bob', password: 'pw');
  final bobTransport = MatrixRelayTransport(
    client: bobClient,
    crypto: bobCrypto,
    roomId: room,
    resolvePeer: resolve,
  );

  return CollabTransportPair(
    a: aliceTransport,
    b: bobTransport,
    // Matrix is pull-based: syncOnce op beide kanten levert de berichten.
    pump: () async {
      await aliceTransport.syncOnce();
      await bobTransport.syncOnce();
      await pumpEventQueue(times: 50);
    },
    dispose: () async {
      await aliceTransport.dispose();
      await bobTransport.dispose();
    },
  );
}

/// Deterministische device-sleutels van een label (spiegelt de fixture in
/// `matrix_relay_transport_test.dart`).
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
