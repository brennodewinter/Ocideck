import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/services/website_style/website_style_source.dart';
import 'package:ocideck/widgets/dialogs/website_style_renderer.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/pump_until.dart';

class _Controller extends PlatformWebViewController {
  _Controller()
    : super.implementation(const PlatformWebViewControllerCreationParams());

  String? html;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    this.html = html;
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate()
    : super.implementation(const PlatformNavigationDelegateCreationParams());

  NavigationRequestCallback? navigate;
  HttpAuthRequestCallback? authenticate;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    navigate = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}

  @override
  Future<void> setOnHttpAuthRequest(HttpAuthRequestCallback callback) async {
    authenticate = callback;
  }
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _Platform extends WebViewPlatform {
  final controller = _Controller();
  final delegate = _Delegate();

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller;

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate;

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

void main() {
  testWidgets(
    'only the initial local snapshot can navigate; auth is cancelled',
    (tester) async {
      final platform = _Platform();
      final previous = WebViewPlatform.instance;
      WebViewPlatform.instance = platform;
    if (previous != null) {
      addTearDown(() => WebViewPlatform.instance = previous);
    }
      final snapshot = WebsiteStyleSnapshot(
        url: Uri.parse('https://example.org'),
        html: '<html><body>Offline preview</body></html>',
        incompleteStylesheets: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WebsiteStyleRenderer(
            snapshot: snapshot,
            onResult: (_) {},
            onError: () => fail('renderer could not load the local snapshot'),
          ),
        ),
      );
      await pumpUntil(tester, () => platform.controller.html != null);
      expect(platform.controller.html, snapshot.html);
      final navigate = platform.delegate.navigate!;
      Future<NavigationDecision> request(
        String url, {
        bool main = true,
      }) async => navigate(NavigationRequest(url: url, isMainFrame: main));
      expect(await request('https://example.org'), NavigationDecision.prevent);
      expect(
        await request('about:blank', main: false),
        NavigationDecision.prevent,
      );
      expect(await request('about:blank'), NavigationDecision.navigate);
      for (final url in [
        'https://example.org',
        'https://example.org.evil.invalid',
        'file:///private.txt',
        'data:text/html,<script>fetch("https://example.org")</script>',
        'about:blank',
      ]) {
        expect(await request(url), NavigationDecision.prevent, reason: url);
      }
      var cancelled = false;
      platform.delegate.authenticate!(
        HttpAuthRequest(
          onProceed: (_) => fail('HTTP authentication must not proceed'),
          onCancel: () => cancelled = true,
          host: 'example.org',
        ),
      );
      expect(cancelled, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
