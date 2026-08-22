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

/// Rendert de twee gebundelde JS-renderers naar inline SVG: Mermaid-diagrammen
/// ([render]) en TeX-formules ([renderMath], via MathJax `tex-svg`). Voor de
/// voorvertoning, de presentator, de raster-export (WYSIWYG) en — voor beide —
/// de PDF van een document. Uitkomsten worden gesleuteld op de bijgesneden bron.
///
/// Eén verborgen pagina voor allebei, en niet twee: het monteren van de host,
/// het wachten op de bootstrap en het serialiseren van de wachtrij zijn precies
/// de delen die hier moeizaam goed zijn gekregen (#882). Die twee keer hebben is
/// twee keer hetzelfde kunnen breken.
///
/// De naam is daarmee smaller geworden dan wat de klasse doet; hernoemen raakt
/// eenendertig plekken en hoort in een eigen wijziging thuis, niet verstopt in
/// deze.
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

  /// Of er op dit platform überhaupt gerenderd kan worden.
  ///
  /// De verborgen WebView bestaat alleen waar `webview_flutter` een
  /// implementatie heeft: Android, iOS en macOS. **Windows en Linux hebben er
  /// geen** (zie `pubspec.lock`: android, wkwebview, web — meer niet), en dan is
  /// `WebViewPlatform.instance` null. Zonder deze vraag zou een render daar de
  /// host laten monteren, zou die een `WebViewController` bouwen, en zou dát
  /// gooien — een documentexport die eerst gewoon lukte, sloopt dan op één
  /// diagram.
  ///
  /// Op web is er een eigen weg (JS-interop in de app-pagina zelf), dus daar is
  /// het antwoord ja zonder dat er een platform-instantie hoeft te zijn.
  bool get isAvailable => kIsWeb || WebViewPlatform.instance != null;

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
    // Dezelfde MathJax-bundel die de HTML-export inlijnt: `tex-svg`, dus zonder
    // externe lettertypebestanden — de glyphs komen als paden mee. Daardoor is
    // de uitkomst een op zichzelf staande SVG die ook in een PDF te zetten is.
    final mathJs = await rootBundle.loadString('assets/web_export/tex-svg.js');
    // Geen `eval()` meer — zie het commentaar in de pagina hieronder voor hoe
    // de bundel er wél in komt. Daarmee kan `'unsafe-eval'` uit de CSP van deze
    // pagina en is de enige `eval()` in het product weg.
    //
    // `'unsafe-inline'` blijft nodig: dit ís een inline script. Dat is een
    // wezenlijk zwakkere ontheffing — er kan geen code meer ontstaan uit een
    // string die op dat moment wordt samengesteld.
    final escapedJs = jsonEncode(mermaidJs);
    final escapedInlinerJs = jsonEncode(inlinerJs);
    final escapedMathJs = jsonEncode(mathJs);
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
// MathJax, op dezelfde manier ingebracht. `startup.typeset: false` omdat we
// zelf per formule `tex2svgPromise` aanroepen in plaats van de pagina te laten
// scannen — er stáát hier geen document om te scannen.
window.MathJax = {startup: {typeset: false}, options: {enableMenu: false}};
var mathBundle = document.createElement('script');
mathBundle.textContent = $escapedMathJs;
document.head.appendChild(mathBundle);
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
// Formule → SVG. Dezelfde afspraak als __renderMermaid: het antwoord komt via
// het channel, gekoppeld aan de seq.
window.__renderMath = function(tex, seq) {
  try {
    MathJax.startup.promise.then(function() {
      return MathJax.tex2svgPromise(tex, {display: true});
    }).then(function(node) {
      var svg = node.querySelector('svg');
      MermaidChannel.postMessage(JSON.stringify({
        seq: seq,
        svg: svg ? svg.outerHTML : null,
        error: svg ? null : 'geen svg'
      }));
    }).catch(function(e) {
      MermaidChannel.postMessage(JSON.stringify({seq: seq, error: String(e)}));
    });
  } catch (e) {
    MermaidChannel.postMessage(JSON.stringify({seq: seq, error: String(e)}));
  }
};
MermaidChannel.postMessage(JSON.stringify({diag: 'setup-ok', mermaid: mermaidType, render: typeof window.__renderMermaid, math: typeof window.__renderMath, inliner: typeof window.__ocideckInlineSvgStyles}));
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
  Future<String?> render(String source) =>
      _enqueue(source, _RenderKind.mermaid);

  /// Zet een TeX-formule om in zelfstandige SVG, of `null` als dat niet lukt.
  ///
  /// Op web niet beschikbaar: daar draait de app als CanvasKit-pagina zonder de
  /// verborgen WebView, en het web-pad van [render] kent alleen mermaid. Een
  /// aanroeper hoort met `null` om te kunnen gaan — de documentexport valt dan
  /// terug op de bron van de formule.
  Future<String?> renderMath(String tex) {
    if (kIsWeb) return SynchronousFuture(null);
    return _enqueue(tex, _RenderKind.math);
  }

  Future<String?> _enqueue(String source, _RenderKind kind) {
    // Eerst de vraag of hier gerenderd kán worden: zo niet, dan meteen niets
    // teruggeven in plaats van een host te laten monteren die niet bestaat.
    // De aanroeper valt dan netjes terug — een diagram in zijn brontekst, geen
    // stukgelopen export.
    if (!isAvailable) return SynchronousFuture(null);
    // Op web is er geen WebView-host: het web-pad (JS-interop) draait mermaid
    // rechtstreeks in de app-pagina, dus `hostNeeded` blijft daar bewust uit.
    if (!kIsWeb) requestHost();
    final source0 = source.trim();
    if (source0.isEmpty) return SynchronousFuture(null);
    // De soort hoort in de sleutel: een formule en een diagram met toevallig
    // dezelfde tekst zijn niet hetzelfde plaatje.
    final key = '${kind.name}:$source0';
    final cached = _cache[key];
    if (cached != null) return SynchronousFuture(cached);

    final completer = Completer<String?>();
    _queue.add(_PendingRender(source0, kind, completer));
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
        // JSON-omhulsel zoals de WebView). Formules komen hier niet: die zijn
        // op web al bij [renderMath] afgevangen.
        raw = await web_renderer.renderMermaid(job.source);
      } else {
        // Vuur de render en wacht op het antwoord via het MermaidChannel (#882):
        // een Promise via runJavaScriptReturningResult marshalt niet op macOS.
        final seq = ++_renderSeq;
        final completer = Completer<String?>();
        _renderCompleter = completer;
        final encoded = jsonEncode(job.source);
        final entry = job.kind == _RenderKind.math
            ? '__renderMath'
            : '__renderMermaid';
        await _controller!.runJavaScript('window.$entry($encoded, $seq)');
        raw = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            logWarning(
              'MermaidRender: WebView ${job.kind.name} render timed out',
            );
            return null;
          },
        );
      }
      // Ook de MathJax-uitvoer gaat door de schoonmaak: het is uitvoer van een
      // JS-renderer, en de whitelist laat juist door wat MathJax gebruikt
      // (`defs`, `use`, `symbol`, `href`).
      final svg = sanitizeMermaidSvg(raw ?? '');
      if (svg != null && svg.contains('<svg')) {
        _cache['${job.kind.name}:${job.source}'] = svg;
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
        // De fouttekst komt uit een renderer van gebruikersinhoud en kan die
        // inhoud letterlijk herhalen. Houd het log daarom op een vaste melding.
        logWarning('MermaidRender: WebView setup mislukt');
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
      // MathJax/Mermaid-fouten kunnen de ingevoerde bron herhalen. Die hoort
      // niet in het log; de vaste melding is voldoende voor diagnostiek.
      logWarning('MermaidRender: WebView render mislukt');
      completer.complete(null);
    } else {
      completer.complete(data['svg'] as String?);
    }
  }
}

/// Welke van de twee gebundelde renderers een wachtend verzoek nodig heeft.
enum _RenderKind { mermaid, math }

class _PendingRender {
  final String source;
  final _RenderKind kind;
  final Completer<String?> completer;

  _PendingRender(this.source, this.kind, this.completer);
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
