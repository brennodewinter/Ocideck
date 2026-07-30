// The per-tab owner of a collaboration session (`docs/design/COLLABORATION.md`
// §5.7) — the app glue over the transport, snapshot, diff and controller in
// `lib/collab/`. It builds a WebDAV log store from the tab's origin, hosts or
// joins a session, keeps the session on `TabInfo.collabSession`, and wires a
// [CollabSessionController] between the session and the tab's deck: local edits
// flow out as ops, remote changes flow back merged.
//
// Overridden per tab in `app_shell.dart`'s `_tabScope`, exactly like
// `deckProvider` — a collab action reads it from the same (per-tab) scope, so it
// sees the tab's own deck. The unbound root notifier is idle; nothing reads it
// outside a tab scope.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../collab/collab.dart';
import 'deck_provider.dart';
import 'tabs_provider.dart';
import 'webdav_provider.dart';

/// Whether this tab hosts the session or joined someone else's.
enum CollabRole { host, guest }

/// Where a tab's collaboration is in its lifecycle.
enum CollabPhase { idle, connecting, active, failed }

/// The observable collaboration state of one tab.
class CollabSessionState {
  const CollabSessionState({
    this.phase = CollabPhase.idle,
    this.role,
    this.error,
  });

  final CollabPhase phase;
  final CollabRole? role;

  /// A short machine key for the failure (e.g. `not-webdav`, `no-baseline`), so
  /// the UI localises the message rather than showing a raw exception.
  final String? error;

  bool get isActive => phase == CollabPhase.active;
  bool get isConnecting => phase == CollabPhase.connecting;

  CollabSessionState copyWith({
    CollabPhase? phase,
    CollabRole? role,
    String? error,
  }) => CollabSessionState(
    phase: phase ?? this.phase,
    role: role ?? this.role,
    error: error,
  );
}

/// The sidecar ops directory for a deck at [remotePath]: a folder beside the
/// deck, never the `.md` itself (P2). `decks/talk.md` → `decks/talk.ocideck-collab/ops`.
String collabSidecarOpsDir(String remotePath) {
  final base = remotePath.endsWith('.md')
      ? remotePath.substring(0, remotePath.length - 3)
      : remotePath;
  return '$base.ocideck-collab/ops';
}

/// Owns one tab's session. Construct via the per-tab override; the root gets a
/// `null` tab and stays idle.
class CollabSessionNotifier extends StateNotifier<CollabSessionState> {
  CollabSessionNotifier(this._ref, this._tab)
    : super(const CollabSessionState());

  final Ref _ref;
  final TabInfo? _tab;

  CollabSessionController? _controller;
  StreamSubscription<DeckState>? _deckSub;
  bool _disposed = false;

  /// True when this tab can collaborate: its deck lives on a WebDAV source.
  bool get canCollaborate => _tab?.webdavOrigin != null;

  /// Start a session others can join.
  Future<void> host() => _begin(CollabRole.host);

  /// Join a session another author already started for this deck.
  Future<void> join() => _begin(CollabRole.guest);

  Future<void> _begin(CollabRole role) async {
    if (state.isActive || state.isConnecting) return;
    final tab = _tab;
    final origin = tab?.webdavOrigin;
    if (tab == null || origin == null) {
      state = state.copyWith(phase: CollabPhase.failed, error: 'not-webdav');
      return;
    }
    final deckNotifier = _ref.read(deckProvider.notifier);
    final deck = deckNotifier.currentState.deck;
    if (deck == null) {
      state = state.copyWith(phase: CollabPhase.failed, error: 'no-deck');
      return;
    }
    state = const CollabSessionState(phase: CollabPhase.connecting);
    try {
      final service = await _ref.read(
        webdavServiceProvider(origin.connectionId).future,
      );
      if (_disposed) return;
      if (service == null) {
        state = state.copyWith(phase: CollabPhase.failed, error: 'no-service');
        return;
      }
      final store = WebdavCollabLogStore(
        service: service,
        opsDir: collabSidecarOpsDir(origin.remotePath),
      );
      final id = '${origin.username}-${const Uuid().v4()}';
      final session = role == CollabRole.host
          ? await hostCollabSession(store: store, deck: deck, participantId: id)
          : await joinCollabSession(
              store: store,
              localDeck: deck,
              participantId: id,
            );
      if (_disposed) {
        await session.dispose();
        return;
      }
      tab.collabSession = session;
      _attach(session, deckNotifier);
      state = CollabSessionState(phase: CollabPhase.active, role: role);
    } catch (e) {
      state = state.copyWith(
        phase: CollabPhase.failed,
        error: role == CollabRole.guest ? 'no-baseline' : 'failed',
      );
    }
  }

  void _attach(CollabSession session, DeckNotifier deckNotifier) {
    _controller = CollabSessionController(
      session: session,
      readDeck: () => deckNotifier.currentState.deck ?? session.deck,
      writeDeck: deckNotifier.applyCollabDeck,
    );
    _deckSub = deckNotifier.stream.listen((deckState) {
      final deck = deckState.deck;
      if (deck != null) _controller?.onLocalEdit(deck);
    });
  }

  /// End this tab's session and return to idle.
  Future<void> leave() async {
    await _teardown();
    if (!_disposed) state = const CollabSessionState();
  }

  Future<void> _teardown() async {
    await _deckSub?.cancel();
    _deckSub = null;
    await _controller?.dispose(); // disposes the session too
    _controller = null;
    _tab?.collabSession = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _deckSub?.cancel();
    _controller?.dispose();
    _tab?.collabSession = null;
    super.dispose();
  }
}

/// The per-tab collaboration session. Overridden in `app_shell.dart`'s
/// `_tabScope`; the root is an idle, tab-less notifier.
final collabSessionProvider =
    StateNotifierProvider<CollabSessionNotifier, CollabSessionState>(
      (ref) => CollabSessionNotifier(ref, null),
    );
