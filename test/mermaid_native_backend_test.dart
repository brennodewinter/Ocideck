import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/mermaid_render_service.dart';
import 'package:ocideck/widgets/mermaid_render_host.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_win_floating/webview_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native renderer creates an offscreen controller without a view',
    (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('webview_win_floating');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'create' ? true : null;
          });
      WebViewPlatform.instance = WindowsWebViewPlatform();
      final service = MermaidRenderService.instance;
      expect(service.isAvailable, isTrue);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MermaidRenderHost(),
        ),
      );
      await tester.pump();
      final creation = calls.singleWhere((c) => c.method == 'create');
      expect(creation.arguments['offscreen'], isTrue);
      expect(find.byType(Offstage), findsNothing);
      expect(find.byType(PlatformViewLink), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.any((c) => c.method == 'dispose'), isTrue);
      expect(service.hostNeeded.value, isFalse);
    },
  );
}
