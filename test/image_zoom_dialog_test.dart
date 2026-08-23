import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/slides/image_zoom_dialog.dart';

/// Behaviour tests for the full-screen image zoom dialog: an unresolvable path
/// opens nothing, while an in-memory image opens a pan/zoom view with its
/// caption and a close action.
void main() {
  // A minimal valid 1×1 transparent PNG.
  final pngBytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    ),
  );

  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  Future<void> pumpOpener(
    WidgetTester tester, {
    required String imagePath,
    String caption = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showImageZoomDialog(
                context,
                imagePath: imagePath,
                caption: caption,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('an unresolvable path opens no dialog', (tester) async {
    await pumpOpener(tester, imagePath: 'bestaat-niet.png');

    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('an in-memory image opens a zoomable view with its caption', (
    tester,
  ) async {
    final memPath = WebAssetStore.put(pngBytes, name: 'bewijs.png');
    await pumpOpener(tester, imagePath: memPath, caption: 'Bewijsfoto');

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Bewijsfoto'), findsOneWidget);
  });

  testWidgets('the close button dismisses the dialog', (tester) async {
    final memPath = WebAssetStore.put(pngBytes, name: 'bewijs.png');
    await pumpOpener(tester, imagePath: memPath);

    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('a blank caption renders no caption banner', (tester) async {
    final memPath = WebAssetStore.put(pngBytes, name: 'bewijs.png');
    await pumpOpener(tester, imagePath: memPath, caption: '   ');

    // The only Text in the view is the close tooltip target, never a caption.
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('   '), findsNothing);
  });
}
