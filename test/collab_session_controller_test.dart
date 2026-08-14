import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_log_store.dart';
import 'package:ocideck/collab/collab_session_controller.dart';
import 'package:ocideck/collab/collab_session_launch.dart';
import 'package:ocideck/collab/handover_coordinator.dart';
import 'package:ocideck/collab/webdav_async_transport.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

const _noTick = Duration(hours: 1);

Slide slide(
  String id, {
  String title = '',
  List<List<String>> table = const [],
}) => Slide(id: id, type: SlideType.bullets, title: title, tableRows: table);

/// A tab: a mutable deck plus the controller bridging it to a session. [edit]
/// mutates the deck and feeds it to the controller, the way a notifier would.
class _Tab {
  _Tab(this.deck, CollabLaunch launch) : _coordinator = launch.coordinator {
    ctrl = CollabSessionController(
      session: launch.session,
      readDeck: () => deck,
      writeDeck: (d) => deck = d,
    );
  }
  Deck deck;
  final HandoverCoordinator _coordinator;
  late final CollabSessionController ctrl;

  void edit(Deck d) {
    deck = d;
    ctrl.onLocalEdit(d);
  }

  Future<void> dispose() async {
    await _coordinator.dispose();
    await ctrl.dispose();
  }
}

/// Drive the async log forward deterministically instead of waiting on timers.
Future<void> _sync(List<_Tab> tabs) async {
  for (final t in tabs) {
    await (t.ctrl.session.transport as WebdavAsyncTransport).poll();
  }
  await pumpEventQueue();
}

void main() {
  group('CollabSessionController', () {
    test('a host edit reaches the guest', () async {
      final store = InMemoryCollabLogStore();
      final host = _Tab(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'old')],
        ),
        await hostCollabSession(
          store: store,
          deck: Deck(
            title: 'd',
            slides: [slide('a', title: 'old')],
          ),
          participantId: 'host',
          pollInterval: _noTick,
        ),
      );
      final guest = _Tab(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'old')],
        ),
        await joinCollabSession(
          store: store,
          localDeck: Deck(
            title: 'd',
            slides: [slide('a', title: 'old')],
          ),
          participantId: 'guest',
          pollInterval: _noTick,
        ),
      );
      await pumpEventQueue();

      host.edit(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'new')],
        ),
      );
      await _sync([host, guest]);

      expect(guest.deck.slides.single.title, 'new');

      await host.dispose();
      await guest.dispose();
    });

    test('a guest edit reaches the host (intent round-trip)', () async {
      final store = InMemoryCollabLogStore();
      final baseline = Deck(
        title: 'd',
        slides: [slide('a', title: 'x')],
      );
      final host = _Tab(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'x')],
        ),
        await hostCollabSession(
          store: store,
          deck: baseline,
          participantId: 'host',
          pollInterval: _noTick,
        ),
      );
      final guest = _Tab(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'x')],
        ),
        await joinCollabSession(
          store: store,
          localDeck: Deck(
            title: 'd',
            slides: [slide('a', title: 'x')],
          ),
          participantId: 'guest',
          pollInterval: _noTick,
        ),
      );
      await pumpEventQueue();

      guest.edit(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'from-guest')],
        ),
      );
      await _sync([host, guest]); // host applies the intent, rebroadcasts
      await _sync([host, guest]); // guest applies the authoritative op
      expect(host.deck.slides.single.title, 'from-guest');
      expect(guest.deck.slides.single.title, 'from-guest');

      await host.dispose();
      await guest.dispose();
    });

    test('merge keeps local non-syncable fields across a remote edit', () async {
      final store = InMemoryCollabLogStore();
      final host = _Tab(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'old')],
        ),
        await hostCollabSession(
          store: store,
          deck: Deck(
            title: 'd',
            slides: [slide('a', title: 'old')],
          ),
          participantId: 'host',
          pollInterval: _noTick,
        ),
      );
      final guest = _Tab(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'old')],
        ),
        await joinCollabSession(
          store: store,
          localDeck: Deck(
            title: 'd',
            slides: [slide('a', title: 'old')],
          ),
          participantId: 'guest',
          pollInterval: _noTick,
        ),
      );
      await pumpEventQueue();

      // The guest adds table rows locally — a non-syncable edit, so nothing is
      // submitted, but it must survive a remote change to the same slide.
      guest.edit(
        Deck(
          title: 'd',
          slides: [
            slide(
              'a',
              title: 'old',
              table: const [
                ['cell'],
              ],
            ),
          ],
        ),
      );

      host.edit(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'renamed')],
        ),
      );
      await _sync([host, guest]);

      expect(
        guest.deck.slides.single.title,
        'renamed',
        reason: 'remote applied',
      );
      expect(guest.deck.slides.single.tableRows, [
        ['cell'],
      ], reason: 'local non-syncable field preserved through the merge');

      await host.dispose();
      await guest.dispose();
    });

    test('adding a slide reaches the guest', () async {
      final store = InMemoryCollabLogStore();
      final host = _Tab(
        Deck(title: 'd', slides: [slide('a')]),
        await hostCollabSession(
          store: store,
          deck: Deck(title: 'd', slides: [slide('a')]),
          participantId: 'host',
          pollInterval: _noTick,
        ),
      );
      final guest = _Tab(
        Deck(title: 'd', slides: [slide('a')]),
        await joinCollabSession(
          store: store,
          localDeck: Deck(title: 'd', slides: [slide('a')]),
          participantId: 'guest',
          pollInterval: _noTick,
        ),
      );
      await pumpEventQueue();

      host.edit(
        Deck(
          title: 'd',
          slides: [
            slide('a'),
            slide('b', title: 'two'),
          ],
        ),
      );
      await _sync([host, guest]);

      expect(guest.deck.slides.map((s) => s.id), ['a', 'b']);
      expect(guest.deck.slides.last.title, 'two');

      await host.dispose();
      await guest.dispose();
    });

    test('re-feeding the applied deck submits nothing (echo guard)', () async {
      final store = InMemoryCollabLogStore();
      final host = _Tab(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'old')],
        ),
        await hostCollabSession(
          store: store,
          deck: Deck(
            title: 'd',
            slides: [slide('a', title: 'old')],
          ),
          participantId: 'host',
          pollInterval: _noTick,
        ),
      );
      final guest = _Tab(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'old')],
        ),
        await joinCollabSession(
          store: store,
          localDeck: Deck(
            title: 'd',
            slides: [slide('a', title: 'old')],
          ),
          participantId: 'guest',
          pollInterval: _noTick,
        ),
      );
      await pumpEventQueue();

      host.edit(
        Deck(
          title: 'd',
          slides: [slide('a', title: 'new')],
        ),
      );
      await _sync([host, guest]);
      final opsAfterSync = (await store.listSequences()).length;

      // A notifier firing after the controller wrote the merged deck: the guest
      // re-feeds its own deck. It matches the session, so the diff is empty.
      guest.ctrl.onLocalEdit(guest.deck);
      await pumpEventQueue();

      expect(
        (await store.listSequences()).length,
        opsAfterSync,
        reason: 'echoing the session deck must not append an op',
      );

      await host.dispose();
      await guest.dispose();
    });
  });
}
