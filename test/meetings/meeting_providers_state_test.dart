// Tests voor de Riverpod-wiring (#2533): de providerregistratie, de
// prefs-backed profielnotifier en de resolver die die twee samenbrengt.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_link_resolver.dart';
import 'package:ocideck/meetings/meeting_provider_profile.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_provider.dart';
import 'package:ocideck/state/meeting_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

MeetingProviderProfile _profile(String origin) => MeetingProviderProfile(
  id: '',
  providerId: 'jitsi',
  origin: Uri.parse(origin),
  allowedJoinPathPrefixes: const {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // De singleton warmen: daarna resolveert getInstance() in een microtask
    // en volstaat pumpEventQueue() om _load() af te zien ronden.
    await SharedPreferences.getInstance();
  });

  test('registreert de Jitsi-adapter als enige provider', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final providers = c.read(meetingProvidersProvider);
    expect(providers.single, isA<JitsiMeetingProvider>());
  });

  test('laadt lege profielen uit schone prefs', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // build() start _load(); even wachten tot de prefs rond zijn.
    expect(c.read(meetingProfilesProvider).loading, isTrue);
    await pumpEventQueue();
    expect(c.read(meetingProfilesProvider).loading, isFalse);
    expect(c.read(meetingProfilesProvider).profiles, isEmpty);
  });

  test(
    'upsert bewaart, dedupliceert op (providerId, origin) en genereert id',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await pumpEventQueue();
      final notifier = c.read(meetingProfilesProvider.notifier);

      await notifier.upsert(_profile('https://meet.example'));
      await notifier.upsert(_profile('https://meet.example')); // zelfde origin
      await notifier.upsert(_profile('https://other.example'));

      final profiles = c.read(meetingProfilesProvider).profiles;
      expect(profiles, hasLength(2));
      expect(profiles.first.id, isNotEmpty);

      // Overleeft een herstart: een nieuwe container leest dezelfde prefs.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(meetingProfilesProvider);
      await pumpEventQueue();
      expect(c2.read(meetingProfilesProvider).profiles, hasLength(2));
    },
  );

  test('remove verwijdert en bewaart', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await pumpEventQueue();
    final notifier = c.read(meetingProfilesProvider.notifier);
    await notifier.upsert(_profile('https://meet.example'));
    final id = c.read(meetingProfilesProvider).profiles.single.id;
    await notifier.remove(id);
    expect(c.read(meetingProfilesProvider).profiles, isEmpty);
  });

  test('de resolver herkent een link via een goedgekeurd profiel', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await pumpEventQueue();
    await c
        .read(meetingProfilesProvider.notifier)
        .upsert(_profile('https://meet.example'));

    final resolver = c.read(meetingLinkResolverProvider);
    final resolution = resolver.resolve('https://meet.example/team-overleg');
    expect(resolution.verdict, MeetingLinkVerdict.recognized);
    expect(resolution.match?.providerId, 'jitsi');
    expect(resolution.viaProfile, isNotNull);
  });
}
