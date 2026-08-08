// The session chat over Matrix (`docs/design/SELF_ENCRYPTED_RELAY.md` §6, phase
// P-E). Messages ride room timeline events `nl.ocideck.chat` — a conversation is
// history, so unlike presence it accumulates rather than replacing. Sealed like
// the deck content, so the homeserver relays only ciphertext.
//
// **Signed**, unlike ops and presence. Every session member holds the same epoch
// key, so an unsigned message would let one member forge one attributed to
// another — and chat is exactly where "who said what" has to be trustworthy. So a
// message is sealed with a signature and opened requiring one; a message that
// fails the check is dropped fail-closed.
//
// Own messages are echoed locally on [send] (so they show at once) and skipped on
// receive, so the sender does not see a duplicate when its own event syncs back.

import '../utils/log.dart';
import 'collab_crypto.dart';
import 'matrix_client.dart';
import 'collab_device_directory.dart';

/// One chat line, as the panel shows it.
class ChatMessage {
  const ChatMessage({
    required this.userId,
    required this.deviceId,
    required this.text,
    required this.isSelf,
  });

  final String userId;
  final String deviceId;
  final String text;

  /// True for a message this device sent (echoed locally, shown right-aligned).
  final bool isSelf;
}

/// Sends and receives session chat. Wire [handleSystemEvent] to the transport's
/// `onSystemEvent`; the app calls [send]. [onChanged] fires when the list grows.
class MatrixChat {
  MatrixChat({
    required MatrixClient client,
    required CollabCrypto crypto,
    required this.roomId,
    required this.directory,
    required this.ownUserId,
    this.maxMessageChars = 4000,
  }) : _matrix = client,
       _e2ee = crypto;

  /// Room timeline event carrying one sealed chat message.
  static const chatType = 'nl.ocideck.chat';

  final MatrixClient _matrix;
  final CollabCrypto _e2ee;
  final String roomId;
  final CollabDeviceDirectory directory;

  /// This device's Matrix user id, to attribute a locally-echoed own message.
  final String ownUserId;

  /// Cap on a single message, so one event stays well under the ~64 KiB limit.
  final int maxMessageChars;

  final List<ChatMessage> _messages = [];

  /// Sealed messages that arrived before their sender's keys or the epoch key
  /// was known; re-opened in [retryPending] in arrival order.
  final List<SealedEnvelope> _pending = [];

  /// Fired after the message list changes, so the provider can refresh the UI.
  void Function()? onChanged;

  /// The conversation so far, oldest first.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Send [text] to the room (signed + sealed) and echo it locally at once. A
  /// blank or over-long message is refused.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxMessageChars) return;
    final sealed = await _e2ee.seal(
      {'text': trimmed},
      room: roomId,
      type: chatType,
      signed: true,
    );
    _messages.add(
      ChatMessage(
        userId: ownUserId,
        deviceId: _e2ee.deviceId,
        text: trimmed,
        isSelf: true,
      ),
    );
    onChanged?.call();
    await _matrix.sendEvent(
      roomId: roomId,
      type: chatType,
      content: sealed.toContent(),
    );
  }

  /// Wire to `MatrixRelayTransport.onSystemEvent`. Opens a peer's message, or
  /// buffers it for [retryPending] when its key or sender is not yet known.
  Future<void> handleSystemEvent(MatrixTimelineEvent event) async {
    if (event.type != chatType) return;
    try {
      final sealed = SealedEnvelope.fromContent(event.content);
      if (sealed.senderDevice == _e2ee.deviceId) return; // own echo — shown
      _pending.add(sealed);
      await retryPending();
    } on Exception catch (e) {
      logWarning('collab.matrix.chat', e);
    }
  }

  /// Re-open buffered messages whose key or sender may now be known. Preserves
  /// arrival order; a still-unopenable message stays buffered.
  Future<void> retryPending() async {
    var progressed = false;
    while (_pending.isNotEmpty) {
      final opened = await _open(_pending.first);
      // Sender or epoch not ready — keep this and the rest queued for next round.
      if (opened == null) break;
      _pending.removeAt(0);
      if (opened.isNotEmpty) {
        _messages.add(_messageFrom(opened));
        progressed = true;
      }
    }
    if (progressed) onChanged?.call();
  }

  /// Opens [sealed], or null when it is not yet openable (unknown sender or
  /// epoch — keep and retry). Returns an empty map when it is openable but
  /// unusable (bad payload — drop by treating as opened-empty).
  Future<Map<String, Object?>?> _open(SealedEnvelope sealed) async {
    final sender = directory.resolve(sealed.senderDevice);
    if (sender == null) return null; // sender not known yet — keep
    try {
      final opened = await _e2ee.open(
        sealed,
        room: roomId,
        type: chatType,
        sender: sender,
        requireSignature: true,
      );
      final text = opened['text'];
      if (text is! String) return const {}; // openable but malformed — drop
      return {'text': text, 'device': sealed.senderDevice};
    } on CollabCryptoException catch (e) {
      if (e.reason == 'unknown-epoch') return null; // key not installed — keep
      logWarning('collab.matrix.chat.open', e); // bad sig/tag — drop
      return const {};
    }
  }

  ChatMessage _messageFrom(Map<String, Object?> opened) {
    final device = opened['device'] as String;
    return ChatMessage(
      userId: directory.addressOf(device) ?? '',
      deviceId: device,
      text: opened['text'] as String,
      isSelf: false,
    );
  }
}
