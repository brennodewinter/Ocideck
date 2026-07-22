import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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
  void requestHost() {
    if (!hostNeeded.value) hostNeeded.value = true;
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
    // Het bundeltje gaat rechtstreeks in een <script>-blok, niet meer via
    // `textContent` + `eval()`.
    //
    // Die omweg bestond om een `</script`-reeks binnen de geminificeerde bundel
    // het HTML-blok niet te laten afbreken. Dat is op te lossen door die reeks
    // te ontsnappen — dezelfde `<\/script`-truc die `MarpHtmlService` op de
    // export toepast — en dan is er geen dynamische code-evaluatie meer nodig.
    // Daarmee kan `'unsafe-eval'` uit de CSP van deze pagina: de enige `eval()`
    // in het product is hiermee weg.
    //
    // `'unsafe-inline'` blijft nodig — dit ís een inline script — maar dat is
    // een wezenlijk zwakkere ontheffing: er kan geen code meer ontstaan uit een
    // string die op dat moment wordt samengesteld.
    final inlineJs = mermaidJs.replaceAllMapped(
      RegExp(r'</(script)', caseSensitive: false),
      (m) => '<\\/${m.group(1)}',
    );
    await _controller!.loadHtmlString('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:">
</head>
<body>
<script>
$inlineJs
</script>
<script>
mermaid.initialize({
  startOnLoad: false,
  theme: 'neutral',
  securityLevel: 'strict',
  htmlLabels: false,
  // `flowchart.htmlLabels` staat standaard op true en het topniveau zakt daar
  // niet in door. Zonder deze regel zetten flowchart, classDiagram en
  // stateDiagram-v2 hun labels in <foreignObject> — en `sanitizeMermaidSvg`
  // strípt dat, terecht, waardoor de gebruiker lege blokjes en lege pijlen
  // overhield. Deze drie delen dezelfde renderweg, dus één sleutel repareert
  // ze alle drie; `class:` en `state:` bestaan wél maar doen hier niets.
  flowchart: { htmlLabels: false },
  // `htmlLabels` in `secure` is wat een deck tegenhoudt dat via
  // `%%{init: {"flowchart": {"htmlLabels": true}}}%%` alsnog HTML in de labels
  // probeert te krijgen — mermaid past die lijst op élke diepte toe, niet
  // alleen op het topniveau. `flowchart` zélf hier bijzetten voegt daar niets
  // aan toe en kost wel iets: dan ligt het hele flowchart-configblok vast en
  // kan een deck ook geen `curve`, `padding` of `nodeSpacing` meer kiezen.
  secure: ['securityLevel', 'startOnLoad', 'htmlLabels']
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
