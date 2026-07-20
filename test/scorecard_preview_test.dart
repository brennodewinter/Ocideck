import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/scorecard_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 800,
        height: 450,
        child: SlidePreviewWidget(
          slide: slide,
          themeProfile: const ThemeProfile(),
        ),
      ),
    ),
  ),
);

Slide _scorecard(List<ScorecardEntry> entries, {String title = 'Stand'}) {
  final spec = ScorecardSpec(title: title, entries: entries);
  return Slide.create(
    SlideType.scorecard,
  ).copyWith(title: spec.title, tableRows: spec.toTableRows());
}

/// The colour the change line is drawn in, found by its arrow icon.
Color? _arrowColor(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon)).color;

/// The rendered size of a figure, to compare one layout against another.
double _fontSizeOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.fontSize!;

void main() {
  testWidgets('renders the title, each figure and its unit', (tester) async {
    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(label: 'Open bevindingen', value: 96, previous: 120),
          ScorecardEntry(
            label: 'Gemiddeld openstaand',
            value: 62,
            previous: 73,
            unit: 'dagen',
          ),
        ]),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Stand'), findsOneWidget);
    expect(find.text('Open bevindingen'), findsOneWidget);
    expect(find.text('96'), findsOneWidget);
    expect(find.text('dagen'), findsOneWidget);
  });

  testWidgets('a fall is drawn as a downward arrow and a signed change', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(label: 'Open', value: 96, previous: 120),
        ]),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    // Signed, so the direction survives a greyscale print.
    expect(find.text('-24'), findsOneWidget);
  });

  testWidgets('polarity decides the colour, not the direction', (tester) async {
    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(
            label: 'Open',
            value: 96,
            previous: 120,
            polarity: ScorecardPolarity.lowerBetter,
          ),
        ]),
      ),
    );
    await tester.pump();

    // Down and green: fewer open findings is good news.
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(
      _arrowColor(tester, Icons.arrow_downward_rounded),
      AppTheme.success700,
    );

    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(
            label: 'Gedekt',
            value: 96,
            previous: 120,
            polarity: ScorecardPolarity.higherBetter,
          ),
        ]),
      ),
    );
    await tester.pump();

    // The same fall, now red — the arrow did not move, the verdict did.
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(
      _arrowColor(tester, Icons.arrow_downward_rounded),
      AppTheme.danger700,
    );
  });

  testWidgets('without a previous figure no change is drawn at all', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_scorecard(const [ScorecardEntry(label: 'Open', value: 96)])),
    );
    await tester.pump();

    expect(find.text('96'), findsOneWidget);
    // No arrow in any direction: a first report has no trend to claim.
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
  });

  testWidgets('an unchanged figure says so instead of showing a zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(
            label: 'Kritiek',
            value: 8,
            previous: 8,
            polarity: ScorecardPolarity.lowerBetter,
          ),
        ]),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.text('ongewijzigd'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
  });

  testWidgets('five figures with long labels still fit their tiles', (
    tester,
  ) async {
    // Five is the documented maximum, so five must fit — including labels of
    // real length and a unit beside the figure. Caught by rendering the slide
    // and finding Flutter's overflow stripes across it.
    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(label: 'Assets in beeld', value: 412, previous: 375),
          ScorecardEntry(
            label: 'Open bevindingen',
            value: 96,
            previous: 120,
            polarity: ScorecardPolarity.lowerBetter,
          ),
          ScorecardEntry(
            label: 'Waarvan kritiek',
            value: 8,
            previous: 5,
            polarity: ScorecardPolarity.lowerBetter,
          ),
          ScorecardEntry(
            label: 'Gemiddeld openstaand',
            value: 62,
            previous: 73,
            unit: 'dagen',
            polarity: ScorecardPolarity.lowerBetter,
          ),
          ScorecardEntry(label: 'Nieuw deze maand', value: 18),
        ]),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('one figure is drawn far larger than one of five', (
    tester,
  ) async {
    // The point of the layout: a scorecard with a single figure is a different
    // slide from one with five, and gets the whole slide to say so. Measured on
    // the same figure so only the layout differs.
    await tester.pumpWidget(
      _host(_scorecard(const [ScorecardEntry(label: 'Open', value: 96)])),
    );
    await tester.pump();
    final hero = _fontSizeOf(tester, '96');

    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(label: 'Assets', value: 412),
          ScorecardEntry(label: 'Open', value: 96),
          ScorecardEntry(label: 'Kritiek', value: 8),
          ScorecardEntry(label: 'Openstaand', value: 62),
          ScorecardEntry(label: 'Nieuw', value: 18),
        ]),
      ),
    );
    await tester.pump();

    expect(hero, greaterThan(_fontSizeOf(tester, '96') * 2));
  });

  testWidgets('the card names the figure it replaced', (tester) async {
    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(
            label: 'Gemiddeld openstaand',
            value: 62,
            previous: 73,
            unit: 'dagen',
          ),
        ]),
      ),
    );
    await tester.pump();

    // The unit rides along: "was 73" would read as a different quantity.
    expect(find.text('was 73 dagen'), findsOneWidget);
  });

  testWidgets('without a previous figure there is nothing to have been', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_scorecard(const [ScorecardEntry(label: 'Open', value: 96)])),
    );
    await tester.pump();

    expect(find.textContaining('was'), findsNothing);
  });

  testWidgets('four figures are laid out two by two', (tester) async {
    // Four in a single row would be four thin strips; the 2×2 block is what
    // keeps the figures big. Asserted on the geometry, since that is the whole
    // claim: two cards share the top edge, the other two sit below them.
    await tester.pumpWidget(
      _host(
        _scorecard(const [
          ScorecardEntry(label: 'Assets', value: 412),
          ScorecardEntry(label: 'Open', value: 96),
          ScorecardEntry(label: 'Kritiek', value: 8),
          ScorecardEntry(label: 'Nieuw', value: 18),
        ]),
      ),
    );
    await tester.pump();

    final tops = [
      for (final label in ['Assets', 'Open', 'Kritiek', 'Nieuw'])
        tester.getTopLeft(find.text(label)).dy,
    ];
    expect(tops[0], tops[1]);
    expect(tops[2], tops[3]);
    expect(tops[2], greaterThan(tops[0]));
  });

  testWidgets('an empty scorecard renders without a figure', (tester) async {
    await tester.pumpWidget(_host(_scorecard(const [])));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Stand'), findsOneWidget);
  });
}
