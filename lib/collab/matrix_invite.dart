// Building and reading the shareable link that invites someone into a
// collaboration room (`docs/design/SELF_ENCRYPTED_RELAY.md` §6.5, phase P-D UX).
// The host creates a fresh room per session and shares a `matrix.to` link; the
// guest pastes it to join. This is pure string work — no network — so it is fully
// unit-tested, and the resolver refuses anything that is not a room id or alias
// rather than guessing (a pasted link is bearer-like: we never probe it).

/// Build a `matrix.to` invite link for [roomIdOrAlias] (e.g. `!abc:hs.example`
/// or `#room:hs.example`). The id is percent-encoded so its `!`/`#`/`:` survive
/// the fragment intact.
String buildMatrixInvite(String roomIdOrAlias) =>
    'https://matrix.to/#/${Uri.encodeComponent(roomIdOrAlias.trim())}';

/// Read a room id or alias out of a pasted invite. Accepts a full `matrix.to`
/// link (`https://matrix.to/#/!abc:hs` or `.../#/%23room:hs`) or a bare id/alias
/// (`!abc:hs`, `#room:hs`). Returns null when the input is neither — the caller
/// then shows "not a valid invite" instead of joining something unknown.
String? parseMatrixInvite(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  // A bare room id or alias.
  if (_isRoomIdOrAlias(trimmed)) return trimmed;

  // A matrix.to link: the target sits in the fragment after `#/`.
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.toLowerCase() != 'matrix.to') return null;
  final fragment = uri.fragment; // e.g. `/!abc:hs.example` or `/%23room:hs`
  if (!fragment.startsWith('/')) return null;
  // The fragment may carry extra `/`-separated parts (a via server, an event id);
  // the room target is the first segment.
  final firstSegment = fragment.substring(1).split('/').first;
  if (firstSegment.isEmpty) return null;
  final decoded = Uri.decodeComponent(firstSegment);
  return _isRoomIdOrAlias(decoded) ? decoded : null;
}

/// A Matrix room id starts with `!`, an alias with `#`; both carry a `:server`.
bool _isRoomIdOrAlias(String s) =>
    (s.startsWith('!') || s.startsWith('#')) && s.contains(':') && s.length > 3;
