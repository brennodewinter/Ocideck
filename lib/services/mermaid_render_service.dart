import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/log.dart';
import '../utils/lru_cache.dart';
import '../utils/sanitize_svg.dart';

/// Renders Mermaid diagram source to inline SVG for preview, presenter, and
/// raster export (WYSIWYG). Results are cached by trimmed source text.
///
/// The hidden [WebViewWidget] is mounted lazily via [MermaidRenderHostLayer]
/// only after the first diagram is requested — never in the MaterialApp builder,
/// which breaks macOS frame scheduling when combined with multi-window.
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
mermaid.initialize({
  startOnLoad: false,
  theme: 'neutral',
  securityLevel: 'strict',
  htmlLabels: false,
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

/// Mounts [MermaidRenderHost] only after a diagram is first requested.
class MermaidRenderHostLayer extends StatelessWidget {
  const MermaidRenderHostLayer({super.key});

  @override
  Widget build(BuildContext context) {
    if (isFlutterTest) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: MermaidRenderService.instance.hostNeeded,
      builder: (context, needed, child) {
        if (!needed) return const SizedBox.shrink();
        return child!;
      },
      child: const MermaidRenderHost(),
    );
  }
}

/// Offstage WebView that boots the shared Mermaid renderer.
class MermaidRenderHost extends StatefulWidget {
  const MermaidRenderHost({super.key});

  @override
  State<MermaidRenderHost> createState() => _MermaidRenderHostState();
}

class _MermaidRenderHostState extends State<MermaidRenderHost> {
  WebViewController? _controller;
  var _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    // Defer platform-view creation until after the first frame so we never
    // compete with engine/window startup (macOS multi-window + WebView).
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWebView());
  }

  void _initWebView() {
    if (!mounted || _controller != null) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!_initialLoadDone) {
              _initialLoadDone = true;
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onHttpAuthRequest: (request) async {
            // Deny auth prompts from the offline renderer.
          },
        ),
      );
    setState(() => _controller = controller);
    MermaidRenderService.instance.attachController(controller);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Offstage(
        offstage: true,
        child: SizedBox(
          width: 320,
          height: 240,
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
  }
}
