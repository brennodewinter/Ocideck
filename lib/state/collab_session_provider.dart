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

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../collab/collab.dart';
import 'deck_provider.dart';
import 'editor_provider.dart';
import 'matrix_client_provider.dart';
import 'secret_store_provider.dart';
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
    this.isTemporaryAuthority = false,
    this.inviteLink,
    this.isMatrix = false,
    this.presence = const [],
    this.chatMessages = const [],
  });

  final CollabPhase phase;
  final CollabRole? role;

  /// A short machine key for the failure (e.g. `not-webdav`, `no-baseline`), so
  /// the UI localises the message rather than showing a raw exception.
  final String? error;

  /// True when this tab is a *guest* currently standing in as the authority
  /// because the owner dropped (§5.3). It keeps the session alive but must not
  /// persist; the UI surfaces this so the co-author knows their work is not being
  /// saved to the shared source until the owner returns.
  final bool isTemporaryAuthority;

  /// The link to share so others can join, set only when *hosting* over Matrix
  /// (a new room per session, §6.5). Null for a guest, and for WebDAV where
  /// joining is by the deck's own source rather than a link.
  final String? inviteLink;

  /// True for a realtime Matrix session (§6), false for a WebDAV one. Set from
  /// the moment connecting starts, so the UX layer can tell the two apart across
  /// the whole lifecycle — which feedback to show, and whether an invite link and
  /// device fingerprints are in play.
  final bool isMatrix;

  /// Where each co-author is looking, for the presence UI (§6, Matrix only).
  /// Updated as peers move; empty outside an active Matrix session.
  final List<PeerPresence> presence;

  /// The session chat, oldest first (§6, Matrix only). Grows as messages arrive
  /// and are sent; empty outside an active Matrix session.
  final List<ChatMessage> chatMessages;

  bool get isActive => phase == CollabPhase.active;
  bool get isConnecting => phase == CollabPhase.connecting;

  /// Whether saving the deck to its shared source is allowed. Only the owner
  /// persists (§5.3): a guest in an active session — including one temporarily
  /// holding authority — must not write the shared `.md`. Outside a session
  /// (idle) saving is unaffected.
  bool get canPersist => !isActive || role == CollabRole.host;

  CollabSessionState copyWith({
    CollabPhase? phase,
    CollabRole? role,
    String? error,
    bool? isTemporaryAuthority,
    String? inviteLink,
    bool? isMatrix,
    List<PeerPresence>? presence,
    List<ChatMessage>? chatMessages,
  }) => CollabSessionState(
    phase: phase ?? this.phase,
    role: role ?? this.role,
    error: error,
    isTemporaryAuthority: isTemporaryAuthority ?? this.isTemporaryAuthority,
    inviteLink: inviteLink ?? this.inviteLink,
    isMatrix: isMatrix ?? this.isMatrix,
    presence: presence ?? this.presence,
    chatMessages: chatMessages ?? this.chatMessages,
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
  HandoverCoordinator? _coordinator;
  MatrixCollabLaunch? _matrixLaunch;
  StreamSubscription<DeckState>? _deckSub;
  StreamSubscription<void>? _authoritySub;
  StreamSubscription<EditorState>? _presenceSub;
  bool _disposed = false;

  /// True when this tab can collaborate: its deck lives on a WebDAV source.
  bool get canCollaborate => _tab?.webdavOrigin != null;

  /// Start a session others can join.
  Future<void> host() => _begin(CollabRole.host);

  /// Join a session another author already started for this deck.
  Future<void> join() => _begin(CollabRole.guest);

  /// Host a realtime session over the app-global Matrix account (§6): a fresh
  /// encrypted room whose link — surfaced on [CollabSessionState.inviteLink] —
  /// others paste into [joinMatrix]. Works for any deck; unlike WebDAV it does
  /// not need the deck to live on a shared source.
  Future<void> hostMatrix() => _beginMatrix(CollabRole.host);

  /// Join the Matrix session named by [inviteLink].
  Future<void> joinMatrix(String inviteLink) =>
      _beginMatrix(CollabRole.guest, inviteLink: inviteLink);

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
      final launch = role == CollabRole.host
          ? await hostCollabSession(store: store, deck: deck, participantId: id)
          : await joinCollabSession(
              store: store,
              localDeck: deck,
              participantId: id,
            );
      if (_disposed) {
        await launch.coordinator.dispose();
        await launch.session.dispose();
        return;
      }
      tab.collabSession = launch.session;
      _coordinator = launch.coordinator;
      _attach(launch, deckNotifier, role);
      state = CollabSessionState(phase: CollabPhase.active, role: role);
    } catch (e) {
      state = state.copyWith(
        phase: CollabPhase.failed,
        error: role == CollabRole.guest ? 'no-baseline' : 'failed',
      );
    }
  }

  /// Wire the controller both transports share: local deck edits flow out as ops
  /// (via [DeckNotifier.stream]) and remote changes flow back merged (via
  /// [DeckNotifier.applyCollabDeck]). The WebDAV path layers authority handover
  /// on top ([_attach]); the Matrix path (§6, handover is P-E) does not.
  void _attachController(CollabSession session, DeckNotifier deckNotifier) {
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

  /// Host or join a realtime Matrix session (§6.5). Unlike [_begin] this needs no
  /// WebDAV source — only the app-global Matrix account and, for a guest, an
  /// invite link. A guest does not become active until the authority's baseline
  /// arrives, so it drives the launch's sync loop and awaits its `sessionReady`.
  Future<void> _beginMatrix(CollabRole role, {String? inviteLink}) async {
    if (state.isActive || state.isConnecting) return;
    final tab = _tab;
    final deckNotifier = _ref.read(deckProvider.notifier);
    final deck = deckNotifier.currentState.deck;
    if (tab == null || deck == null) {
      state = state.copyWith(
        phase: CollabPhase.failed,
        error: 'no-deck',
        isMatrix: true,
      );
      return;
    }
    final account = _ref.read(matrixAccountProvider);
    if (account == null || !account.isConfigured) {
      state = state.copyWith(
        phase: CollabPhase.failed,
        error: 'no-matrix-account',
        isMatrix: true,
      );
      return;
    }
    state = const CollabSessionState(
      phase: CollabPhase.connecting,
      isMatrix: true,
    );
    try {
      final client = await _ref.read(matrixClientProvider.future);
      if (_disposed) return;
      if (client == null) {
        state = state.copyWith(
          phase: CollabPhase.failed,
          error: 'no-matrix-account',
        );
        return;
      }
      final secrets = _ref.read(secretStoreProvider);
      String? link;
      final MatrixCollabLaunch launch;
      if (role == CollabRole.host) {
        final hosted = await hostMatrixCollab(
          client: client,
          secretStore: secrets,
          account: account,
          deck: deck,
        );
        launch = hosted.launch;
        link = hosted.inviteLink;
      } else {
        launch = await joinMatrixCollab(
          client: client,
          secretStore: secrets,
          account: account,
          localDeck: deck,
          inviteLink: inviteLink!,
        );
      }
      if (_disposed) return await launch.dispose();
      _matrixLaunch = launch;
      launch.start();
      // The session is live now for a host and once the baseline arrives for a
      // guest. Finish off this call so `connecting` is observable and a guest
      // does not block its caller while the baseline is in flight.
      unawaited(_finishMatrix(launch, role, link, tab, deckNotifier));
    } catch (e) {
      await _teardown();
      if (!_disposed) {
        state = state.copyWith(
          phase: CollabPhase.failed,
          error: _matrixError(role, e),
        );
      }
    }
  }

  /// Await the session becoming live (immediate for a host, baseline-gated for a
  /// guest), then attach the controller and go active. Bounded so a dead host
  /// fails the join rather than spinning forever.
  Future<void> _finishMatrix(
    MatrixCollabLaunch launch,
    CollabRole role,
    String? link,
    TabInfo tab,
    DeckNotifier deckNotifier,
  ) async {
    try {
      final session = await launch.sessionReady.timeout(
        const Duration(seconds: 45),
      );
      if (_disposed) return;
      tab.collabSession = session;
      _attachController(session, deckNotifier);
      state = CollabSessionState(
        phase: CollabPhase.active,
        role: role,
        inviteLink: link,
        isMatrix: true,
      );
      _wirePresence(launch, deckNotifier);
      _wireChat(launch);
    } on TimeoutException {
      await _teardown();
      if (!_disposed) {
        state = state.copyWith(
          phase: CollabPhase.failed,
          error: 'join-timeout',
        );
      }
    }
  }

  /// Broadcast this tab's current slide to co-authors and reflect theirs (§6,
  /// "iedereen ziet iedereen"). Announces the current selection at once, then on
  /// every selection change; a peer's move refreshes [CollabSessionState.presence].
  void _wirePresence(MatrixCollabLaunch launch, DeckNotifier deckNotifier) {
    void refresh() {
      if (_disposed) return;
      state = state.copyWith(presence: launch.presencePeers);
    }

    // Seed from whatever already arrived: a peer's presence can open on the same
    // sync that starts the session, before this callback is wired.
    refresh();
    launch.onPresenceChanged = refresh;
    void announceCurrent() {
      final deck = deckNotifier.currentState.deck;
      final index = _ref.read(editorProvider).selectedIndex;
      if (deck != null && index >= 0 && index < deck.slides.length) {
        unawaited(launch.announcePresence(deck.slides[index].id));
      }
    }

    announceCurrent();
    _presenceSub = _ref.read(editorProvider.notifier).stream.listen((editor) {
      announceCurrent();
    });
  }

  /// Reflect the session chat into the state as it grows (§6). Seeds from
  /// whatever already arrived before this callback was wired.
  void _wireChat(MatrixCollabLaunch launch) {
    void refresh() {
      if (_disposed) return;
      state = state.copyWith(chatMessages: launch.chatMessages);
    }

    refresh();
    launch.onChatChanged = refresh;
  }

  /// Send a chat message to the active Matrix session (§6). No-op otherwise.
  Future<void> sendChatMessage(String text) async {
    await _matrixLaunch?.sendChat(text);
  }

  /// Drive one Matrix sync round now, so a test can advance the session without
  /// waiting on the periodic loop. No-op outside a Matrix session.
  @visibleForTesting
  Future<void> debugMatrixSyncNow() async => _matrixLaunch?.syncNow();

  /// The devices in the running Matrix session for the verification UI (§4.3):
  /// this device plus every verified peer, each with its identity-key
  /// fingerprint. Empty outside a Matrix session.
  List<CollabParticipant> matrixParticipants() {
    final launch = _matrixLaunch;
    final account = _ref.read(matrixAccountProvider);
    if (launch == null || account == null) return const [];
    return launch.participants(account.userId);
  }

  /// Map a Matrix launch failure to a machine key the UI localises.
  static String _matrixError(CollabRole role, Object e) {
    if (e is MatrixException) {
      return switch (e.kind) {
        MatrixErrorKind.config =>
          role == CollabRole.guest ? 'bad-invite' : 'matrix-config',
        MatrixErrorKind.auth => 'matrix-auth',
        MatrixErrorKind.network => 'matrix-network',
        _ => 'matrix-failed',
      };
    }
    return role == CollabRole.guest ? 'no-baseline' : 'failed';
  }

  void _attach(
    CollabLaunch launch,
    DeckNotifier deckNotifier,
    CollabRole role,
  ) {
    final session = launch.session;
    _attachController(session, deckNotifier);
    // When the session authority changes (an owner drops, a successor takes over,
    // the owner hands back), re-drive any local edit the old authority never
    // versioned to the new one, and refresh the "temporary owner" indicator.
    _authoritySub = launch.coordinator.authorityChanged.listen((_) {
      if (_disposed) return;
      // Re-drive lost edits only when caught up. Diffing a session deck that
      // still lags the log (WebDAV gives no cross-client read-your-writes) could
      // re-emit an authoritative op still in flight and duplicate a
      // non-idempotent one like InsertSlide — a distinct, contiguous version the
      // in-order rule would not drop. A not-yet-caught-up follower recovers its
      // lost edit on its next real edit instead, which is safe.
      final transport = session.transport;
      final caughtUp =
          transport is! WebdavAsyncTransport || transport.isCaughtUp;
      if (caughtUp) {
        final deck = deckNotifier.currentState.deck;
        if (deck != null) _controller?.onLocalEdit(deck);
      }
      final temporary = role == CollabRole.guest && session.isAuthority;
      if (temporary != state.isTemporaryAuthority) {
        state = state.copyWith(isTemporaryAuthority: temporary);
      }
    });
  }

  /// End this tab's session and return to idle.
  Future<void> leave() async {
    await _teardown();
    if (!_disposed) state = const CollabSessionState();
  }

  Future<void> _teardown() async {
    await _authoritySub?.cancel();
    _authoritySub = null;
    await _presenceSub?.cancel();
    _presenceSub = null;
    await _deckSub?.cancel();
    _deckSub = null;
    await _coordinator?.dispose();
    _coordinator = null;
    await _controller?.dispose(); // disposes the session too
    _controller = null;
    // Matrix owns its session through the launch (WebDAV owns it through the
    // controller). Both dispose paths are idempotent, so disposing after the
    // controller is safe; the launch also stops its sync loop and transport.
    await _matrixLaunch?.dispose();
    _matrixLaunch = null;
    _tab?.collabSession = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _authoritySub?.cancel();
    _presenceSub?.cancel();
    _deckSub?.cancel();
    _coordinator?.dispose();
    _controller?.dispose();
    _matrixLaunch?.dispose();
    _tab?.collabSession = null;
    super.dispose();
  }
}

/// Whether the collaboration chat panel is open. App-wide (one tab's session is
/// in view at a time); toggled from the command palette, shown only while a
/// Matrix session runs.
final collabChatOpenProvider = StateProvider<bool>((ref) => false);

/// The per-tab collaboration session. Overridden in `app_shell.dart`'s
/// `_tabScope`; the root is an idle, tab-less notifier.
final collabSessionProvider =
    StateNotifierProvider<CollabSessionNotifier, CollabSessionState>(
      (ref) => CollabSessionNotifier(ref, null),
    );
