// Deterministic companion-room derivation (F3, `NATIVE_CALLS.md` §5.1). OciDeck's
// control plane (presenter-sync, ops, presence) rides a SEPARATE MUC from the
// Jitsi conference — the companion room — so non-OciDeck participants are
// undisturbed and OciDeck users discover each other in a room of their own.
//
// There is no central registry (P1): two clients that hold the same conference
// URL must compute the same companion room, and no one who lacks the URL may
// recover it from the room name. So the name is a ONE-WAY hash of the normalized
// conference identity behind a versioned domain separator — it reveals nothing
// about the conference (§5.1), and a scheme change can rev the salt version
// without colliding with the old derivation. SHA-256 comes from `package:crypto`
// (already
// a dependency, used by the SASL code).

import 'dart:convert';

import 'package:crypto/crypto.dart';

// Rev the version if the derivation scheme changes, so an old and a new client do
// not silently land in different rooms for the same conference.
const _companionSalt = 'ocideck-companion:v1:';

/// The companion room's localpart for [conferenceRef] — `ocideck-<hash>`, a valid
/// MUC nodeprep string. Deterministic (the same conference URL always yields the
/// same name) and one-way (the name does not reveal the conference).
String companionRoomLocalpart(String conferenceRef) {
  final normalized = _normalizeConferenceRef(conferenceRef);
  final digest = sha256.convert(utf8.encode('$_companionSalt$normalized'));
  // 128 bits of the digest as hex — negligible accidental-collision risk, and hex
  // (0-9a-f) needs no nodeprep escaping.
  return 'ocideck-${digest.toString().substring(0, 32)}';
}

/// The full companion room JID on [mucService] — the MUC component of the same
/// XMPP server that carries the conference (e.g. `conference.example.org`).
String companionRoomJid(String conferenceRef, String mucService) =>
    '${companionRoomLocalpart(conferenceRef)}@$mucService';

/// Normalize a conference reference so two clients holding the same link derive
/// the same room: lowercase the host, keep the (effective) port so two
/// deployments on one host but different ports do not collapse into one room,
/// drop the ephemeral fragment (`#config…`) and query (Jitsi carries mute/camera
/// hints there — not part of the room's identity), and strip trailing
/// slashes. A non-URL reference is taken verbatim (trimmed) — it is already the
/// shared identifier. The path case is preserved: a room name can be
/// case-sensitive, so it is not folded together.
String _normalizeConferenceRef(String conferenceRef) {
  final trimmed = conferenceRef.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    var path = uri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    // uri.port is the effective port (the scheme default when none was written),
    // so an explicit `:443` and an implicit one agree, but `:8443` does not.
    return '${uri.host.toLowerCase()}:${uri.port}$path';
  }
  return trimmed;
}
