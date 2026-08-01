// The little coloured markers on a slide in the list that show which co-authors
// are looking at it (SELF_ENCRYPTED_RELAY.md §6, "iedereen ziet iedereen"). Only
// rendered during a live Matrix session with peers on that slide, so it never
// touches the slide list outside collaboration (and leaves the goldens alone).

import 'package:flutter/material.dart';

import '../../collab/matrix_presence.dart';
import '../../theme/app_theme.dart';

/// Wrap a slide thumbnail [child] with presence dots for whoever in [presence]
/// is on [slideId], keeping [key] at the top so the reorderable list and
/// scroll-to keep working. Returns the bare child (under the key) when no
/// co-author is on the slide, so the list looks exactly as it always did outside
/// a session. Filtering lives here to keep it out of the slide-list state class.
Widget slideWithPresence({
  required Key key,
  required Widget child,
  required List<PeerPresence> presence,
  required String slideId,
}) {
  final here = presence.where((p) => p.slideId == slideId).toList();
  if (here.isEmpty) return KeyedSubtree(key: key, child: child);
  return KeyedSubtree(
    key: key,
    child: Stack(
      children: [
        child,
        Positioned(top: 4, right: 4, child: SlidePresenceDots(here)),
      ],
    ),
  );
}

/// A row of small avatars, one per co-author currently on this slide. Each shows
/// an initial from the user id and a stable colour, with the full id as tooltip.
/// Caps the row and adds a "+N" so a crowded slide stays readable.
class SlidePresenceDots extends StatelessWidget {
  const SlidePresenceDots(this.peers, {super.key, this.maxShown = 3});

  final List<PeerPresence> peers;
  final int maxShown;

  static Color colorFor(String id) =>
      AppTheme.presencePalette[id.hashCode.abs() %
          AppTheme.presencePalette.length];

  static String _initial(String userId) {
    final trimmed = userId.replaceFirst('@', '').trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) return const SizedBox.shrink();
    final shown = peers.length <= maxShown
        ? peers
        : peers.take(maxShown - 1).toList();
    final overflow = peers.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final peer in shown)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Tooltip(
              message: peer.userId,
              child: _dot(colorFor(peer.deviceId), _initial(peer.userId)),
            ),
          ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: _dot(AppTheme.slate500, '+$overflow'),
          ),
      ],
    );
  }

  Widget _dot(Color color, String label) => Container(
    width: 16,
    height: 16,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );
}
