import 'package:flutter_test/flutter_test.dart';
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

  test('launches an allowed https URL as-is', () async {
    await openExternalUrl('https://example.com/pad');
    expect(fake.launched, ['https://example.com/pad']);
  });

  test('prepends https:// to a bare domain', () async {
    await openExternalUrl('example.com');
    expect(fake.launched, ['https://example.com']);
  });

  test('turns an email-like string into a mailto: link', () async {
    await openExternalUrl('jan@example.com');
    expect(fake.launched, ['mailto:jan@example.com']);
  });

  test('allows http and mailto schemes', () async {
    await openExternalUrl('http://intern.test');
    await openExternalUrl('mailto:info@example.com');
    expect(fake.launched, ['http://intern.test', 'mailto:info@example.com']);
  });

  test('refuses dangerous or unexpected schemes', () async {
    for (final url in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'ftp://host/file',
      'data:text/html,<script>x</script>',
    ]) {
      await openExternalUrl(url);
    }
    expect(fake.launched, isEmpty);
  });

  test('ignores empty or whitespace-only input', () async {
    await openExternalUrl('');
    await openExternalUrl('   ');
    expect(fake.launched, isEmpty);
  });

  test('does nothing when the platform cannot launch the URL', () async {
    fake.canLaunchResult = false;
    await openExternalUrl('https://example.com');
    expect(fake.launched, isEmpty);
  });

  test('swallows a launcher exception without rethrowing', () async {
    fake.throwOnCanLaunch = true;
    // Must complete normally — a broken link never crashes the presentation.
    await openExternalUrl('https://example.com');
    expect(fake.launched, isEmpty);
  });
}
