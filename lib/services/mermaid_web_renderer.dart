import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../utils/log.dart';
import 'mermaid_config.dart';

/// De web-kant van de Mermaid-render (#851).
///
/// Op web kán de verborgen WebView-renderer niet werken: `webview_flutter_web`
/// implementeert `runJavaScriptReturningResult` niet — het erft de
/// `UnimplementedError` uit de basisklasse — en de WebView-renderer leunt daar
/// volledig op. Elke render gaf daardoor stil `null` terug en het diagram bleef
/// een leeg vlak.
///
/// Hier draaien we de gebundelde mermaid.min.js rechtstreeks in de app-pagina.
/// Dat mag onder de strikte app-CSP (`script-src 'self' 'wasm-unsafe-eval'`):
///
///  * het script wordt als `<script src>` van de eigen origin geladen — 'self'
///    dekt dat. Inline of via `blob:` injecteren kan niet (geen 'unsafe-inline',
///    geen blob: in script-src), vandaar de URL en niet de tekst;
///  * mermaid heeft geen `eval()` nodig: de WebView-bootstrap draaide het al
///    onder een CSP zónder 'unsafe-eval'. Daarom is 'wasm-unsafe-eval' (voor
///    CanvasKit) genoeg en hoeft er niets aan de app-CSP versoepeld te worden.
///
/// De teruggegeven SVG wordt door de aanroeper (`MermaidRenderService`) nog met
/// `sanitizeMermaidSvg` opgeschoond, net als bij de WebView-kant.

@JS('mermaid')
external _JsMermaid? get _mermaidGlobal;

/// De handvol mermaid-functies die we gebruiken.
extension type _JsMermaid(JSObject _) implements JSObject {
  external void initialize(JSObject config);
  external JSPromise<JSObject> render(String id, String source);
}

/// Het resultaat van `mermaid.render`: `{ svg, bindFunctions, ... }`.
extension type _RenderResult(JSObject _) implements JSObject {
  external String get svg;
}

/// De gebundelde SVG-stijl-inliner (svg_style_inline.js, #862) op `window`, of
/// null zolang die (nog) niet geladen is.
@JS('__ocideckInlineSvgStyles')
external JSFunction? get _inlineSvgStylesFn;

/// Zet mermaids theme-styling (die in een `<style>`-blok zit dat flutter_svg
/// negeert) als inline attributen op de SVG, of geef de SVG ongewijzigd terug
/// als de inliner er niet is. Zie [_loadInliner].
String _applyStyleInliner(String svg) {
  final fn = _inlineSvgStylesFn;
  if (fn == null) return svg;
  final result = fn.callAsFunction(null, svg.toJS)?.dartify();
  return result is String ? result : svg;
}

/// Laadt en initialiseert mermaid één keer per sessie.
Future<void>? _loaded;

/// Uniek id per render; mermaid gebruikt het als element-id.
int _counter = 0;

Future<void> _ensureLoaded() {
  final pending = _loaded;
  if (pending != null) return pending;

  final completer = Completer<void>();
  _loaded = completer.future;

  // Al aanwezig (bijvoorbeeld na een hot restart): alleen (her)initialiseren.
  if (_mermaidGlobal != null) {
    _initialize();
    _loadInliner(completer);
    return completer.future;
  }

  // Een mislukte lading niet permanent onthouden: bij een fout wordt `_loaded`
  // teruggezet op null zodat een volgende render het opnieuw mag proberen. Zonder
  // dit zou één transiënte laadfout (netwerk, een korte hapering) mermaid voor de
  // hele sessie uitschakelen. Fail-closed blijft het per render — een render die
  // faalt valt terug op de brontekst — maar niet voor altijd.
  final script = web.HTMLScriptElement()..src = kMermaidWebScriptUrl;
  script.addEventListener(
    'load',
    (web.Event _) {
      try {
        _initialize();
        _loadInliner(completer);
      } catch (e) {
        logError('MermaidWebRenderer: init na load mislukt', e);
        _loaded = null;
        completer.completeError(e);
      }
    }.toJS,
  );
  script.addEventListener(
    'error',
    (web.Event _) {
      final error = StateError('mermaid.min.js kon niet laden');
      logError('MermaidWebRenderer: script laden mislukt', error);
      _loaded = null;
      completer.completeError(error);
    }.toJS,
  );
  web.document.head!.appendChild(script);
  return completer.future;
}

void _initialize() {
  _mermaidGlobal!.initialize(kMermaidInitConfig.jsify() as JSObject);
}

/// Laadt de gebundelde stijl-inliner (#862) en voltooit dan [completer]. Een
/// laadfout mag mermaid niet uitschakelen: zonder de inliner tekent flutter_svg
/// het diagram nog steeds, alleen ongestyled — daarom completen we ook bij een
/// fout (en niet met `completeError`).
void _loadInliner(Completer<void> completer) {
  if (_inlineSvgStylesFn != null) {
    completer.complete();
    return;
  }
  final script = web.HTMLScriptElement()..src = kSvgStyleInlineScriptUrl;
  script.addEventListener(
    'load',
    (web.Event _) {
      completer.complete();
    }.toJS,
  );
  script.addEventListener(
    'error',
    (web.Event _) {
      logWarning('MermaidWebRenderer: SVG-stijl-inliner kon niet laden (#862)');
      completer.complete();
    }.toJS,
  );
  web.document.head!.appendChild(script);
}

/// Rendert [source] naar SVG-opmaak, of `null` als dat niet lukt.
///
/// De aanroepen worden door [MermaidRenderService] al geserialiseerd (één
/// tegelijk), dus hier is geen eigen wachtrij nodig.
Future<String?> renderMermaid(String source) async {
  try {
    await _ensureLoaded();
    final mermaid = _mermaidGlobal;
    if (mermaid == null) return null;
    final id = 'm${_counter++}';
    final result = _RenderResult(await mermaid.render(id, source).toDart);
    return _applyStyleInliner(result.svg);
  } catch (e) {
    // Ongeldige diagrambron of een render die faalt: terugval op de brontekst,
    // net als op desktop. Geen ruwe uitzondering naar de widgetboom.
    logError('MermaidWebRenderer: render mislukt', e);
    return null;
  }
}
