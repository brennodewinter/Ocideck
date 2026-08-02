import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/editor_slide_preview.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

// `editorSlidePreview` is de gedeelde voorbeeld-wrapper die de editors via hun
// `previewBuilder` lui aanroepen — daardoor voerde geen enkele editor-test hem
// ooit uit. Deze test rendert hem rechtstreeks, zodat de 16:9-omkadering en de
// doorgifte naar [SlidePreviewWidget] werkelijk draaien.
void main() {
  testWidgets('editorSlidePreview wraps the slide preview in a 16:9 frame', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(customMarkdown: '# Demo\n');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 800,
            height: 450,
            child: editorSlidePreview(slide, projectPath: '/tmp/deck'),
          ),
        ),
      ),
    );

    expect(find.byType(SlidePreviewWidget), findsOneWidget);
    final aspect = tester.widget<AspectRatio>(
      find
          .ancestor(
            of: find.byType(SlidePreviewWidget),
            matching: find.byType(AspectRatio),
          )
          .first,
    );
    expect(aspect.aspectRatio, 16 / 9);
  });
}
