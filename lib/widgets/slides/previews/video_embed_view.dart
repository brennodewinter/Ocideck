import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Native desktop child windows paint above Flutter dialogs. Hide the surface
/// while its route is covered, keeping the controller and document alive.
class VideoEmbedView extends StatelessWidget {
  final WebViewController controller;

  const VideoEmbedView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final nativeDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    final visible = !nativeDesktop || (ModalRoute.isCurrentOf(context) ?? true);
    return Visibility(
      visible: visible,
      child: WebViewWidget(controller: controller),
    );
  }
}
