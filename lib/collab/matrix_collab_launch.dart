// App-level orchestration of a Matrix collaboration session
// (`docs/design/SELF_ENCRYPTED_RELAY.md` §6.5, phase P-D UX). It ties together the
// pieces a provider needs but should not itself assemble: the device key material
// (from the keychain via `SecretStore`), the room (created fresh per host session,
// joined via a shared link by a guest), and the session launch. The transport, the
// crypto and the session lifecycle are the layers below; this is the thin seam
// between them and the app's account/provider layer.
//
// The room model is "new room per session + shareable link" (decided 2026-07-31):
// the host creates a private, non-directory-listed room whose id is the secret the
// invite link carries, and a guest joins by pasting that link. Content is E2EE by
// our own layer, so the homeserver relays only ciphertext regardless.

import '../models/deck.dart';
import '../models/matrix_settings.dart';
import '../services/secret_store.dart';
import 'collab_crypto.dart';
import 'collab_device_store.dart';
import 'matrix_client.dart';
import 'matrix_invite.dart';
import 'matrix_session_launch.dart';

/// A hosted session and the link to share so others can join it.
class MatrixCollabHost {
  const MatrixCollabHost({required this.launch, required this.inviteLink});

  final MatrixCollabLaunch launch;
  final String inviteLink;
}

/// A device's crypto identity: the session crypto and the public keys to publish.
class _Device {
  const _Device(this.crypto, this.publicKeys);
  final CollabCrypto crypto;
  final DevicePublicKeys publicKeys;
}

/// Host a collaboration session on [account]'s homeserver: create a fresh room,
/// load (or generate) this device's keys, publish the baseline and start as the
/// authority. Returns the launch and the [MatrixCollabHost.inviteLink] to share.
Future<MatrixCollabHost> hostMatrixCollab({
  required MatrixClient client,
  required SecretStore secretStore,
  required MatrixServer account,
  required Deck deck,
}) async {
  final device = await _loadDevice(secretStore, account);
  // Private (not directory-listed) but join-by-id, so the room id in the link is
  // the access secret. The E2EE is ours, so the server still sees only ciphertext.
  final roomId = await client.createRoom(
    extra: {'preset': 'public_chat', 'visibility': 'private'},
  );
  final launch = await hostMatrixSession(
    client: client,
    crypto: device.crypto,
    ownKeys: device.publicKeys,
    ownUserId: account.userId,
    roomId: roomId,
    deck: deck,
  );
  return MatrixCollabHost(
    launch: launch,
    inviteLink: buildMatrixInvite(roomId),
  );
}

/// Join the session named by [inviteLink]. Throws [MatrixException] with kind
/// `config` when the link is not a valid room invite. The session appears on the
/// returned launch's [MatrixCollabLaunch.sessionReady] once the baseline arrives.
Future<MatrixCollabLaunch> joinMatrixCollab({
  required MatrixClient client,
  required SecretStore secretStore,
  required MatrixServer account,
  required Deck localDeck,
  required String inviteLink,
}) async {
  final target = parseMatrixInvite(inviteLink);
  if (target == null) {
    throw const MatrixException(
      MatrixErrorKind.config,
      'not a valid collaboration invite',
    );
  }
  final roomId = await client.join(target);
  final device = await _loadDevice(secretStore, account);
  return joinMatrixSession(
    client: client,
    crypto: device.crypto,
    ownKeys: device.publicKeys,
    ownUserId: account.userId,
    roomId: roomId,
    localDeck: localDeck,
  );
}

Future<_Device> _loadDevice(
  SecretStore secretStore,
  MatrixServer account,
) async {
  final keys = await loadOrCreateDeviceKeys(
    secretStore: secretStore,
    homeserver: account.homeserverUrl,
    userId: account.userId,
    deviceId: account.deviceId,
  );
  return _Device(CollabCrypto(keys), await keys.publicKeys(rot: 0));
}
