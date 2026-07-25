@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/mermaid_config.dart';
import 'package:ocideck/services/mermaid_web_renderer_stub.dart' as io_stub;

/// De web-render van Mermaid-diagrammen (#851).
///
/// Op web kon de verborgen WebView-renderer niet werken: `webview_flutter_web`
/// implementeert `runJavaScriptReturningResult` niet, dus elke render gaf stil
/// `null` en het diagram bleef een leeg vlak. De fix draait de gebundelde
/// mermaid.min.js rechtstreeks in de app-pagina via JS-interop.
///
/// Dát pad is hier niet uit te voeren: `kIsWeb` is onder `flutter test` altijd
/// `false` en `dart:js_interop` compileert niet op de VM, dus het echte renderen
/// wordt visueel op web geverifieerd. Wat deze poort wél vasthoudt is de
/// structuur waar de bug in zat en waar hij weer in zou kunnen sluipen:
///
///  1. de mermaid-instellingen staan op ÉÉN plek, zodat de twee renderpaden niet
///     uiteen kunnen lopen in beveiligingsposture;
///  2. de service kiest achter `kIsWeb` het web-pad, met een conditional import;
///  3. de web-renderer laadt de bundel van de juiste, van pubspec afgeleide URL.
void main() {
  group('gedeelde mermaid-config is de veilige posture', () {
    test('securityLevel is strict en htmlLabels staat overal uit', () {
      expect(kMermaidInitConfig['securityLevel'], 'strict');
      expect(kMermaidInitConfig['htmlLabels'], isFalse);
      expect(
        (kMermaidInitConfig['flowchart'] as Map)['htmlLabels'],
        isFalse,
        reason: 'htmlLabels ook per diagramsoort uit, anders lege vakjes',
      );
      expect((kMermaidInitConfig['class'] as Map)['htmlLabels'], isFalse);
    });

    test("de 'secure'-lijst beschermt zichzelf en securityLevel", () {
      final secure = kMermaidInitConfig['secure'] as List;
      // Zonder 'secure' en 'securityLevel' in de onaantastbare lijst kan een
      // diagramrichtlijn de beperkingen alsnog opheffen.
      expect(secure, containsAll(<String>['secure', 'securityLevel']));
    });
  });

  group('de web-script-URL klopt met wat pubspec bundelt', () {
    test('kMermaidWebScriptUrl is assets/ + de assetsleutel', () {
      // Flutter serveert een asset onder `assets/` + de assetsleutel; de sleutel
      // is hier zelf `assets/web_export/mermaid.min.js` (de map staat zo in
      // pubspec), vandaar de dubbele `assets/`. Leid dat hier af zodat een
      // verplaatsing van de asset deze poort laat vallen in plaats van stil de
      // URL te breken.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains('assets/web_export/'),
        reason: 'de map moet in pubspec als asset staan',
      );
      const assetKey = 'assets/web_export/mermaid.min.js';
      expect(kMermaidWebScriptUrl, 'assets/$assetKey');
      expect(
        File(assetKey).existsSync(),
        isTrue,
        reason: 'de gebundelde mermaid moet bestaan op $assetKey',
      );
    });

    test('kSvgStyleInlineScriptUrl is assets/ + de assetsleutel en bestaat', () {
      // Zelfde afleiding voor de stijl-inliner (#862): mermaids theme zit in een
      // `<style>`-blok dat flutter_svg negeert, deze inliner zet het inline.
      const assetKey = 'assets/web_export/svg_style_inline.js';
      expect(kSvgStyleInlineScriptUrl, 'assets/$assetKey');
      expect(
        File(assetKey).existsSync(),
        isTrue,
        reason: 'de gebundelde stijl-inliner (#862) moet bestaan op $assetKey',
      );
    });
  });

  group('de service kiest het web-pad en houdt één config', () {
    final service = File(
      'lib/services/mermaid_render_service.dart',
    ).readAsStringSync();

    test('conditional import van de web-renderer', () {
      expect(
        service,
        contains("if (dart.library.js_interop) 'mermaid_web_renderer.dart'"),
        reason: 'op web een andere render-implementatie dan op IO',
      );
    });

    test('een kIsWeb-tak roept de web-renderer aan', () {
      expect(service, contains('kIsWeb'));
      expect(
        service,
        contains('web_renderer.renderMermaid'),
        reason: 'het web-pad moet de JS-interop-renderer gebruiken',
      );
    });

    test('de WebView-bootstrap zet dezelfde config als JSON', () {
      // Één bron van waarheid: de WebView krijgt de config via jsonEncode van
      // kMermaidInitConfig, niet als tweede handgeschreven kopie.
      expect(
        service,
        contains(r'mermaid.initialize(${jsonEncode(kMermaidInitConfig)})'),
      );
    });

    test('de WebView bundelt en past de gedeelde stijl-inliner toe (#862)', () {
      // Dezelfde inliner-asset als de web-kant, in de WebView-HTML gebundeld en
      // op de render toegepast — zodat flutter_svg mermaids kleuren/tekst leest.
      expect(service, contains('svg_style_inline.js'));
      expect(service, contains('__ocideckInlineSvgStyles'));
    });
  });

  test('de web-renderer laadt de bundel via de gedeelde URL en config', () {
    final web = File(
      'lib/services/mermaid_web_renderer.dart',
    ).readAsStringSync();
    expect(web, contains('kMermaidWebScriptUrl'));
    expect(
      web,
      contains('kMermaidInitConfig'),
      reason: 'de web-kant moet dezelfde instellingen gebruiken',
    );
    expect(
      web,
      contains('kSvgStyleInlineScriptUrl'),
      reason: 'de web-kant moet de stijl-inliner (#862) laden',
    );
    expect(web, contains('__ocideckInlineSvgStyles'));
  });

  test('de io-stub geeft null en wordt nooit voor het echt gebruikt', () async {
    // De niet-web tegenhanger bestaat alleen zodat de conditional import op IO
    // compileert; op desktop/mobiel rendert de WebView. Hij hoort altijd null te
    // geven — de service neemt het web-pad uitsluitend achter kIsWeb.
    expect(await io_stub.renderMermaid('graph TD; A-->B;'), isNull);
  });
}
