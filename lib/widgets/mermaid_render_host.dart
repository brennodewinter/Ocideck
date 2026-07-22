import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/mermaid_render_service.dart';

/// De widgetkant van [MermaidRenderService]: de verborgen WebView waarin de
/// diagrammen worden getekend. Die woont hier en niet bij de dienst, zodat de
/// renderdienst zelf headless blijft — bruikbaar en toetsbaar zonder widgetboom.

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
    // GEEN setBackgroundColor. Die stond hierboven in de cascade en gooide op
    // macOS `UnimplementedError: opaque is not implemented` — waarmee alles wat
    // erna kwam werd overgeslagen: de controller werd nooit toegekend,
    // `attachController` draaide nooit, en elk diagram bleef eeuwig op zijn
    // laadtolletje staan. De fout landde in een scheduler-callback en bereikte
    // de interface nooit.
    //
    // Weggelaten in plaats van afgevangen. Deze WebView staat offstage en tekent
    // niets — wat eruit komt is SVG-tekst — dus de achtergrondkleur was
    // decoratie zonder kijker. Een try/catch eromheen zou een tak opleveren die
    // op de meeste platforms nooit draait en dus stil kan rotten.
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
