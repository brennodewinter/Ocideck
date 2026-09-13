// Draait het gedeelde CollabTransport-contract over Loopback — de
// implementatie die vandaag bestaat. XMPP draait in zijn eigen test
// (`test/xmpp/xmpp_transport_test.dart`) omdat het de `FakeMucHub`-testhelper
// nodig heeft die onder `test/xmpp/` leeft. Het contract zelf is één keer
// gedefinieerd in `collab_transport_contract.dart` en hier alleen aangeroepen,
// zodat een nieuw transport (XMPP, later WebDAV) hetzelfde bewijs levert als de
// bestaande.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_transport.dart';

import 'collab_transport_contract.dart';

void main() {
  runCollabTransportContract('Loopback', _createLoopback);
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
