import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// De bullet-grafiek in beeld: norm en prestatie op één meetlat.
///
/// Het punt van deze vorm is dat de norm als *norm* getekend wordt — een
/// streepje op de lat — en niet als tweede staaf. Bij een SLA-verhaal is dat
/// het verschil tussen "twee getallen" en "gehaald of niet gehaald". Wat hier
/// getoetst wordt is dus de meetkunde: staat het streepje waar de norm ligt, en
/// staat de balk waar de meting ligt?
///
/// `bullet_chart_test.dart` toetst het model (de asgrens); dit toetst wat de
/// kijker ziet.
Widget _host(ChartSpec spec, {double width = 800, double height = 450}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: SlidePreviewWidget(
            slide: Slide.create(
              SlideType.chart,
            ).copyWith(customMarkdown: spec.toBlock()),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const spec = ChartSpec(
    type: ChartType.bullet,
    title: 'Verhelptijd tegen norm',
    x: ['Kritiek (14d)', 'Hoog (30d)', 'Middel (90d)'],
    series: [
      ChartSeries(name: 'Gehaald', data: [38, 61, 84]),
    ],
    targets: [90, 90, 80],
    bands: [60, 80],
  );

  /// Het smalle, volledig gekleurde blokje is het streefstreepje: 2,5 breed.
  List<Rect> targetTicks(WidgetTester tester) => [
    for (final element in find.byType(ColoredBox).evaluate())
      if (tester.getSize(find.byWidget(element.widget)).width < 4)
        tester.getRect(find.byWidget(element.widget)),
  ];

  testWidgets('elke rij krijgt zijn eigen label', (tester) async {
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    for (final label in spec.x) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('de norm is een streepje, geen tweede staaf', (tester) async {
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final ticks = targetTicks(tester);
    expect(ticks.length, spec.x.length, reason: 'één streepje per rij');
    for (final tick in ticks) {
      // Een streepje, geen balk: als het als tweede staaf getekend werd, zou
      // het meelopen met de breedte van de rij.
      expect(tick.width, lessThan(4));
    }
  });

  testWidgets('een hogere norm schuift het streepje naar rechts', (
    tester,
  ) async {
    await tester.pumpWidget(_host(spec));
    await tester.pump();
    final ticks = targetTicks(tester)..sort((a, b) => a.top.compareTo(b.top));

    // Rij 1 en 2 hebben norm 90, rij 3 norm 80 — op dezelfde as, dus rij 3
    // hoort links van de andere twee te staan.
    expect(ticks[0].left, closeTo(ticks[1].left, 0.5));
    expect(ticks[2].left, lessThan(ticks[0].left - 1));
  });

  testWidgets('het streepje volgt de as, niet de rijhoogte', (tester) async {
    // Dezelfde grafiek met een vastgezette bovengrens: de as wordt ruimer, dus
    // elk streepje schuift naar links. Verandert er niets, dan hangt de positie
    // niet aan de waarde.
    await tester.pumpWidget(_host(spec));
    await tester.pump();
    final before = targetTicks(tester)..sort((a, b) => a.top.compareTo(b.top));

    await tester.pumpWidget(_host(spec.copyWith(maxBound: 200)));
    await tester.pump();
    final after = targetTicks(tester)..sort((a, b) => a.top.compareTo(b.top));

    expect(after[0].left, lessThan(before[0].left - 1));
  });

  testWidgets('zonder streefwaarden blijft er een gewone staaf over', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ChartSpec(
          type: ChartType.bullet,
          title: 'Zonder norm',
          x: ['A', 'B'],
          series: [
            ChartSeries(name: 'x', data: [10, 20]),
          ],
        ),
      ),
    );
    await tester.pump();

    // Een half ingevulde grafiek toont nog steeds iets zinnigs...
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    // ...maar geen streepje dat een norm suggereert die er niet is.
    expect(targetTicks(tester), isEmpty);
  });

  testWidgets('een grafiek zonder gegevens zegt dat, en tekent niets', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const ChartSpec(type: ChartType.bullet, title: 'Leeg', x: [])),
    );
    await tester.pump();

    expect(find.text('Geen grafiekgegevens'), findsOneWidget);
    expect(targetTicks(tester), isEmpty);
  });

  testWidgets('een volle lat past nog steeds op één slide', (tester) async {
    // Er staat nergens een maximum aantal rijen geschreven, dus toetsen we een
    // realistisch vol scherm: acht normen, elk met een streefwaarde. Bij dat
    // aantal moet élk label nog in beeld staan en mag er niets overlopen —
    // twee rijen bewijzen daar niets over.
    final many = ChartSpec(
      type: ChartType.bullet,
      title: 'Acht normen',
      x: [for (var i = 1; i <= 8; i++) 'Norm $i'],
      series: [
        ChartSeries(
          name: 'Gehaald',
          data: [for (var i = 1; i <= 8; i++) i * 10.0],
        ),
      ],
      targets: [for (var i = 1; i <= 8; i++) 75],
      bands: const [40, 70],
    );

    await tester.pumpWidget(_host(many));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final label in many.x) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(targetTicks(tester).length, 8);
  });
}
