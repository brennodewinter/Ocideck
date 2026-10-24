// Riverpod-wiring voor de vergaderlaag (#2533): welke [MeetingProvider]s de
// app kent, welke [MeetingProviderProfile]s de gebruiker heeft goedgekeurd,
// en de [MeetingLinkResolver] die die twee samenbrengt.
//
// Bewust apart van `meeting_session_provider.dart`: dat bestand kent de
// module-toggle en de live sessie; dit bestand kent HERKENNING — zuiver en
// zonder netwerk tot de gebruiker expliciet om een preflight vraagt.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../meetings/meeting_link_resolver.dart';
import '../meetings/meeting_provider.dart';
import '../meetings/meeting_provider_profile.dart';
import '../meetings/providers/jitsi/jitsi_meeting_provider.dart';
import '../utils/log.dart';

/// De geregistreerde adapters. Jitsi is de enige die nu bestaat; MatrixRTC
/// komt hier later naast (NATIVE_CALLS.md §1: één shell per adapter-familie).
final meetingProvidersProvider = Provider<List<MeetingProvider>>(
  (ref) => [JitsiMeetingProvider()],
);

class MeetingProfilesState {
  const MeetingProfilesState({this.profiles = const [], this.loading = true});
  final List<MeetingProviderProfile> profiles;
  final bool loading;
}

/// De door de gebruiker goedgekeurde self-hosted deployments —
/// prefs-backed via [MeetingProfilesStore].
final meetingProfilesProvider =
    NotifierProvider<MeetingProfilesNotifier, MeetingProfilesState>(
      MeetingProfilesNotifier.new,
    );

class MeetingProfilesNotifier extends Notifier<MeetingProfilesState> {
  MeetingProfilesStore _store = MeetingProfilesStore();
  late final Future<void> _ready;

  /// Vervangt de store — tests injecteren een met mock-prefs.
  set store(MeetingProfilesStore store) => _store = store;

  @override
  MeetingProfilesState build() {
    _ready = _load();
    return const MeetingProfilesState();
  }

  Future<void> _load() async {
    try {
      state = MeetingProfilesState(
        profiles: await _store.load(),
        loading: false,
      );
    } catch (e, s) {
      logError('MeetingProfilesNotifier: profielen laden', e, s);
      state = const MeetingProfilesState(loading: false);
    }
  }

  /// Voegt een profiel toe of vervangt het bestaande voor dezelfde
  /// (providerId, origin): één deployment = één trust-beslissing, geen
  /// stille dubbele. [profile.id] wordt hier gegenereerd als hij leeg is.
  Future<void> upsert(MeetingProviderProfile profile) async {
    // Een mutatie mag nooit onder een nog-lopende eerste load door schieten:
    // anders overschrijft de geladen set de zojuist bewaarde beslissing.
    await _ready;
    final id = profile.id.isNotEmpty
        ? profile.id
        : 'p${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final fixed = MeetingProviderProfile(
      id: id,
      providerId: profile.providerId,
      origin: profile.origin,
      allowedJoinPathPrefixes: profile.allowedJoinPathPrefixes,
      trustedInternal: profile.trustedInternal,
      pinnedCertSha256: profile.pinnedCertSha256,
    );
    final rest = [
      for (final p in state.profiles)
        if (!(p.providerId == fixed.providerId && p.origin == fixed.origin)) p,
    ];
    state = MeetingProfilesState(profiles: [...rest, fixed], loading: false);
    try {
      await _store.save(state.profiles);
    } catch (e, s) {
      logError('MeetingProfilesNotifier: profiel opslaan', e, s);
    }
  }

  Future<void> remove(String id) async {
    await _ready;
    state = MeetingProfilesState(
      loading: false,
      profiles: [
        for (final p in state.profiles)
          if (p.id != id) p,
      ],
    );
    try {
      await _store.save(state.profiles);
    } catch (e, s) {
      logError('MeetingProfilesNotifier: profiel verwijderen', e, s);
    }
  }
}

/// De resolver met de huidige providers + goedgekeurde profielen.
/// Herbouwt vanzelf wanneer een profiel wijzigt.
final meetingLinkResolverProvider = Provider<MeetingLinkResolver>((ref) {
  return MeetingLinkResolver(
    providers: ref.watch(meetingProvidersProvider),
    profiles: ref.watch(meetingProfilesProvider.select((s) => s.profiles)),
  );
});
