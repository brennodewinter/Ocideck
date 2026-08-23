import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/image_slide_editor.dart';

class _FakeImageService extends ImageService {
  final String? pastedPath;

  _FakeImageService({this.pastedPath});

  @override
  Future<ImageImportOutcome> pasteImageDetailed({String? projectPath}) async =>
      pastedPath == null
      ? const ImageImportOutcome.failed(ImageImportFailure.noClipboardImage)
      : ImageImportOutcome.success(pastedPath);
}

Widget _host(
  Slide slide,
  ImageService imageService,
  ValueChanged<Slide> onUpdate,
) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: ImageSlideEditor(
          slide: slide,
          onUpdate: onUpdate,
          imageService: imageService,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('pasted full-slide image starts fully visible', (tester) async {
    var updated = Slide.create(SlideType.image);
    await tester.pumpWidget(
      _host(
        updated,
        _FakeImageService(pastedPath: '/tmp/pasted.png'),
        (slide) => updated = slide,
      ),
    );

    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();

    expect(updated.imagePath, '/tmp/pasted.png');
    expect(updated.imageSize, 100);
  });

  testWidgets('carousel selection resets an old crop to fully visible', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.image,
    ).copyWith(imagePath: 'old.png', imageSize: 160);
    await tester.pumpWidget(
      _host(updated, _FakeImageService(), (slide) => updated = slide),
    );

    final picker = tester.widget<ImagePickerBar>(find.byType(ImagePickerBar));
    picker.onPicked('new.png', 'Bijschrift');

    expect(updated.imagePath, 'new.png');
    expect(updated.imageCaption, 'Bijschrift');
    expect(updated.imageSize, 100);
  });

  testWidgets('slide-filling checkbox toggles cover mode (imageSize 0)', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.image,
    ).copyWith(imagePath: 'photo.png', imageSize: 100);
    await tester.pumpWidget(
      _host(updated, _FakeImageService(), (slide) => updated = slide),
    );

    // Off by default: the image is shown in full and the zoom control applies.
    expect(find.text('Zoom afbeelding'), findsOneWidget);

    // Tick "slide-filling" → cover mode (imageSize 0).
    await tester.tap(find.text('Afbeelding slidevullend'));
    await tester.pump();
    expect(updated.imageSize, 0);

    // Re-pump with the cover-mode slide: the zoom control is now hidden, and
    // unticking restores the full-image (contain) default.
    await tester.pumpWidget(
      _host(updated, _FakeImageService(), (slide) => updated = slide),
    );
    await tester.pump();
    expect(find.text('Zoom afbeelding'), findsNothing);

    await tester.tap(find.text('Afbeelding slidevullend'));
    await tester.pump();
    expect(updated.imageSize, 100);
  });

  // Het pad staat er om overgenomen te worden — uit een privacybevinding komt
  // een bestandsnaam als `images/pasted_1781245807752.png`, en die overtypen
  // gaat mis. De placeholder blijft er bewust buiten: daar valt niets te
  // kopiëren, en een selecteerbare uitnodiging tot niets is misleidend.
  testWidgets('the image path is selectable, the placeholder is not', (
    tester,
  ) async {
    var slide = Slide.create(SlideType.image);
    await tester.pumpWidget(
      _host(slide, _FakeImageService(), (updated) => slide = updated),
    );
    await tester.pump();
    expect(find.byType(SelectionArea), findsNothing);

    slide = slide.copyWith(imagePath: 'images/pasted_1781245807752.png');
    await tester.pumpWidget(
      _host(slide, _FakeImageService(), (updated) => slide = updated),
    );
    await tester.pump();

    final selectable = find.ancestor(
      of: find.text('images/pasted_1781245807752.png'),
      matching: find.byType(SelectionArea),
    );
    expect(selectable, findsOneWidget);
  });
}
