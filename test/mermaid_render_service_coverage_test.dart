import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/mermaid_render_service.dart';
import 'package:ocideck/widgets/mermaid_render_host.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Covers the parts of MermaidRenderService that DON'T need a live WebView / JS
/// engine: the test-mode guards, the host-request notifier, the empty-source
/// fast path, and the offstage host layer's test-mode short-circuit.
///
/// The bootstrap → runJavaScript → sanitize pipeline (the bulk of the file) is
/// intentionally not covered here: it strictly requires a WebViewController and
/// a JavaScript runtime, which a plain unit test cannot provide. Driving a
/// non-empty render() without a controller would enqueue a job that never
/// completes, so those paths are left to widget/integration harnesses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // De dienst is een singleton en `hostNeeded` overleeft dus de test die hem
  // zette. De suite draait met `--test-randomize-ordering-seed random`, dus de
  // volgorde binnen dit bestand ligt niet vast: liep de requestHost-test eerst,
  // dan zag de test hieronder een gevraagde host en viel om (seeds 7 en 42).
  // Elke test begint daarom op dezelfde stand.
  setUp(() => MermaidRenderService.instance.hostNeeded.value = false);

  test('isFlutterTest reports true under the flutter test runner', () {
    expect(isFlutterTest, isTrue);
  });

  test('render() of blank source resolves to null without a WebView', () async {
    final service = MermaidRenderService.instance;
    // Empty and whitespace-only sources short-circuit before any host/JS use.
    expect(await service.render(''), isNull);
    expect(await service.render('   \n\t'), isNull);
  });

  test('zonder WebView-platform levert een render meteen niets op', () async {
    // Windows en Linux hebben geen `webview_flutter`-implementatie (pubspec.lock
    // kent android, wkwebview en web). Daar blijft `WebViewPlatform.instance`
    // null — net als hier in een unit-test.
    //
    // Vóór de vraag `isAvailable` liep dit anders af: de dienst vroeg om de
    // host, die bouwde een `WebViewController` op een platform zonder
    // implementatie, en dát gooide. Een documentexport met één mermaid-diagram
    // sloopte daarmee op Windows, terwijl hij het daarvóór gewoon deed. In deze
    // test zou hij zonder de vraag eeuwig blijven wachten — de job komt de
    // wachtrij nooit uit zonder controller.
    final service = MermaidRenderService.instance;
    // De service is een singleton; een eerdere test in de suite kan de vlag
    // al gezet hebben (bijv. mermaid_render_pipeline_test).
    service.hostNeeded.value = false;
    expect(WebViewPlatform.instance, isNull, reason: 'anders meet dit niets');
    expect(service.isAvailable, isFalse);
    expect(
      await service
          .render('graph TD; A-->B;')
          .timeout(const Duration(seconds: 5), onTimeout: () => 'BLEEF HANGEN'),
      isNull,
    );
    expect(
      await service
          .renderMath('E = mc^2')
          .timeout(const Duration(seconds: 5), onTimeout: () => 'BLEEF HANGEN'),
      isNull,
    );
    // En de host is niet gevraagd: er valt niets te monteren.
    expect(service.hostNeeded.value, isFalse);
  });

  testWidgets('requestHost zet de vlag ná het frame, niet erin', (
    tester,
  ) async {
    final service = MermaidRenderService.instance;
    // De aanroep komt in het echt uit initState van MermaidDiagram, dus midden
    // in de buildfase. Meteen omzetten markeerde de ValueListenableBuilder die
    // de verborgen WebView draagt als vuil terwijl die al gebouwd was —
    // "setState() called during build" — en dan werd de host nooit gemonteerd
    // en bleef elk diagram eeuwig laden.
    service.requestHost();
    expect(
      service.hostNeeded.value,
      isFalse,
      reason: 'binnen het frame verandert er niets',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    expect(service.hostNeeded.value, isTrue);

    // Nog een keer vragen kost niets en meldt niets.
    service.requestHost();
    await tester.pump();
    expect(service.hostNeeded.value, isTrue);
  });

  testWidgets('MermaidRenderHostLayer collapses to nothing in test mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MermaidRenderHostLayer())),
    );
    // isFlutterTest is true, so the layer never mounts the offstage host.
    expect(find.byType(MermaidRenderHost), findsNothing);
    expect(find.byType(MermaidRenderHostLayer), findsOneWidget);
  });
}
