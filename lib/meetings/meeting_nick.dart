// Unique anonymous MUC nicks for meeting joins. A reused nick collides in a
// MUC (code 409 conflict) and — worse — makes a participant linkable across
// rooms and sessions by any server that sees presence. Each join therefore
// gets a fresh `ocideck-<random>` occupant name; nothing here is stable or
// derived from identity.
//
// 8 hex chars from Random.secure: 32 bits of collision space is tight for a
// cryptographic ID but right for a throwaway room nick — the MUC rejects a
// collision rather than silently merging occupants, so the failure mode of
// an astronomically unlucky draw is a retry, not a confused roster.

import 'dart:math';

/// A fresh per-join MUC nickname like `ocideck-3f9a2b7c`. [random] is
/// injectable so tests stay deterministic.
String uniqueMeetingNick([Random? random]) {
  final r = random ?? Random.secure();
  final value = r.nextInt(0x100000000);
  return 'ocideck-${value.toRadixString(16).padLeft(8, '0')}';
}
