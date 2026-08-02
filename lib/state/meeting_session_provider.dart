// The optional video-calls module and its root-scoped live session
// (`docs/design/NATIVE_CALLS.md` §1, §7 F1; §9 for the root scope).
//
// Two things live here:
//   1. The module toggle — same shape as every other optional module
//      (`asset_rights_module_provider.dart`): a prefs-backed on/off, default OFF.
//   2. The active [MeetingSession], held **root-scoped** so a call survives a
//      deck-tab switch (NATIVE_CALLS.md §9). This deliberately does NOT copy
//      `collabSessionProvider`'s per-tab override — a meeting is app-global, like
//      `matrixClientProvider`.
//
// There is no in-app join flow yet: a real [MeetingProvider] adapter (Jitsi over
// lib/xmpp/ + flutter_webrtc) arrives in F3. Until then [meetingSessionProvider]
// stays null in the running app, and the call panel it feeds is exercised by
// tests with a fake session. This is the structural foundation, wired so it is
// not dead code, not a user-operable feature yet.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meetings/meeting_provider.dart';
import '../utils/log.dart';

const videoCallsModuleEnabledKey = 'videoCallsModuleEnabled';

final videoCallsModuleProvider =
    NotifierProvider<VideoCallsModuleNotifier, VideoCallsModuleState>(
      VideoCallsModuleNotifier.new,
    );

/// Whether the video-calls switch is on (the stored preference).
final videoCallsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(videoCallsModuleProvider.select((state) => state.enabled));
});

/// The features are visible when the module is on **or** a call is live — never
/// strand an active call because the toggle is off (the `collaboration` module's
/// reveal rule, `NATIVE_CALLS.md` §8 backend exclusivity notwithstanding: this is
/// purely a UI-reveal gate).
final videoCallsRevealProvider = Provider<bool>((ref) {
  return ref.watch(videoCallsEnabledProvider) ||
      ref.watch(meetingSessionProvider) != null;
});

/// The active meeting, root-scoped (survives a deck-tab switch), or null when no
/// call is running.
final meetingSessionProvider =
    NotifierProvider<MeetingSessionNotifier, MeetingSession?>(
      MeetingSessionNotifier.new,
    );

class VideoCallsModuleState {
  final bool enabled;
  final bool loading;

  const VideoCallsModuleState({this.enabled = false, this.loading = true});
}

class VideoCallsModuleNotifier extends Notifier<VideoCallsModuleState> {
  @override
  VideoCallsModuleState build() {
    _initialize();
    return const VideoCallsModuleState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = VideoCallsModuleState(
        enabled: prefs.getBool(videoCallsModuleEnabledKey) ?? false,
        loading: false,
      );
    } catch (e, s) {
      logError('VideoCallsModuleNotifier: voorkeur lezen', e, s);
      state = const VideoCallsModuleState(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = VideoCallsModuleState(enabled: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(videoCallsModuleEnabledKey, value);
    } catch (e, s) {
      logError('VideoCallsModuleNotifier: voorkeur schrijven', e, s);
    }
  }
}

/// Holds the live [MeetingSession]. An adapter's `join(...)` result is handed to
/// [adopt]; [leave] ends the call and clears it. Root-scoped and never overridden
/// per tab, so the call is the same across every deck tab.
class MeetingSessionNotifier extends Notifier<MeetingSession?> {
  @override
  MeetingSession? build() => null;

  /// Adopt a freshly joined session as the app's active call.
  void adopt(MeetingSession session) => state = session;

  /// Leave the active call, if any, and clear it.
  Future<void> leave() async {
    final session = state;
    state = null;
    await session?.leave();
  }
}
