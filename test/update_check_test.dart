import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/export_metadata.dart' show kOciDeckVersion;
import 'package:ocideck/services/update_check_fetch.dart';
import 'package:ocideck/services/update_check_fetch_web.dart' as web_fetch;
import 'package:ocideck/services/update_check_service.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/update_check_provider.dart';
import 'package:ocideck/utils/version_compare.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('update_check_fetch', () {
    // Coverage: de facade en de webhelft staan anders in geen enkele test.
    // De webweigering is pure Dart en dus gewoon op de VM aan te roepen.
    test('web weigert de check altijd', () async {
      expect(await web_fetch.pinnedUpdateCheckFetch(latestReleaseUri), isNull);
    });

    test('de facade wijst een fetcher aan', () {
      expect(defaultUpdateCheckFetch, isNotNull);
    });
  });

  group('AppVersion', () {
    test('parset v-prefix, build-metadata en pre-release', () {
      expect(AppVersion.tryParse('v1.2.3')!.core, '1.2.3');
      expect(AppVersion.tryParse('1.2.3+42')!.toString(), '1.2.3');
      expect(AppVersion.tryParse('0.6.12-rc1')!.toString(), '0.6.12-rc1');
      expect(AppVersion.tryParse('1.2'), isNull);
      expect(AppVersion.tryParse('a.b.c'), isNull);
      expect(AppVersion.tryParse('1.2.3-'), isNull);
    });

    test(
      'ordenet kern, release boven pre-release, numeriek voor alfanumeriek',
      () {
        expect(AppVersion.isNewer('v0.7.0', '0.6.12'), isTrue);
        expect(AppVersion.isNewer('0.6.12', '0.6.12'), isFalse);
        expect(AppVersion.isNewer('0.6.11', '0.6.12'), isFalse);
        // 0.6.12-rc1 < 0.6.12 (semver: pre-release < release)
        expect(AppVersion.isNewer('0.6.12-rc1', '0.6.12'), isFalse);
        expect(AppVersion.isNewer('0.6.12', '0.6.12-rc1'), isTrue);
        // rc2 > rc1; numeriek < alfanumeriek; langere lijst > kortere
        expect(AppVersion.isNewer('0.6.12-rc2', '0.6.12-rc1'), isTrue);
        expect(AppVersion.isNewer('0.6.12-alpha', '0.6.12-1'), isTrue);
        expect(AppVersion.isNewer('0.6.12-alpha.1', '0.6.12-alpha'), isTrue);
        // ongeldige invoer is nooit "nieuwer"
        expect(AppVersion.isNewer('geen-versie', '0.6.12'), isFalse);
      },
    );
  });

  group('UpdateCheckService', () {
    UpdateCheckService service(String? body) =>
        UpdateCheckService(fetcher: (_) async => body);

    String releaseJson(String tag) => jsonEncode({'tag_name': tag});

    test('nieuwere tag → isNewer met genormaliseerde versie', () async {
      final r = await service(releaseJson('v99.0.0')).fetchLatest();
      expect(r!.isNewer, isTrue);
      expect(r.latestVersion, '99.0.0');
    });

    test('gelijke of oudere tag → isNewer false', () async {
      final same = await service(
        releaseJson('v$kOciDeckVersion'),
      ).fetchLatest();
      expect(same!.isNewer, isFalse);
      final older = await service(releaseJson('v0.0.1')).fetchLatest();
      expect(older!.isNewer, isFalse);
    });

    test('elke kapotte invoer is "geen uitspraak" (null)', () async {
      expect(await service(null).fetchLatest(), isNull);
      expect(await service('geen json').fetchLatest(), isNull);
      expect(await service('[1,2]').fetchLatest(), isNull);
      expect(await service('{}').fetchLatest(), isNull);
      expect(await service(jsonEncode({'tag_name': 7})).fetchLatest(), isNull);
      expect(await service(releaseJson('vabc')).fetchLatest(), isNull);
    });
  });

  group('updateCheckProvider', () {
    /// Fetcher die zijn calls telt en een geprogrammeerde tag teruggeeft.
    UpdateCheckService fakeService(String? tag, List<Uri> calls) =>
        UpdateCheckService(
          fetcher: (uri) async {
            calls.add(uri);
            return tag == null ? null : jsonEncode({'tag_name': tag});
          },
        );

    /// Levende subscription, zoals de aiStatus-tests: autoDispose breekt een
    /// kale `read` meteen af en de async restore/check landt dan nergens.
    Future<ProviderContainer> container(
      UpdateCheckService service, {
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final c = ProviderContainer(
        overrides: [updateCheckServiceProvider.overrideWithValue(service)],
      );
      addTearDown(c.dispose);
      final sub = c.listen(updateCheckProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return c;
    }

    test('check uit → geen ping, wel herstelde indicator', () async {
      final calls = <Uri>[];
      final c = await container(
        fakeService('v99.0.0', calls),
        prefs: {'updateCheckLatestSeen': '99.0.0'},
      );
      expect(c.read(updateCheckProvider).latestVersion, '99.0.0');
      expect(c.read(updateCheckProvider).updateAvailable, isTrue);
      expect(calls, isEmpty);
    });

    test('check aan → één ping, uitslag en tijdstip bewaard', () async {
      final calls = <Uri>[];
      final c = await container(fakeService('v99.0.0', calls));
      await c.read(settingsProvider.notifier).setUpdateChecksEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, [latestReleaseUri]);
      expect(c.read(updateCheckProvider).updateAvailable, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('updateCheckLatestSeen'), '99.0.0');
      expect(prefs.getInt('updateCheckLastCheckMs'), isNotNull);
    });

    test('check aan maar vandaag al gedaan → geen nieuwe ping', () async {
      final calls = <Uri>[];
      final c = await container(
        fakeService('v99.0.0', calls),
        prefs: {
          'updateCheckLastCheckMs': DateTime.now().millisecondsSinceEpoch,
        },
      );
      await c.read(settingsProvider.notifier).setUpdateChecksEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, isEmpty);
    });

    test('handmatige check mag ook als de automatische uit staat', () async {
      final calls = <Uri>[];
      final c = await container(fakeService('v99.0.0', calls));
      await c.read(updateCheckProvider.notifier).checkNow();
      expect(calls, [latestReleaseUri]);
      expect(c.read(updateCheckProvider).updateAvailable, isTrue);
    });

    test('gefaalde handmatige check toont checkFailed', () async {
      final calls = <Uri>[];
      final c = await container(fakeService(null, calls));
      await c.read(updateCheckProvider.notifier).checkNow();
      expect(c.read(updateCheckProvider).checkFailed, isTrue);
      expect(c.read(updateCheckProvider).updateAvailable, isFalse);
    });

    test('gefaalde automatische check blijft stil', () async {
      final calls = <Uri>[];
      final c = await container(
        fakeService(null, calls),
        prefs: {'updateCheckLatestSeen': '99.0.0'},
      );
      await c.read(settingsProvider.notifier).setUpdateChecksEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, [latestReleaseUri]);
      // Stil = geen checkFailed, en de herstelde indicator blijft staan.
      expect(c.read(updateCheckProvider).checkFailed, isFalse);
      expect(c.read(updateCheckProvider).updateAvailable, isTrue);
    });
  });
}
