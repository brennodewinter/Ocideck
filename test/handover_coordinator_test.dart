import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_codec.dart';
import 'package:ocideck/collab/collab_log_store.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/collab_snapshot.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/handover_coordinator.dart';
import 'package:ocideck/collab/webdav_async_transport.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

// Handover is driven by *counting polls*, never a wall-clock: every test advances
// the log and the decision by calling `party.sync()` an exact number of times.
// The seed read of the beacon sets the staleness baseline, so a frozen authority
// is "gone" after `staleThreshold` *further* reads — that off-by-one is spec, not
// an accident of the code, and the tests count from it.
const _noTick = Duration(hours: 1);

Deck _deck() => Deck(
  title: 'd',
  slides: [Slide(id: 'a', type: SlideType.bullets, title: 't')],
);

/// Seed a session sidecar as a host would: a baseline plus an opening beacon
/// naming [owner] as the authority (an owner) at [tick].
Future<void> _seed(
  CollabLogStore store, {
  String owner = 'host',
  int tick = 1,
}) async {
  await store.writeSnapshot(
    jsonEncode(CollabSnapshot.capture(_deck(), 0).toJson()),
  );
  await store.writeBeacon(
    jsonEncode({'authority': owner, 'authorityIsOwner': true, 'tick': tick}),
  );
}

/// A participant: session + transport + coordinator over a shared [store].
class _Party {
  _Party(this.session, this.transport, this.coordinator);
  final CollabSession session;
  final WebdavAsyncTransport transport;
  final HandoverCoordinator coordinator;

  bool get isAuthority => session.isAuthority;
  // syncNow drives poll + decide; the pump flushes the op stream so an assertion
  // right after a sync sees the applied deck/version, not a pending microtask.
  Future<void> sync() async {
    await coordinator.syncNow();
    await pumpEventQueue();
  }

  Future<void> dispose() async {
    await coordinator.dispose();
    await session.dispose();
  }
}

_Party _party(
  CollabLogStore store,
  String pid, {
  required bool owner,
  required bool authority,
  int staleThreshold = 3,
  int seqSteadyThreshold = 2,
  int claimSpread = 1, // backoff 0 by default — deterministic thresholds
  int heartbeatFailThreshold = 3,
}) {
  final transport = WebdavAsyncTransport(
    store: store,
    participantId: pid,
    pollInterval: _noTick,
  );
  final session = CollabSession(
    initialDeck: _deck(),
    transport: transport,
    isAuthority: authority,
  );
  final coordinator = HandoverCoordinator(
    session: session,
    transport: transport,
    isOwner: owner,
    staleThreshold: staleThreshold,
    seqSteadyThreshold: seqSteadyThreshold,
    claimSpread: claimSpread,
    heartbeatFailThreshold: heartbeatFailThreshold,
  );
  return _Party(session, transport, coordinator);
}

Future<Map<String, Object?>> _beacon(CollabLogStore store) async =>
    jsonDecode((await store.readBeacon())!) as Map<String, Object?>;

SetSlideField _edit(String author, SlideField field, String value) =>
    SetSlideField(
      version: 0,
      authorId: author,
      slideId: 'a',
      field: field,
      value: value,
    );

/// The op versions present in the numbered log, in sequence order — the
/// invariant surface the tests assert on (a duplicate or a gap here is a real
/// version collision, which deck equality would hide).
Future<List<int>> _logVersions(CollabLogStore store) async {
  final versions = <int>[];
  for (final seq in await store.listSequences()) {
    final env = jsonDecode(await store.read(seq)) as Map<String, Object?>;
    if (env['kind'] == 'op') {
      versions.add((env['op'] as Map)['version'] as int);
    }
  }
  return versions;
}

void main() {
  group('HandoverCoordinator — heartbeat and detection', () {
    test('only the authority advances the beacon tick', () async {
      final store = InMemoryCollabLogStore();
      await _seed(store, owner: 'host', tick: 1);
      final host = _party(store, 'host', owner: true, authority: true);
      final guest = _party(store, 'guest', owner: false, authority: false);
      addTearDown(host.dispose);
      addTearDown(guest.dispose);

      final start = (await _beacon(store))['tick'] as int;
      await host.sync();
      await host.sync();
      await host.sync();
      expect(
        (await _beacon(store))['tick'],
        start + 3,
        reason: 'the authority bumps the tick once per poll',
      );

      // The owner drops; the guest polling does not move the tick.
      final frozen = (await _beacon(store))['tick'] as int;
      await guest.sync();
      await guest.sync();
      await guest.sync();
      expect(
        (await _beacon(store))['tick'],
        frozen,
        reason: 'a follower never heartbeats',
      );
      expect(guest.isAuthority, isFalse);
    });
  });

  group('HandoverCoordinator — election', () {
    test(
      'a successor claims exactly on the staleness threshold, not before',
      () async {
        final store = InMemoryCollabLogStore();
        await _seed(store, owner: 'host', tick: 5);
        final guest = _party(store, 'guest', owner: false, authority: false);
        addTearDown(guest.dispose);

        // Owner is gone from the start (never synced). Seed read + 2 stale reads is
        // below the threshold of 3.
        await guest.sync(); // seed read: stale 0
        await guest.sync(); // stale 1
        await guest.sync(); // stale 2
        expect(guest.isAuthority, isFalse, reason: 'still below the threshold');

        await guest.sync(); // stale 3 — claim
        expect(guest.isAuthority, isTrue);
        final beacon = await _beacon(store);
        expect(beacon['authority'], 'guest');
        expect(
          beacon['authorityIsOwner'],
          isFalse,
          reason: 'a temporary, non-owner authority',
        );
      },
    );

    test(
      'a lone caught-up guest always eventually takes over (liveness)',
      () async {
        final store = InMemoryCollabLogStore();
        await _seed(store, owner: 'host', tick: 1);
        // Full default spread: the backoff is unknown but bounded by staleThreshold
        // + claimSpread, so enough polls must produce a takeover.
        final guest = _party(
          store,
          'lonely-guest',
          owner: false,
          authority: false,
          claimSpread: 8,
        );
        addTearDown(guest.dispose);

        for (var i = 0; i < 3 + 8 + 1; i++) {
          await guest.sync();
        }
        expect(
          guest.isAuthority,
          isTrue,
          reason: 'no permanent stall when a peer can work',
        );
      },
    );

    test(
      'the caught-up guard refuses a claim while a record is unseen (a gap)',
      () async {
        final store = InMemoryCollabLogStore();
        await _seed(store, owner: 'host', tick: 1);
        // The dropped owner's last two ops: seq 1 is visible, seq 2 is missing (an
        // upload the successor's listing does not show yet) and seq 3 is present.
        await store.append(1, jsonEncode({'kind': 'x', 'from': 'host'}));
        await store.append(3, jsonEncode({'kind': 'x', 'from': 'host'}));
        final guest = _party(store, 'guest', owner: false, authority: false);
        addTearDown(guest.dispose);

        // Even well past the staleness threshold, the gap keeps `isCaughtUp` false,
        // so the successor does not resume the version stream over an unseen record.
        for (var i = 0; i < 6; i++) {
          await guest.sync();
        }
        expect(
          guest.isAuthority,
          isFalse,
          reason: 'a gap blocks the takeover (fail-closed)',
        );

        // The missing record arrives; now caught up, the successor may take over.
        await store.append(2, jsonEncode({'kind': 'x', 'from': 'host'}));
        for (var i = 0; i < 4; i++) {
          await guest.sync();
        }
        expect(guest.isAuthority, isTrue);
      },
    );

    test('the sequence-steady guard waits out WebDAV list-lag before claiming', () async {
      final inner = InMemoryCollabLogStore();
      // revealAfter (4) is deliberately GREATER than staleThreshold (2): the
      // record is still unseen at the poll where a frozen tick alone would let
      // the successor claim, so it is the sequence-steady guard — not staleness
      // — that must hold the claim back. Remove that guard (seqSteadyThreshold
      // 0) and the first assertion below flips, which is what pins it.
      final store = _LaggyStore(inner, revealAfter: 4);
      await _seed(store, owner: 'host', tick: 1);
      // The dropped owner's final op is appended but its visibility lags: the
      // successor's first listings do not show it. The steadiness guard must
      // hold the claim until the record surfaces and is applied — otherwise the
      // successor resumes past it and every replica but itself keeps it.
      final opRecord = jsonEncode({
        'kind': 'op',
        'from': 'host',
        'op': deckOpToJson(
          const SetSlideField(
            version: 1,
            authorId: 'host',
            slideId: 'a',
            field: SlideField.title,
            value: 'late',
          ),
        ),
      });
      await store.append(1, opRecord);
      final guest = _party(
        store,
        'guest',
        owner: false,
        authority: false,
        staleThreshold: 2,
        seqSteadyThreshold: 3,
      );
      addTearDown(guest.dispose);

      // Three polls: the tick has been frozen past staleThreshold (2) and the
      // successor believes it is caught up (the lagging record is invisible, so
      // knownMaxSeq is still 0). Only the steadiness guard keeps it a follower.
      await guest.sync();
      await guest.sync();
      await guest.sync();
      expect(
        guest.isAuthority,
        isFalse,
        reason: 'stale + apparently caught up, but seq-steady blocks the claim',
      );
      expect(
        guest.session.version,
        0,
        reason: 'the lagging record has not surfaced yet',
      );

      // Keep polling: the record surfaces (bumping knownMaxSeq, which resets the
      // steadiness counter), is applied, and only then — once the sequence is
      // truly steady — does the successor take over, with the record included.
      var claimedBeforeSeeingSeq1 = false;
      for (var i = 0; i < 8; i++) {
        await guest.sync();
        if (guest.isAuthority && guest.session.version < 1) {
          claimedBeforeSeeingSeq1 = true;
          break;
        }
      }
      expect(
        claimedBeforeSeeingSeq1,
        isFalse,
        reason: 'never claim while the in-flight record is unseen',
      );
      expect(
        guest.session.version,
        1,
        reason: 'the lagging op was applied first',
      );
      expect(
        guest.isAuthority,
        isTrue,
        reason: 'then the successor takes over',
      );
    });
  });

  group('HandoverCoordinator — fail-closed', () {
    test('a malformed beacon is treated as absent: no claim, no throw', () async {
      final store = InMemoryCollabLogStore();
      await store.writeSnapshot(
        jsonEncode(CollabSnapshot.capture(_deck(), 0).toJson()),
      );
      final guest = _party(store, 'guest', owner: false, authority: false);
      addTearDown(guest.dispose);

      for (final bad in <String>[
        'not json',
        '"a string"',
        '{"authority":"x"}', // missing fields
        '{"authority":"x","authorityIsOwner":true,"tick":"nan"}', // tick not int
        '{"authority":1,"authorityIsOwner":true,"tick":1}', // authority not string
      ]) {
        await store.writeBeacon(bad);
        await guest.sync();
        await guest.sync();
        await guest.sync();
        await guest.sync();
      }
      expect(
        guest.isAuthority,
        isFalse,
        reason: 'a corrupt beacon never grants authority',
      );
    });

    test('an absent beacon (a pre-handover session) is a no-op', () async {
      final store = InMemoryCollabLogStore();
      await store.writeSnapshot(
        jsonEncode(CollabSnapshot.capture(_deck(), 0).toJson()),
      );
      final guest = _party(store, 'guest', owner: false, authority: false);
      addTearDown(guest.dispose);

      for (var i = 0; i < 8; i++) {
        await guest.sync();
      }
      expect(guest.isAuthority, isFalse);
    });

    test('a store read that throws changes nothing', () async {
      final store = _FaultyStore(InMemoryCollabLogStore());
      await _seed(store, owner: 'host', tick: 1);
      final guest = _party(store, 'guest', owner: false, authority: false);
      addTearDown(guest.dispose);

      store.failReadBeacon = true;
      for (var i = 0; i < 8; i++) {
        await guest.sync(); // must not throw, must not claim
      }
      expect(guest.isAuthority, isFalse);
    });

    test(
      'an incumbent whose heartbeat write keeps failing steps down',
      () async {
        final store = _FaultyStore(InMemoryCollabLogStore());
        await _seed(store, owner: 'host', tick: 1);
        final host = _party(
          store,
          'host',
          owner: true,
          authority: true,
          heartbeatFailThreshold: 3,
        );
        addTearDown(host.dispose);

        await host.sync(); // one good heartbeat
        expect(host.isAuthority, isTrue);

        store.failWriteBeacon = true;
        await host.sync();
        await host.sync();
        expect(
          host.isAuthority,
          isTrue,
          reason: 'tolerates a couple of failures',
        );
        await host.sync();
        expect(
          host.isAuthority,
          isFalse,
          reason:
              'stops assigning versions once it can no longer publish liveness',
        );
      },
    );
  });

  group('HandoverCoordinator — takeover and hand-back', () {
    test(
      'a successor resumes the version stream without a collision',
      () async {
        final store = InMemoryCollabLogStore();
        await _seed(store, owner: 'host', tick: 1);
        final host = _party(store, 'host', owner: true, authority: true);
        final guest = _party(store, 'guest', owner: false, authority: false);
        addTearDown(host.dispose);
        addTearDown(guest.dispose);

        // The owner edits up to version 1, then drops.
        await host.session.submit(_edit('host', SlideField.title, 'v1'));
        await guest.sync(); // guest catches up to v1
        expect(guest.session.version, 1);

        // The owner is gone; the guest takes over and edits.
        for (var i = 0; i < 4; i++) {
          await guest.sync();
        }
        expect(guest.isAuthority, isTrue);
        await guest.session.submit(_edit('guest', SlideField.subtitle, 'v2'));

        expect(guest.session.version, 2, reason: 'resumed from 1, not reset');
        expect(await _logVersions(store), [
          1,
          2,
        ], reason: 'no duplicate, no gap');
      },
    );

    test('the owner reclaims authority from a live guest (hand-back)', () async {
      final store = InMemoryCollabLogStore();
      await _seed(store, owner: 'host', tick: 1);
      final guest = _party(store, 'guest', owner: false, authority: false);
      addTearDown(guest.dispose);

      // The guest takes over while the owner is gone.
      for (var i = 0; i < 4; i++) {
        await guest.sync();
      }
      expect(guest.isAuthority, isTrue);
      expect((await _beacon(store))['authorityIsOwner'], isFalse);

      // The owner returns as a fresh participant (a restart) and reclaims.
      final owner = _party(store, 'host-2', owner: true, authority: false);
      addTearDown(owner.dispose);
      await owner.sync();
      expect(
        owner.isAuthority,
        isTrue,
        reason: 'the owner reclaims a live stand-in',
      );
      expect((await _beacon(store))['authority'], 'host-2');
      expect((await _beacon(store))['authorityIsOwner'], isTrue);

      // The stand-in sees the owner back and steps down — no lasting split brain.
      await guest.sync();
      expect(guest.isAuthority, isFalse);
    });

    test('a returning owner reclaims via election when no one stood in', () async {
      // The core #1004 case: the owner closes the app and reopens before any
      // guest took over. The beacon is frozen and still names the old owner with
      // authorityIsOwner:true, so the hand-back branch (which needs a *guest*
      // stand-in) does not fire — the returning owner must reclaim through the
      // election path instead, and land back as an owner authority.
      final store = InMemoryCollabLogStore();
      await _seed(store, owner: 'old-owner', tick: 1);

      final owner = _party(store, 'new-owner', owner: true, authority: false);
      addTearDown(owner.dispose);

      await owner.sync(); // seed read
      await owner.sync(); // stale 1
      await owner.sync(); // stale 2
      expect(owner.isAuthority, isFalse, reason: 'still below the threshold');

      await owner.sync(); // stale 3 — claim via election
      expect(owner.isAuthority, isTrue);
      final beacon = await _beacon(store);
      expect(beacon['authority'], 'new-owner');
      expect(
        beacon['authorityIsOwner'],
        isTrue,
        reason: 'the reclaiming owner is an owner authority, and may persist',
      );
    });

    test(
      'a guest does not reclaim from another guest, nor from the owner',
      () async {
        final store = InMemoryCollabLogStore();
        await _seed(store, owner: 'host', tick: 1);
        final host = _party(store, 'host', owner: true, authority: true);
        final guest = _party(store, 'guest', owner: false, authority: false);
        addTearDown(host.dispose);
        addTearDown(guest.dispose);

        // With the owner alive and heartbeating, the guest always defers.
        for (var i = 0; i < 8; i++) {
          await host.sync();
          await guest.sync();
        }
        expect(
          guest.isAuthority,
          isFalse,
          reason: 'a live owner is never displaced',
        );
        expect(host.isAuthority, isTrue);
      },
    );
  });

  group('HandoverCoordinator — convergence to one authority', () {
    test('the first claimant wins; a second caught-up guest defers', () async {
      final store = InMemoryCollabLogStore();
      await _seed(store, owner: 'host', tick: 1);
      final a = _party(store, 'guest-a', owner: false, authority: false);
      final b = _party(store, 'guest-b', owner: false, authority: false);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      // Both accumulate staleness; a claims first (synced first past the
      // threshold), and its fresh beacon tick tells b the authority is alive.
      for (var i = 0; i < 3; i++) {
        await a.sync();
        await b.sync();
      }
      await a.sync(); // a claims on its 4th sync
      expect(a.isAuthority, isTrue);
      await b.sync(); // b reads a's fresh beacon and defers
      expect(b.isAuthority, isFalse, reason: 'exactly one authority survives');
      expect((await _beacon(store))['authority'], 'guest-a');
    });

    test(
      'the documented residual: simultaneous authorities diverge for the loser',
      () async {
        // The transient dual-authority the design accepts for Fase 0.5 cannot occur
        // in this deterministic store, so we force it and pin the *recovery*: every
        // replica that reads the log in order converges, while the losing authority
        // keeps its own optimistic op — that divergence, and the duplicate version
        // it leaves in the log, is the residual §5.3 documents.
        final store = InMemoryCollabLogStore();
        await _seed(store, owner: 'host', tick: 1);
        final a = _party(
          store,
          'a',
          owner: false,
          authority: true,
        ); // forced authority
        final b = _party(
          store,
          'b',
          owner: false,
          authority: true,
        ); // forced authority
        final watcher = _party(store, 'watch', owner: false, authority: false);
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        addTearDown(watcher.dispose);

        await a.session.submit(_edit('a', SlideField.title, 'A-wins'));
        await b.session.submit(_edit('b', SlideField.title, 'B-wins'));

        // A follower reads the log in canonical order: a's op (seq 1) applies, b's
        // duplicate-version op (seq 2) is dropped.
        await watcher.sync();
        expect(watcher.session.deck.slides.single.title, 'A-wins');
        expect(a.session.deck.slides.single.title, 'A-wins');
        expect(
          b.session.deck.slides.single.title,
          'B-wins',
          reason:
              'the losing authority keeps its own op — the documented residual',
        );
        expect(
          await _logVersions(store),
          [1, 1],
          reason: 'the duplicate version is real; deck equality would hide it',
        );
      },
    );
  });

  group('HandoverCoordinator — authorityChanged', () {
    test('fires when the observed authority changes', () async {
      final store = InMemoryCollabLogStore();
      await _seed(store, owner: 'host', tick: 1);
      final guest = _party(store, 'guest', owner: false, authority: false);
      addTearDown(guest.dispose);

      var changes = 0;
      guest.coordinator.authorityChanged.listen((_) => changes++);

      // Take over: the observed authority goes host -> guest.
      for (var i = 0; i < 5; i++) {
        await guest.sync();
      }
      await pumpEventQueue();
      expect(guest.isAuthority, isTrue);
      expect(
        changes,
        greaterThanOrEqualTo(1),
        reason: 'the authority flip is signalled',
      );
    });
  });
}

/// A store wrapper that fails a chosen operation on demand, to drive the
/// fail-closed paths (a read/write that throws).
class _FaultyStore implements CollabLogStore {
  _FaultyStore(this._inner);
  final CollabLogStore _inner;
  bool failReadBeacon = false;
  bool failWriteBeacon = false;

  @override
  Future<String?> readBeacon() async {
    if (failReadBeacon) throw StateError('read failed');
    return _inner.readBeacon();
  }

  @override
  Future<void> writeBeacon(String beacon) async {
    if (failWriteBeacon) throw StateError('write failed');
    return _inner.writeBeacon(beacon);
  }

  @override
  Future<List<int>> listSequences() => _inner.listSequences();
  @override
  Future<String> read(int seq) => _inner.read(seq);
  @override
  Future<bool> append(int seq, String record) => _inner.append(seq, record);
  @override
  Future<String?> readSnapshot() => _inner.readSnapshot();
  @override
  Future<void> writeSnapshot(String snapshot) => _inner.writeSnapshot(snapshot);
}

/// A store wrapper that delays the visibility of freshly appended sequences, to
/// simulate WebDAV's lack of cross-client read-your-writes: a record is present
/// but does not show in a listing until [revealAfter] listings have passed.
class _LaggyStore implements CollabLogStore {
  _LaggyStore(this._inner, {this.revealAfter = 2});
  final CollabLogStore _inner;
  final int revealAfter;
  int _listCalls = 0;
  final Map<int, int> _visibleAt = {};

  @override
  Future<List<int>> listSequences() async {
    _listCalls++;
    final all = await _inner.listSequences();
    return all.where((s) => (_visibleAt[s] ?? 0) <= _listCalls).toList()
      ..sort();
  }

  @override
  Future<bool> append(int seq, String record) async {
    final ok = await _inner.append(seq, record);
    if (ok) _visibleAt[seq] = _listCalls + revealAfter;
    return ok;
  }

  @override
  Future<String> read(int seq) => _inner.read(seq);
  @override
  Future<String?> readSnapshot() => _inner.readSnapshot();
  @override
  Future<void> writeSnapshot(String snapshot) => _inner.writeSnapshot(snapshot);
  @override
  Future<String?> readBeacon() => _inner.readBeacon();
  @override
  Future<void> writeBeacon(String beacon) => _inner.writeBeacon(beacon);
}
