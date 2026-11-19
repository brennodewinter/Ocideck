import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_win_floating/webview_plugin.dart';

import '../../services/website_style/website_style_proposal.dart';
import '../../services/website_style/website_style_source.dart';
import '../../utils/log.dart';
import '../../utils/ui_frame.dart';

/// An offline browser used only to resolve CSS and measure the rendered DOM.
class WebsiteStyleRenderer extends StatefulWidget {
  const WebsiteStyleRenderer({
    super.key,
    required this.snapshot,
    required this.onResult,
    required this.onError,
  });

  final WebsiteStyleSnapshot snapshot;
  final ValueChanged<WebsiteStyleProposal> onResult;
  final VoidCallback onError;

  @override
  State<WebsiteStyleRenderer> createState() => _WebsiteStyleRendererState();
}

class _WebsiteStyleRendererState extends State<WebsiteStyleRenderer> {
  WebViewController? _controller;
  Timer? _timeout;
  bool _finished = false;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 10), _fail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    try {
      final script = await rootBundle.loadString(
        'assets/website_style_probe.js',
      );
      if (!mounted || _finished) return;
      final windows = WebViewPlatform.instance is WindowsWebViewPlatform;
      final controller = WebViewController.fromPlatformCreationParams(
        windows
            ? const WindowsWebViewControllerCreationParams(
                offscreen: true,
                suspendDuringDeactive: false,
              )
            : const PlatformWebViewControllerCreationParams(),
      );
      setState(() => _controller = controller);
      await waitForUiFrame();
      if (!mounted || _finished) return;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!mounted || _finished) return;
      var initialLoadDone = false;
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final local =
                request.url == 'about:blank' ||
                request.url.startsWith('data:text/html');
            if (!initialLoadDone && request.isMainFrame && local) {
              initialLoadDone = true;
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          // The desktop delegate has no HTTP-auth callback; the snapshot CSP
          // blocks network resources on every platform.
          onHttpAuthRequest: windows ? null : (request) => request.onCancel(),
          onPageFinished: (_) => unawaited(_read(controller, script)),
        ),
      );
      if (mounted && !_finished) {
        await controller.loadHtmlString(widget.snapshot.html);
      }
    } catch (error) {
      logWarning('Website style renderer could not start', error.runtimeType);
      _fail();
    }
  }

  Future<void> _read(WebViewController controller, String script) async {
    if (!mounted || _finished || _probing) return;
    _probing = true;
    try {
      final result = await controller.runJavaScriptReturningResult(script);
      if (!mounted || _finished || result == '' || result == '""') return;
      final proposal = WebsiteStyleProposal.fromProbe(
        result,
        widget.snapshot.url,
      );
      _finished = true;
      _timeout?.cancel();
      widget.onResult(proposal);
    } catch (error) {
      logWarning(
        'Website style renderer could not read page',
        error.runtimeType,
      );
      _fail();
    } finally {
      _probing = false;
    }
  }

  void _fail() {
    if (!mounted || _finished) return;
    _finished = true;
    _timeout?.cancel();
    widget.onError();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    final platform = _controller?.platform;
    if (platform is WindowsPlatformWebViewController) {
      unawaited(platform.controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null ||
        controller.platform is WindowsPlatformWebViewController) {
      return const SizedBox.shrink();
    }
    return Offstage(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 1024,
        maxWidth: 1024,
        minHeight: 768,
        maxHeight: 768,
        child: WebViewWidget(controller: controller),
      ),
    );
  }
}
