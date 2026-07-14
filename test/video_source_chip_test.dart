import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/editors/video_slide_editor.dart';

Widget _host(Slide slide) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: VideoSlideEditor(
          slide: slide,
          onUpdate: (_) {},
          imageService: ImageService(),
        ),
      ),
    ),
  );
}

Color? _chipColor(WidgetTester tester, String label) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byType(VideoSlideEditor),
      matching: find.text(label),
    ),
  );
  return text.style?.color;
}

void main() {
  // De bron-chip benoemt de soort bron. Rood is in dit product de kleur van een
  // fout (het kwaliteitspaneel gebruikt hem zo), dus een geldige YouTube-link
  // mag er niet mee gelabeld worden — dat las als "deze video is stuk".
  testWidgets('YouTube source chip is not painted in a danger colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Slide.create(
          SlideType.video,
        ).copyWith(videoPath: 'https://www.youtube.com/watch?v=fZ5u46AjFCU'),
      ),
    );

    final color = _chipColor(tester, 'YouTube');
    expect(color, isNotNull);
    expect(
      color,
      isNot(
        anyOf(
          AppTheme.danger500,
          AppTheme.danger600,
          AppTheme.danger700,
          AppTheme.danger800,
          const Color(0xFFCC0000), // het oude "dangerPlain"-token
        ),
      ),
    );
  });

  testWidgets('every online source kind shares one non-danger chip colour', (
    tester,
  ) async {
    for (final url in const [
      'https://www.youtube.com/watch?v=fZ5u46AjFCU',
      'https://dewinter.com/img/video/ik-zal-je-leren-toxisch.mp4',
    ]) {
      await tester.pumpWidget(
        _host(Slide.create(SlideType.video).copyWith(videoPath: url)),
      );
      await tester.pump();
    }

    // De laatst gepompte bron is de directe .mp4-URL → "Online".
    expect(_chipColor(tester, 'Online'), AppTheme.teal);
  });
}
