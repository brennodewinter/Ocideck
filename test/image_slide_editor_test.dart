import 'package:flutter/material.dart';
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
  Future<String?> pasteImage() async => pastedPath;
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
}
