import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/net_guard.dart';
import 'package:ocideck/utils/url_launcher_util.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records what `openExternalUrl` asks the platform to launch, so we can assert
/// the scheme allowlist and normalisation without touching a real browser.
class _FakeLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];
  bool canLaunchResult = true;
  bool throwOnCanLaunch = false;

  // The return type (LinkDelegate?) is not exported; let Dart infer it from the
  // overridden abstract getter rather than naming the type.
  @override
  get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    if (throwOnCanLaunch) throw Exception('canLaunch exploded');
    return canLaunchResult;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late _FakeLauncher fake;

  setUp(() {
    fake = _FakeLauncher();
    UrlLauncherPlatform.instance = fake;
  });

  /// De hostpoort zonder DNS: alleen de lexicale helft van NetGuard. Genoeg om
  /// een letterlijk intern adres te weren, en het houdt de test hermetisch —
  /// de echte poort doet een opzoeking en zou de suite van het netwerk laten
  /// afhangen. De resolverende helft wordt bij NetGuard zelf getoetst.
  Future<bool> lexicalGate(String url) async => NetGuard.isAllowedMediaUrl(url);

  Future<void> open(String url) => openExternalUrl(url, hostGate: lexicalGate);

  test('launches an allowed https URL as-is', () async {
    await open('https://example.com/pad');
    expect(fake.launched, ['https://example.com/pad']);
  });

  test('prepends https:// to a bare domain', () async {
    await open('example.com');
    expect(fake.launched, ['https://example.com']);
  });

  test('turns an email-like string into a mailto: link', () async {
    await open('jan@example.com');
    expect(fake.launched, ['mailto:jan@example.com']);
  });

  test('allows http and mailto schemes', () async {
    await open('http://intern.test');
    await open('mailto:info@example.com');
    expect(fake.launched, ['http://intern.test', 'mailto:info@example.com']);
  });

  // De kern van de hostpoort. Een link in een deck is invoer: hij mocht de
  // browser van de lezer naar het metadata-eindpunt van een cloudinstantie of
  // naar zijn eigen router sturen, mét cookies. Dit was de enige
  // deck-gestuurde host die NetGuard oversloeg.
  group('hostpoort voor deck-links', () {
    const intern = [
      'http://169.254.169.254/latest/meta-data/',
      'http://127.0.0.1:8080/admin',
      'http://localhost/',
      'https://10.0.0.1/',
      'http://192.168.1.1/',
      'http://172.16.5.4/',
      'http://[::1]/',
      // Een IPv4 verstopt in een IPv6-literal telt net zo goed.
      'http://[::ffff:169.254.169.254]/',
    ];

    for (final url in intern) {
      test('weigert $url', () async {
        await open(url);
        expect(fake.launched, isEmpty);
      });
    }

    test('een gewone publieke host mag nog steeds', () async {
      await open('https://librekat.org/handleiding');
      expect(fake.launched, ['https://librekat.org/handleiding']);
    });

    test('mailto gaat niet door de hostpoort', () async {
      // Daar zit geen host in, en er wordt geen adres uit het deck gebeld.
      var gateCalls = 0;
      await openExternalUrl(
        'mailto:info@example.com',
        hostGate: (url) async {
          gateCalls++;
          return false;
        },
      );
      expect(gateCalls, 0);
      expect(fake.launched, ['mailto:info@example.com']);
    });

    test('een geweigerde host wordt niet eens aan het platform gevraagd', () {
      // Niet alleen "niet geopend": de URL mag de OS-laag niet bereiken.
      return open('http://169.254.169.254/').then((_) {
        expect(fake.launched, isEmpty);
      });
    });
  });

  test('refuses dangerous or unexpected schemes', () async {
    for (final url in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'ftp://host/file',
      'data:text/html,<script>x</script>',
    ]) {
      await open(url);
    }
    expect(fake.launched, isEmpty);
  });

  test('ignores empty or whitespace-only input', () async {
    await open('');
    await open('   ');
    expect(fake.launched, isEmpty);
  });

  test('does nothing when the platform cannot launch the URL', () async {
    fake.canLaunchResult = false;
    await open('https://example.com');
    expect(fake.launched, isEmpty);
  });

  test('swallows a launcher exception without rethrowing', () async {
    fake.throwOnCanLaunch = true;
    // Must complete normally — a broken link never crashes the presentation.
    await open('https://example.com');
    expect(fake.launched, isEmpty);
  });
}
