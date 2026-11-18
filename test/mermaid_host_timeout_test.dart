import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/mermaid_render_service.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _AvailablePlatform extends WebViewPlatform {}

void main() {
  testWidgets('een beschikbare maar ongekoppelde host houdt renders niet vast', (
    tester,
  ) async {
    // Dit bestand heeft een eigen test-isolate; de platformsetter accepteert
    // geen null om de oorspronkelijke stand terug te zetten.
    WebViewPlatform.instance = _AvailablePlatform();
    final service = MermaidRenderService.instance;
    const source = 'graph TD; Host-->Missing;';
    final first = service.render(source);
    final duplicate = service.render(source);
    final math = service.renderMath('x + 1');
    expect(identical(first, duplicate), isTrue);
    expect(service.pendingRenders, 1);
    // Dit is de deadline zelf, in virtuele tijd; geen gok op schijf- of JS-I/O.
    await tester.pump(const Duration(seconds: 20));
    expect(await first, isNull);
    expect(await math, isNull);
    expect(service.pendingRenders, 0);

    // Een mislukte start blijft niet in de deduplicatiecache staan.
    final retry = service.render(source);
    expect(identical(first, retry), isFalse);
    expect(service.pendingRenders, 1);
    await tester.pump(const Duration(seconds: 20));
    expect(await retry, isNull);
    expect(service.pendingRenders, 0);
  });
}
