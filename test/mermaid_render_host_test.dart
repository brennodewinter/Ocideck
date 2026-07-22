import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/mermaid_render_host.dart';
// `PlatformWebViewController` wordt niet door webview_flutter doorgegeven,
// terwijl het de enige manier is om de platformlaag te vervangen. Zie
// mermaid_render_pipeline_test, dat om dezelfde reden hetzelfde doet.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Een WebView die geen WebView is: hij onthoudt wat er aan hem is opgelegd,
/// en biedt de navigatiedelegate terug zodat de test hem kan bevragen.
class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  JavaScriptMode? mode;
  Color? background;
  PlatformNavigationDelegate? delegate;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    this.mode = mode;
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    background = color;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onRequest;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onRequest,
  ) async {
    this.onRequest = onRequest;
  }

  @override
  Future<void> setOnHttpAuthRequest(HttpAuthRequestCallback onRequest) async {}
}

/// De widget die de platformlaag normaal levert. Zonder deze stub gooit
/// `WebViewWidget` een UnimplementedError zodra hij gebouwd wordt.
class _FakeWidget extends PlatformWebViewWidget {
  _FakeWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox(key: Key('nep-webview'));
}

class _FakePlatform extends WebViewPlatform {
  _FakePlatform(this.controller, this.delegate);

  final _FakeController controller;
  final _FakeNavigationDelegate delegate;

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
  ) => _FakeWidget(params);
}

/// De widgetkant van de diagramweergave: de verborgen WebView waarin mermaid
/// tekent.
///
/// Wat hier werkelijk toe doet is de insluiting. Die WebView is een volwaardige
/// browser in het proces; hij hoort precies één pagina te laden — de pagina die
/// de dienst zelf opbouwt — en daarna nergens meer heen te kunnen. Zonder die
/// grens zou een diagram uit een deck een uitgang worden.
void main() {
  late _FakeController controller;
  late _FakeNavigationDelegate delegate;

  setUp(() {
    controller = _FakeController(
      const PlatformWebViewControllerCreationParams(),
    );
    delegate = _FakeNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    WebViewPlatform.instance = _FakePlatform(controller, delegate);
  });

  testWidgets('de eerste lading mag, elke volgende wordt geweigerd', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MermaidRenderHost()));
    // De platformweergave wordt bewust pas ná het eerste frame gemaakt, zodat
    // hij niet met de vensteropbouw concurreert; dus eerst nog een frame.
    await tester.pump();

    final onRequest = delegate.onRequest;
    expect(onRequest, isNotNull, reason: 'er is geen navigatiedelegate gezet');

    const eerste = NavigationRequest(url: 'about:blank', isMainFrame: true);
    expect(
      await onRequest!(eerste),
      NavigationDecision.navigate,
      reason: 'de pagina die de dienst zelf laadt moet erdoor',
    );

    // Alles daarna is per definitie iets anders dan onze eigen pagina.
    for (final url in [
      'https://example.org/',
      'http://169.254.169.254/latest/meta-data/',
      'file:///etc/passwd',
    ]) {
      expect(
        await onRequest(NavigationRequest(url: url, isMainFrame: true)),
        NavigationDecision.prevent,
        reason: '$url had geweigerd moeten worden',
      );
    }
  });

  testWidgets('de host draait JS aan, staat op wit, en blijft onzichtbaar', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MermaidRenderHost()));
    await tester.pump();

    // Mermaid ís JavaScript; zonder dit rendert er niets.
    expect(controller.mode, JavaScriptMode.unrestricted);
    // Wit, niet doorzichtig: de SVG wordt van deze pagina geplukt.
    expect(controller.background, Colors.white);

    // Hij hangt in de boom maar mag niet te zien of te raken zijn. Zoeken
    // binnen de host: MaterialApp brengt zijn eigen Offstage/IgnorePointer mee.
    Finder inHost(Type t) => find.descendant(
      of: find.byType(MermaidRenderHost),
      matching: find.byType(t),
    );
    expect(tester.widget<Offstage>(inHost(Offstage)).offstage, isTrue);
    expect(inHost(IgnorePointer), findsOneWidget);
  });

  testWidgets('vóór het eerste frame staat er niets in de boom', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MermaidRenderHost()));
    // Nog geen tweede frame: de controller bestaat nog niet, dus ook de
    // omhulling eromheen niet.
    Finder inHost(Type t) => find.descendant(
      of: find.byType(MermaidRenderHost),
      matching: find.byType(t),
    );
    expect(inHost(Offstage), findsNothing);
  });

  testWidgets('de laag houdt zich koest in een test', (tester) async {
    // `isFlutterTest` zorgt dat er in een testproces nooit een echte
    // platformweergave wordt opgetuigd — die kan een headless run laten hangen.
    await tester.pumpWidget(const MaterialApp(home: MermaidRenderHostLayer()));
    await tester.pump();

    expect(find.byType(MermaidRenderHost), findsNothing);
  });
}
