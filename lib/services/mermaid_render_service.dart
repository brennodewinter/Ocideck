import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
// `requestHost` plant een post-frame callback. Bewust `scheduler` en niet
// `widgets`: een dienst hoort headless te draaien, en `SchedulerBinding` doet
// hier precies hetzelfde zonder de widgetboom binnen te halen. De klassen die
// deze import ooit meebrachten wonen sinds main's afsplitsing in
// widgets/mermaid_render_host.dart.
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/log.dart';
import '../utils/lru_cache.dart';
import '../utils/sanitize_svg.dart';
import 'mermaid_config.dart';
// Op web kan de WebView-renderer niet werken (webview_flutter_web mist
// runJavaScriptReturningResult, #851); daar draait mermaid rechtstreeks in de
// app-pagina via JS-interop. De stub op IO wordt nooit aangeroepen.
import 'mermaid_web_renderer_stub.dart'
    if (dart.library.js_interop) 'mermaid_web_renderer.dart'
    as web_renderer;

/// Renders Mermaid diagram source to inline SVG for preview, presenter, and
/// raster export (WYSIWYG). Results are cached by trimmed source text.
///
/// De verborgen WebView zelf is een widget en woont daarom in
/// `lib/widgets/mermaid_render_host.dart`; die mount pas na het eerste
/// diagramverzoek — nooit in de MaterialApp-builder, want dat sloopt de
/// frameplanning op macOS in combinatie met meerdere vensters. Deze dienst
/// kent alleen de controller die de host aanreikt.
class MermaidRenderService {
  MermaidRenderService._();

  static final MermaidRenderService instance = MermaidRenderService._();

  final ValueNotifier<bool> hostNeeded = ValueNotifier(false);

  WebViewController? _controller;
  bool _bootstrapped = false;
  Completer<void>? _bootstrapCompleter;
  final List<_PendingRender> _queue = [];
  bool _busy = false;

  /// Correlatie voor de WebView-render (#882). `mermaid.render` is async en op
  /// macOS-WKWebView kan `runJavaScriptReturningResult` het teruggegeven Promise
  /// niet terugvertalen (FWFEvaluateJavaScriptError) — dan bleef elk diagram op
  /// desktop leeg. Daarom vuren we de render af en wachten we op het resultaat
  /// via een JS-channel; [_renderSeq] koppelt het antwoord aan het verzoek en
  /// negeert late/verdwaalde berichten (er is er hooguit één tegelijk, want
  /// [_run] serialiseert).
  int _renderSeq = 0;
  Completer<String?>? _renderCompleter;

  /// Ask the UI layer to mount the offstage WebView host.
  ///
  /// Ná het frame, niet erin. De aanroep komt uit `initState` van
  /// [MermaidDiagram], dus midden in de buildfase — en de
  /// `ValueListenableBuilder` die de verborgen WebView draagt
  /// ([MermaidRenderHostLayer]) staat hóger in de boom en is op dat moment al
  /// gebouwd. Hem dan als vuil markeren gooit "setState() or markNeedsBuild()
  /// called during build": de host werd nooit gemonteerd, [attachController]
  /// draaide nooit, [_controller] bleef null, en elk diagram bleef eeuwig op
  /// zijn laadtolletje staan — in de preview, in de presentatiemodus, én in de
  /// PDF/PPTX-export, die dezelfde renderer gebruikt.
  ///
  /// De uitzondering aan het begin houdt de tweede aanroep gratis; de vlag
  /// wordt maar één keer per sessie omgezet.
  void requestHost() {
    if (hostNeeded.value) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!hostNeeded.value) hostNeeded.value = true;
    });
  }

  /// Attach the hidden [WebViewController] created by [MermaidRenderHost].
  void attachController(WebViewController controller) {
    _controller = controller;
    _bootstrapCompleter ??= Completer<void>();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped || _controller == null) return;
    final mermaidJs = await rootBundle.loadString(
      'assets/web_export/mermaid.min.js',
    );
    // Dezelfde gebundelde SVG-stijl-inliner als de web-kant (#862): mermaid stopt
    // zijn theme in een `<style>`-blok dat flutter_svg negeert; deze zet het als
    // inline attributen vóór teruggave. Eén bron, twee renderpaden.
    final inlinerJs = await rootBundle.loadString(
      'assets/web_export/svg_style_inline.js',
    );
    // Geen `eval()` meer — zie het commentaar in de pagina hieronder voor hoe
    // de bundel er wél in komt. Daarmee kan `'unsafe-eval'` uit de CSP van deze
    // pagina en is de enige `eval()` in het product weg.
    //
    // `'unsafe-inline'` blijft nodig: dit ís een inline script. Dat is een
    // wezenlijk zwakkere ontheffing — er kan geen code meer ontstaan uit een
    // string die op dat moment wordt samengesteld.
    final escapedJs = jsonEncode(mermaidJs);
    final escapedInlinerJs = jsonEncode(inlinerJs);
    // Kanaal waarlangs de pagina de klaar-gerenderde SVG terugstuurt (#882).
    // Vóór het laden geregistreerd, zodat `MermaidChannel` bestaat wanneer de
    // render later vuurt.
    await _controller!.addJavaScriptChannel(
      'MermaidChannel',
      onMessageReceived: _onMermaidMessage,
    );
    await _controller!.loadHtmlString('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:">
</head>
<body>
<script>
// DIAGNOSTIEK (#882): de hele setup in try/catch. Bij pageload meldt de pagina
// via MermaidChannel of de setup slaagde en wat `typeof mermaid` is, of anders
// wélke fout hem brak. Zo is (met één beeldkeuring-ronde) te zien of de
// inline-setup draait en of de bundel laadt op WKWebView.
try {
// De bundel wordt als NIEUW script-element aan het document toegevoegd, niet
// ge-eval'd. Twee redenen. De CSP hierboven hoeft daardoor geen 'unsafe-eval'
// meer toe te staan. En een `var` op het hoogste niveau van een script wordt
// een globale — in een strict-mode eval niet, en moderne mermaid-bundels
// (esbuild, v11) hangen daarop: die zetten hun namespace met `var` en lezen
// hem daarna terug van globalThis.
var mermaidBundle = document.createElement('script');
mermaidBundle.textContent = $escapedJs;
document.head.appendChild(mermaidBundle);
// De stijl-inliner (#862), op dezelfde manier ingebracht.
var inlinerBundle = document.createElement('script');
inlinerBundle.textContent = $escapedInlinerJs;
document.head.appendChild(inlinerBundle);
var mermaidType = typeof window.mermaid;
// Dezelfde instellingen als de web-kant — zie kMermaidInitConfig
// (mermaid_config.dart) voor het waarom van elke sleutel (o.a. htmlLabels uit
// per diagramsoort). Als JSON in de pagina gezet, zodat de config maar op één
// plek staat en de twee renderpaden niet uiteen kunnen lopen.
mermaid.initialize(${jsonEncode(kMermaidInitConfig)});
// Async, dus we geven het resultaat NIET terug via runJavaScriptReturningResult
// (dat marshalt een Promise niet op macOS-WKWebView, #882) maar sturen de
// klaar-gerenderde SVG terug via het MermaidChannel, gekoppeld aan de meegegeven
// seq. De aanroeper (_run) vuurt dit met runJavaScript en wacht op het bericht.
window.__renderMermaid = function(source, seq) {
  mermaid.render('m' + seq, source).then(function(out) {
    // Mermaids theme zit in een <style>-blok dat flutter_svg negeert; inline het
    // (#862) zodat de kleuren/tekst wél verschijnen.
    var svg = window.__ocideckInlineSvgStyles ? window.__ocideckInlineSvgStyles(out.svg) : out.svg;
    MermaidChannel.postMessage(JSON.stringify({seq: seq, svg: svg}));
  }).catch(function(e) {
    MermaidChannel.postMessage(JSON.stringify({seq: seq, error: String(e)}));
  });
};
MermaidChannel.postMessage(JSON.stringify({diag: 'setup-ok', mermaid: mermaidType, render: typeof window.__renderMermaid, inliner: typeof window.__ocideckInlineSvgStyles}));
} catch (e) {
MermaidChannel.postMessage(JSON.stringify({diag: 'setup-error', error: String(e), mermaid: typeof window.mermaid}));
}
</script>
</body>
</html>
''');
    // NIET meteen als klaar markeren (#882): `loadHtmlString` resolvet zodra het
    // laden STÁRT, niet zodra het pagina-script draaide. Een render in dat gaatje
    // roept `runJavaScript('window.__renderMermaid(...)')` aan terwijl die functie
    // nog niet bestaat → `FWFEvaluateJavaScriptError` → grijs vlak; dát was de
    // bug. We wachten op het 'setup-ok'-bericht dat de pagina post zodra mermaid
    // geladen en `__renderMermaid` gedefinieerd is (zie [_onMermaidMessage]). Een
    // time-out markeert alsnog klaar, zodat een uitblijvend bericht de wachtrij
    // niet eeuwig laat hangen (dan valt een render hooguit terug op de brontekst).
    Future<void>.delayed(const Duration(seconds: 10), _markBootstrapReady);
  }

  /// Geef de wachtrij vrij zodra de pagina klaar is om te renderen (#882).
  void _markBootstrapReady() {
    if (_bootstrapped) return;
    _bootstrapped = true;
    _bootstrapCompleter?.complete();
    _bootstrapCompleter = null;
    _pumpQueue();
  }

  /// Returns SVG markup or `null` when rendering fails.
  Future<String?> render(String source) {
    // Op web is er geen WebView-host: het web-pad (JS-interop) draait mermaid
    // rechtstreeks in de app-pagina, dus `hostNeeded` blijft daar bewust uit.
    if (!kIsWeb) requestHost();
    final key = source.trim();
    if (key.isEmpty) return SynchronousFuture(null);
    final cached = _cache[key];
    if (cached != null) return SynchronousFuture(cached);

    final completer = Completer<String?>();
    _queue.add(_PendingRender(key, completer));
    _pumpQueue();
    return completer.future;
  }

  // Bounded so a long session with many distinct diagrams cannot grow the
  // cache without limit; rendered SVGs can each be tens of KB.
  final LruCache<String, String> _cache = LruCache(128);

  void _pumpQueue() {
    if (_busy || _queue.isEmpty) return;
    // Web rendert zonder WebView: geen controller en geen bootstrap om op te
    // wachten. Op IO blijft de oude voorwaarde staan.
    if (!kIsWeb) {
      if (_controller == null) return;
      if (!_bootstrapped) {
        _bootstrapCompleter ??= Completer<void>();
        _bootstrapCompleter!.future.then((_) => _pumpQueue());
        return;
      }
    }
    _busy = true;
    final job = _queue.removeAt(0);
    unawaited(_run(job));
  }

  Future<void> _run(_PendingRender job) async {
    try {
      final String? raw;
      if (kIsWeb) {
        // De JS-interop-renderer geeft de SVG rechtstreeks terug (geen
        // JSON-omhulsel zoals de WebView).
        raw = await web_renderer.renderMermaid(job.source);
      } else {
        // Vuur de render en wacht op het antwoord via het MermaidChannel (#882):
        // een Promise via runJavaScriptReturningResult marshalt niet op macOS.
        final seq = ++_renderSeq;
        final completer = Completer<String?>();
        _renderCompleter = completer;
        final encoded = jsonEncode(job.source);
        await _controller!.runJavaScript(
          'window.__renderMermaid($encoded, $seq)',
        );
        raw = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            logWarning('MermaidRender: WebView render timed out');
            return null;
          },
        );
      }
      final svg = sanitizeMermaidSvg(raw ?? '');
      if (svg != null && svg.contains('<svg')) {
        _cache[job.source] = svg;
        job.completer.complete(svg);
      } else {
        job.completer.complete(null);
      }
    } catch (e) {
      logError('MermaidRender: render failed', e);
      job.completer.complete(null);
    } finally {
      _busy = false;
      _pumpQueue();
    }
  }

  /// Ontvangt het render-antwoord van de WebView (#882) en lost de wachtende
  /// render op. Een bericht met de verkeerde seq (laat/verdwaald) of zonder
  /// wachtende render wordt genegeerd.
  void _onMermaidMessage(JavaScriptMessage message) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (e) {
      logWarning('MermaidRender: onleesbaar channel-bericht', e);
      return;
    }
    // Diagnostiek uit de pagina-setup (#882): geen render-antwoord, maar de
    // uitkomst van het bootstrappen — loggen zodat de beeldkeuring ziet of de
    // setup draaide en of de bundel laadde op WKWebView.
    if (data.containsKey('diag')) {
      // De pagina meldt dat de setup klaar is (of faalde): pas nú is
      // `window.__renderMermaid` gedefinieerd, dus nú mag de wachtrij lopen
      // (#882). Ook bij 'setup-error' vrijgeven — dan valt een render netjes
      // terug op de brontekst i.p.v. eeuwig te wachten.
      if (data['diag'] != 'setup-ok') {
        logWarning(
          'MermaidRender DIAG: ${data['diag']} '
          'mermaid=${data['mermaid']} error=${data['error']}',
        );
      }
      _markBootstrapReady();
      return;
    }
    final seq = (data['seq'] as num?)?.toInt();
    final completer = _renderCompleter;
    if (seq == null ||
        seq != _renderSeq ||
        completer == null ||
        completer.isCompleted) {
      return;
    }
    _renderCompleter = null;
    final error = data['error'];
    if (error != null) {
      logWarning('MermaidRender: WebView render error: $error');
      completer.complete(null);
    } else {
      completer.complete(data['svg'] as String?);
    }
  }
}

class _PendingRender {
  final String source;
  final Completer<String?> completer;

  _PendingRender(this.source, this.completer);
}

bool get isFlutterTest {
  if (kIsWeb) return false;
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (e) {
    logWarning('isFlutterTest: Platform.environment unavailable', e);
    return false;
  }
}
