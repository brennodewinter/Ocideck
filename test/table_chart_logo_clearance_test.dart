import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/rich_text_layout.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// #2091: een tabel of grafiek die de resthoogte vult mag niet door het
/// logo-vak heen. De gereduceerde strook (`size * edgeInset`) meet alleen de
/// spleet achter het logo; deze toets meet tegen het echte vak.
void main() {
  const profile = ThemeProfile(
    logoPath: 'logo.png',
    logoPosition: 'bottom-right',
    logoSize: 96,
  );

  const w = 1280.0;

  void drainOverflowExceptions(WidgetTester tester) {
    for (
      var ex = tester.takeException();
      ex != null;
      ex = tester.takeException()
    ) {
      if (!ex.toString().contains('overflowed')) {
        throw ex as Object;
      }
    }
  }

  double logoTop(Rect slideRect) {
    final size = slideRect.width * (profile.logoSize / 1280);
    return slideRect.bottom - size * (1 + kLogoBottomInsetFraction);
  }

  Future<Rect> pumpSlide(WidgetTester tester, Slide slide) async {
    await tester.binding.setSurfaceSize(const Size(w, w * 9 / 16));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: w,
            height: w * 9 / 16,
            child: SlidePreviewWidget(slide: slide, themeProfile: profile),
          ),
        ),
      ),
    );
    await tester.pump();
    drainOverflowExceptions(tester);
    return tester.getRect(find.byType(SlidePreviewWidget));
  }

  testWidgets('een korte tabel blijft boven het logo-vak (#2091)', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.table).copyWith(
      showLogo: true,
      title: 'Overzicht',
      tableRows: const [
        ['Kolom A', 'Kolom B'],
        ['1', '2'],
      ],
    );
    final slideRect = await pumpSlide(tester, slide);
    final tableBottom = tester.getRect(find.byType(Table)).bottom;
    expect(
      tableBottom,
      lessThanOrEqualTo(logoTop(slideRect) + 1.0),
      reason:
          'tabel eindigt ${tableBottom - logoTop(slideRect)}px in het logo-vak',
    );
  });

  testWidgets('een grafiek blijft boven het logo-vak (#2091)', (tester) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      title: 'Omzet',
      x: ['Q1', 'Q2', 'Q3'],
      series: [
        ChartSeries(name: '2026', data: [10, 14, 8]),
      ],
    );
    final slide = Slide.create(
      SlideType.chart,
    ).copyWith(showLogo: true, customMarkdown: spec.toBlock());
    final slideRect = await pumpSlide(tester, slide);
    final surfaceBottom = tester
        .getRect(find.byKey(const ValueKey('chart-surface')))
        .bottom;
    expect(
      surfaceBottom,
      lessThanOrEqualTo(logoTop(slideRect) + 1.0),
      reason:
          'grafiek eindigt ${surfaceBottom - logoTop(slideRect)}px in het logo-vak',
    );
  });
}
