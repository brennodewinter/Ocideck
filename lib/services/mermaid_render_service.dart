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
    // Geen `eval()` meer — zie het commentaar in de pagina hieronder voor hoe
    // de bundel er wél in komt. Daarmee kan `'unsafe-eval'` uit de CSP van deze
    // pagina en is de enige `eval()` in het product weg.
    //
    // `'unsafe-inline'` blijft nodig: dit ís een inline script. Dat is een
    // wezenlijk zwakkere ontheffing — er kan geen code meer ontstaan uit een
    // string die op dat moment wordt samengesteld.
    final escapedJs = jsonEncode(mermaidJs);
    await _controller!.loadHtmlString('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:">
</head>
<body>
<script>
// De bundel wordt als NIEUW script-element aan het document toegevoegd, niet
// ge-eval'd. Twee redenen. De CSP hierboven hoeft daardoor geen 'unsafe-eval'
// meer toe te staan. En een `var` op het hoogste niveau van een script wordt
// een globale — in een strict-mode eval niet, en moderne mermaid-bundels
// (esbuild, v11) hangen daarop: die zetten hun namespace met `var` en lezen
// hem daarna terug van globalThis. Onder eval liep dat dood op "Cannot read
// properties of undefined", zonder dat de app iets anders liet zien dan een
// diagram dat nooit verscheen.
var mermaidBundle = document.createElement('script');
mermaidBundle.textContent = $escapedJs;
document.head.appendChild(mermaidBundle);
// htmlLabels moet ook PER DIAGRAMSOORT uit: mermaid tekent labels anders in een
// <foreignObject>, en dat element haalt sanitizeMermaidSvg weg — dan houdt de
// preview lege vakjes over zonder één woord erin.
mermaid.initialize({
  startOnLoad: false,
  theme: 'neutral',
  securityLevel: 'strict',
  htmlLabels: false,
  flowchart: { htmlLabels: false },
  class: { htmlLabels: false },
  // De onaantastbare sleutels. Mermaids eigen standaardlijst wordt hierdoor
  // VERVANGEN, dus 'secure' en 'maxTextSize' moeten er zelf in: zonder 'secure'
  // kan een diagramrichtlijn de lijst overschrijven en daarmee de rest van de
  // beperkingen alsnog opheffen.
  secure: [
    'secure', 'securityLevel', 'startOnLoad', 'maxTextSize',
    'suppressErrorRendering', 'htmlLabels'
  ]
});
window.__renderMermaid = async function(source) {
  const id = 'm' + Math.abs(source.split('').reduce((h,c)=>((h<<5)-h+c.charCodeAt(0))|0,0));
  const out = await mermaid.render(id, source);
  return out.svg;
};
</script>
</body>
</html>
''');
    _bootstrapped = true;
    _bootstrapCompleter?.complete();
    _bootstrapCompleter = null;
    _pumpQueue();
  }

  /// Returns SVG markup or `null` when rendering fails.
  Future<String?> render(String source) {
    requestHost();
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
    if (_busy || _queue.isEmpty || _controller == null) return;
    if (!_bootstrapped) {
      _bootstrapCompleter ??= Completer<void>();
      _bootstrapCompleter!.future.then((_) => _pumpQueue());
      return;
    }
    _busy = true;
    final job = _queue.removeAt(0);
    unawaited(_run(job));
  }

  Future<void> _run(_PendingRender job) async {
    try {
      final encoded = jsonEncode(job.source);
      final raw = await _controller!.runJavaScriptReturningResult(
        'window.__renderMermaid($encoded)',
      );
      final svg = sanitizeMermaidSvg(_unwrapJsString(raw) ?? '');
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

  String? _unwrapJsString(Object? raw) {
    if (raw == null) return null;
    var text = raw.toString();
    if (text.startsWith('"') && text.endsWith('"') && text.length >= 2) {
      try {
        text = jsonDecode(text) as String;
      } catch (e) {
        logWarning('MermaidRender: JSON-string unwrap failed', e);
      }
    }
    return text;
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
