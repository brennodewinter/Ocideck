import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/slide_rasterizer.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/utils/image_preload.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:ocideck/widgets/document_signature_view.dart';

import 'support/pump_until.dart';

void main() {
  for (final slot in ['slide', 'logo', 'signature']) {
    testWidgets(
      'vastgelopen $slot stopt export, ruimt op en laat opnieuw proberen',
      (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (current) {
                  context = current;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );
        final bytes = Uint8List.fromList(
          img.encodePng(img.Image(width: 16, height: 16)),
        );
        final path = WebAssetStore.put(bytes, name: 'cloud.png');
        final signatureUri = 'data:image/png;base64,${base64Encode(bytes)}';
        addTearDown(() => WebAssetStore.retain(const {}));
        final audience = PrivacyProjection.forAudience(
          Deck(
            title: 'I/O timeout',
            themeProfile: ThemeProfile(logoPath: slot == 'logo' ? path : null),
            signature: slot == 'signature'
                ? DocumentSignature(name: 'Signer', imagePath: signatureUri)
                : null,
            slides: [
              Slide.create(
                SlideType.image,
              ).copyWith(title: 'Foto', imagePath: slot == 'slide' ? path : ''),
            ],
          ),
        );
        final cache = PaintingBinding.instance.imageCache;
        final oldSize = cache.maximumSize;
        final oldBytes = cache.maximumSizeBytes;
        // Een decode die nooit terugkomt, onder exact de key van de voorlader.
        final pending = OneFrameImageStreamCompleter(
          Completer<ImageInfo>().future,
        );
        cache.putIfAbsent(
          cappedMemoryImage(
            slot == 'signature'
                ? decodeEmbeddedSignatureImage(signatureUri)!
                : bytes,
          ),
          () => pending,
        );
        Object? failure;
        List<Uint8List>? result;
        var captured = 0;
        Future<void> run({required Duration imageTimeout}) async {
          await tester.runAsync(() async {
            unawaited(
              SlideRasterizer.rasterize(
                context: context,
                audience: audience,
                targetWidth: 160,
                imageTimeout: imageTimeout,
                onProgress: (done, _) => captured = done,
              ).then(
                (value) => result = value,
                onError: (Object error) => failure = error,
              ),
            );
          });
          await pumpUntil(tester, () => result != null || failure != null);
        }

        await run(imageTimeout: const Duration(milliseconds: 50));
        expect(
          failure,
          isA<ImagePreloadTimeout>().having(
            (e) => e.source,
            'source',
            slot == 'signature' ? 'signature' : path,
          ),
        );
        expect(result, isNull);
        expect(captured, 0);
        expect(cache.maximumSize, oldSize);
        expect(cache.maximumSizeBytes, oldBytes);
        expect(cache.pendingImageCount, 0);
        expect(pending.hasListeners, isFalse);
        await tester.pump();
        expect(find.byType(SlidePreviewWidget), findsNothing);

        // De onderliggende bytes zijn gezond: na de time-out mag een nieuwe
        // export niet dezelfde vastgelopen cache-entry overnemen. De gezonde
        // decode krijgt de gewone begrensde laadtijd, ook op een drukke runner.
        failure = null;
        await run(imageTimeout: imagePreloadTimeout);
        expect(failure, isNull);
        expect(result, hasLength(1));
        expect(result!.single.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect(captured, 1);
        expect(cache.maximumSizeBytes, oldBytes);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
