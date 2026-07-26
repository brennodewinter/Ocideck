import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/mermaid_config.dart';
import 'package:ocideck/services/mermaid_render_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
// `PlatformWebViewController` wordt niet door webview_flutter doorgegeven,
// terwijl het de enige manier is om de platformlaag te vervangen. Zie
// media_previews_video_coverage_test, dat om dezelfde reden hetzelfde doet.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Een WebView die geen WebView is: hij onthoudt de geladen HTML en geeft op
/// elke JS-aanroep terug wat de test klaarzet.
class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  String? html;
  final scripts = <String>[];

  /// Statisch en gedeeld: de dienst is een singleton die precies één keer
  /// bootstrapt en dáár het channel registreert, terwijl elke test een nieuwe
  /// nep-controller aanhaakt. De callback is een stabiele methode op de
  /// singleton, dus dezelfde gedeelde referentie werkt voor elke controller.
  static void Function(JavaScriptMessage)? _sharedChannel;

  /// Wat de render teruggeeft (een SVG-string), of een `Exception` om een fout
  /// aan de JS-kant te simuleren.
  Object? Function(String script)? answer;

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    this.html = html;
    // Boots de echte pagina na (#882): zodra ze geladen is meldt ze via het
    // channel 'setup-ok', waarna de dienst de wachtrij vrijgeeft. Zonder dit zou
    // de bootstrap op de 10s-time-out moeten wachten.
    _sharedChannel?.call(
      JavaScriptMessage(message: jsonEncode({'diag': 'setup-ok'})),
    );
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    _sharedChannel = javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
    if (!javaScript.startsWith('window.__renderMermaid(')) return;
    // De echte pagina rendert async en stuurt het resultaat via MermaidChannel
    // terug (#882). Hier bootsen we dat na: haal de seq uit de aanroep en lever
    // het door de test klaargezette antwoord op datzelfde kanaal.
    final seq = int.parse(
      RegExp(r',\s*(\d+)\s*\)\s*$').firstMatch(javaScript)!.group(1)!,
    );
    final result = answer?.call(javaScript);
    final payload = result is Exception
        ? {'seq': seq, 'error': result.toString()}
        : {'seq': seq, 'svg': (result as String?) ?? ''};
    _sharedChannel?.call(JavaScriptMessage(message: jsonEncode(payload)));
  }
}

class _FakePlatform extends WebViewPlatform {
  _FakePlatform(this.controller);

  final _FakeController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller;
}

/// De renderketen van [MermaidRenderService]: bootstrappen, de wachtrij, en wat
/// er met het antwoord van de JS-kant gebeurt.
///
/// Dit stuk stond onbeproefd omdat het strikt een WebViewController nodig heeft.
/// Die is hier een dubbel, en daarmee is te tonen wat er werkelijk toe doet: de
/// pagina waarin de opmaak wordt gebouwd is dichtgetimmerd, het antwoord gaat
/// door de zeef vóór het de cache in mag, een fout aan de JS-kant wedgt de
/// wachtrij niet, en het resultaat komt via het MermaidChannel terug in plaats
/// van als Promise via `runJavaScriptReturningResult` (#882), zodat het op
/// macOS-WKWebView niet meer stukloopt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeController controller;

  /// De pagina die bij het bootstrappen is geladen.
  ///
  /// De dienst is een singleton en bootstrapt precies één keer per proces, dus
  /// alleen de eerste test die draait ziet zijn eigen controller geladen
  /// worden. De volgorde is willekeurig; dus wordt de pagina hier vastgehouden
  /// zodra ze er is, en niet uit de controller van dít geval gelezen.
  String? geladenPagina;

  /// Elke test een eigen bron: de dienst is een singleton met een cache, en
  /// een gedeelde bron zou de tweede test op het antwoord van de eerste laten
  /// leunen.
  var teller = 0;
  String verseBron() => 'graph TD; A${teller++}-->B;';

  String svgVoor(String id) =>
      '<svg xmlns="http://www.w3.org/2000/svg"><rect id="$id"/></svg>';

  setUp(() async {
    controller = _FakeController(
      const PlatformWebViewControllerCreationParams(),
    );
    WebViewPlatform.instance = _FakePlatform(controller);
    MermaidRenderService.instance.attachController(WebViewController());
    // Het bootstrappen leest de mermaid-bundel van de asset-bundel; laat dat
    // afronden voordat er iets te renderen valt.
    //
    // Écht wachten, niet alleen microtaken. `AssetBundle.loadString` decodeert
    // alles boven 10 kB in een eigen isolate, en de mermaid-bundel is ruim
    // groter. Een isolate-heenweg komt niet terug op een `Duration.zero` —
    // die pompt alleen de microtaakrij van dit isolate leeg. Met tweehonderd
    // van die rondes bleef `controller.html` dus altijd null en faalde deze
    // toets op "er is geen pagina geladen", nog vóór er iets over de CSP werd
    // beweerd. Vijf milliseconden per ronde geeft de isolate de kans om te
    // antwoorden; hij breekt af zodra de pagina er is, dus het kost niets.
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (geladenPagina != null || controller.html != null) break;
    }
    geladenPagina ??= controller.html;
  });

  test('de pagina waarin gerenderd wordt is dichtgetimmerd', () async {
    final html = geladenPagina;
    expect(html, isNotNull, reason: 'er is geen pagina geladen');
    // Geen netwerk, geen externe scripts: de enige bron is de meegeleverde
    // bundel. Zonder deze regels zou een diagram een uitgang kunnen worden.
    expect(html, contains("default-src 'none'"));
    expect(html, contains('img-src data:'));
    // En mermaid zelf op zijn strengste stand: de pagina wordt geïnitialiseerd
    // met de gedeelde config (mermaid_config.dart), als JSON in de pagina gezet,
    // zodat het web-pad en de WebView niet uiteen kunnen lopen. Dát die config
    // strikt is (securityLevel strict, htmlLabels uit) bewaakt
    // mermaid_web_render_test.
    expect(html, contains(jsonEncode(kMermaidInitConfig)));
    // De pagina meldt zichzelf klaar met 'setup-ok' zodra mermaid geladen en
    // __renderMermaid gedefinieerd is (#882). De dienst wacht op dát signaal
    // vóór het de wachtrij vrijgeeft — niet op het resolven van loadHtmlString,
    // want dat resolvet vóór het pagina-script draait en een render in dat gaatje
    // raakte FWFEvaluateJavaScriptError.
    expect(html, contains("'setup-ok'"));
  });

  test(
    'een geldig diagram komt geschoond terug en blijft in de cache',
    () async {
      final bron = verseBron();
      controller.answer = (_) => svgVoor('een');

      final eerste = await MermaidRenderService.instance.render(bron);
      expect(eerste, contains('<svg'));
      expect(eerste, contains('id="een"'));

      // Tweede keer dezelfde bron: uit de cache, dus geen tweede JS-aanroep.
      final aantal = controller.scripts.length;
      controller.answer = (_) => svgVoor('twee');
      final tweede = await MermaidRenderService.instance.render(bron);
      expect(
        tweede,
        eerste,
        reason: 'de cache hoort het antwoord vast te houden',
      );
      expect(controller.scripts.length, aantal);
    },
  );

  test('de bron gaat als JSON de JS-aanroep in', () async {
    // Een aanhalingsteken of een backslash in de brontekst zou de aanroep
    // anders openbreken — dat is een injectie in de eigen pagina.
    controller.answer = (_) => svgVoor('drie');
    final bron = 'graph TD; A["hij zei \\"hoi\\""]-->B; ${verseBron()}';
    await MermaidRenderService.instance.render(bron);

    final script = controller.scripts.last;
    expect(script, startsWith('window.__renderMermaid('));
    expect(
      script,
      isNot(contains('hij zei "hoi"')),
      reason: 'ongeciteerd zou de aanroep openbreken',
    );
  });

  test('het antwoord komt via het channel terug, niet als Promise', () async {
    // De kern van #882: de render is async, dus we halen het resultaat NIET met
    // runJavaScriptReturningResult op (dat marshalt een Promise niet op
    // macOS-WKWebView) maar vuren met runJavaScript en wachten op het channel.
    controller.answer = (_) => svgVoor('kanaal');
    final svg = await MermaidRenderService.instance.render(verseBron());
    expect(svg, contains('id="kanaal"'));
    expect(
      controller.scripts.last,
      startsWith('window.__renderMermaid('),
      reason: 'afgevuurd, niet als resultaat-teruggevende eval',
    );
  });

  test('opmaak die geen SVG is haalt de cache niet', () async {
    controller.answer = (_) => '<html>fout</html>';
    expect(await MermaidRenderService.instance.render(verseBron()), isNull);
  });

  test('een script dat een gebeurtenis meesmokkelt wordt geschoond', () async {
    controller.answer = (_) =>
        '<svg xmlns="http://www.w3.org/2000/svg" onload="steel()">'
        '<script>alert(1)</script><rect id="vier"/></svg>';

    final svg = await MermaidRenderService.instance.render(verseBron());
    expect(svg, isNotNull);
    expect(svg, isNot(contains('<script')));
    expect(svg, isNot(contains('onload')));
    expect(svg, contains('id="vier"'));
  });

  test(
    'een fout aan de JS-kant levert null op en blokkeert de rij niet',
    () async {
      controller.answer = (_) => Exception('boem');
      expect(await MermaidRenderService.instance.render(verseBron()), isNull);

      // De volgende render moet gewoon doorkomen: bleef de rij hangen, dan
      // stond elk diagram daarna eeuwig op het wachtwieltje.
      controller.answer = (_) => svgVoor('vijf');
      final daarna = await MermaidRenderService.instance.render(verseBron());
      expect(daarna, contains('id="vijf"'));
    },
  );

  test('twee renders tegelijk komen allebei terug', () async {
    // De rij wordt één voor één afgehandeld; wie de tweede laat vallen, laat
    // een dia met twee diagrammen half leeg.
    final a = verseBron();
    final b = verseBron();
    controller.answer = (script) => svgVoor(script.contains(a) ? 'a' : 'b');

    final uitkomsten = await Future.wait([
      MermaidRenderService.instance.render(a),
      MermaidRenderService.instance.render(b),
    ]);

    expect(uitkomsten[0], contains('id="a"'));
    expect(uitkomsten[1], contains('id="b"'));
  });

  test('een lege bron kost geen JS-aanroep', () async {
    final aantal = controller.scripts.length;
    expect(await MermaidRenderService.instance.render('   '), isNull);
    expect(controller.scripts.length, aantal);
  });
}
