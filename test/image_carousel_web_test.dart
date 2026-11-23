@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'support/pump_until.dart';

void main() {
  testWidgets('plakken in de webkiezer geeft een geheugenpad terug (#3120)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(WebAssetStore.clear);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
      'hKmMIQAAAABJRU5ErkJggg==',
    );
    final blob = web.Blob(
      [png.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final item = web.ClipboardItem({'image/png': blob}.jsify()! as JSObject);
    final clipboard = web.window.navigator.clipboard;
    final read = 'read'.toJS;
    final previousRead = clipboard.getProperty<JSFunction>(read);
    final clipboardItems = <web.ClipboardItem>[];
    clipboard.setProperty(
      read,
      (() => Future.value(clipboardItems.toJS).toJS).toJS,
    );
    addTearDown(() => clipboard.setProperty(read, previousRead));

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final initialPath = WebAssetStore.put(png, name: 'bestaand.png');
    ImagePickResult? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await ImageCarouselPicker.show(
                    context,
                    initialPath: initialPath,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final paste = find.text('Afbeelding plakken');
    await tester.runAsync(() => tester.tap(paste));
    final emptyMessage = find.text('Geen afbeelding op het klembord.');
    await pumpUntil(tester, () => emptyMessage.evaluate().isNotEmpty);
    expect(result, isNull);

    clipboardItems.add(item);
    await tester.runAsync(() => tester.tap(paste));
    await pumpUntil(tester, () => result != null);
    await tester.pumpAndSettle();
    expect(find.byType(ImageCarouselPicker), findsNothing);
    expect(WebAssetStore.bytesFor(result!.path), png);
  });
}
