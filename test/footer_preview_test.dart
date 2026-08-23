import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide, ThemeProfile profile, {int? number, int? count}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: slide,
            themeProfile: profile,
            slideNumber: number,
            slideCount: count,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('footer renders text tokens and page numbers', (tester) async {
    const profile = ThemeProfile(
      footerText: 'Vertrouwelijk · {page}/{total}',
      footerShowPageNumbers: true,
    );
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.bullets).copyWith(title: 'T', bullets: ['a']),
        profile,
        number: 2,
        count: 5,
      ),
    );
    await tester.pump();

    expect(find.text('Vertrouwelijk · 2/5'), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget); // page-number block
  });

  testWidgets('footer can be hidden on an individual slide', (tester) async {
    const profile = ThemeProfile(
      footerText: 'Vertrouwelijk',
      footerShowPageNumbers: true,
    );
    await tester.pumpWidget(
      _host(
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'T', bullets: ['a'], showFooter: false),
        profile,
        number: 2,
        count: 5,
      ),
    );
    await tester.pump();

    expect(find.text('Vertrouwelijk'), findsNothing);
    expect(find.text('2 / 5'), findsNothing);
  });

  testWidgets('footer position can be left center or right', (tester) async {
    Future<double> footerLeft(String position) async {
      await tester.pumpWidget(
        _host(
          Slide.create(SlideType.bullets).copyWith(title: 'T', bullets: ['a']),
          ThemeProfile(footerText: 'Voettekst', footerPosition: position),
          number: 1,
          count: 3,
        ),
      );
      await tester.pump();
      return tester.getTopLeft(find.text('Voettekst')).dx;
    }

    final left = await footerLeft('left');
    final center = await footerLeft('center');
    final right = await footerLeft('right');

    expect(left, lessThan(center));
    expect(center, lessThan(right));
  });

  testWidgets('left footer aligns with the bullet content margin', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.bullets).copyWith(title: 'T', bullets: ['a']),
        const ThemeProfile(footerText: 'Voettekst', footerPosition: 'left'),
        number: 1,
        count: 3,
      ),
    );
    await tester.pump();

    // Bullets beginnen op w*0.07 (w=800 → 56px); de footer lijnt daarmee uit.
    final footerX = tester.getTopLeft(find.text('Voettekst')).dx;
    expect(footerX, closeTo(800 * 0.07, 2));
  });

  // #1330: het paginanummer belooft "(rechtsonder)" en moet daar ook staan,
  // ongeacht de footerpositie. Vroeger reed het mee met de gecentreerde footer
  // en belandde het in het midden.
  testWidgets('page number stays bottom-right when footer is centered', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.bullets).copyWith(title: 'T', bullets: ['a']),
        const ThemeProfile(
          footerText: 'www.chateau-it.nl',
          footerPosition: 'center',
          footerShowPageNumbers: true,
        ),
        number: 2,
        count: 5,
      ),
    );
    await tester.pump();

    // Het paginanummer plakt tegen de rechterrand (w=800, rechtermarge w*0.04).
    final pageRight = tester.getTopRight(find.text('2 / 5')).dx;
    expect(pageRight, closeTo(800 - 800 * 0.04, 3));

    // En het staat rechts van de gecentreerde footertekst, niet ernaast in het
    // midden — dat was de bug.
    final footerCenter = tester.getCenter(find.text('www.chateau-it.nl')).dx;
    final pageCenter = tester.getCenter(find.text('2 / 5')).dx;
    expect(footerCenter, lessThan(400));
    expect(pageCenter, greaterThan(footerCenter + 150));
  });

  testWidgets('page number is bottom-right even with a left footer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.bullets).copyWith(title: 'T', bullets: ['a']),
        const ThemeProfile(
          footerText: 'Voettekst',
          footerPosition: 'left',
          footerShowPageNumbers: true,
        ),
        number: 3,
        count: 9,
      ),
    );
    await tester.pump();

    final pageRight = tester.getTopRight(find.text('3 / 9')).dx;
    expect(pageRight, closeTo(800 - 800 * 0.04, 3));
    // Footertekst links, paginanummer rechts: duidelijk gescheiden.
    final footerLeft = tester.getTopLeft(find.text('Voettekst')).dx;
    expect(footerLeft, lessThan(200));
  });

  testWidgets('page number renders bottom-right with no footer text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.bullets).copyWith(title: 'T', bullets: ['a']),
        const ThemeProfile(footerShowPageNumbers: true),
        number: 4,
        count: 7,
      ),
    );
    await tester.pump();

    expect(find.text('4 / 7'), findsOneWidget);
    final pageRight = tester.getTopRight(find.text('4 / 7')).dx;
    expect(pageRight, closeTo(800 - 800 * 0.04, 3));
  });

  testWidgets('footer is hidden on title slides', (tester) async {
    const profile = ThemeProfile(
      footerText: 'Altijd zichtbaar',
      footerShowPageNumbers: true,
    );
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.title).copyWith(title: 'Welkom'),
        profile,
        number: 1,
        count: 4,
      ),
    );
    await tester.pump();

    expect(find.text('Altijd zichtbaar'), findsNothing);
  });

  testWidgets('no footer when profile has none configured', (tester) async {
    const profile = ThemeProfile();
    await tester.pumpWidget(
      _host(
        Slide.create(SlideType.bullets).copyWith(title: 'T', bullets: ['a']),
        profile,
        number: 1,
        count: 3,
      ),
    );
    await tester.pump();

    expect(find.text('1 / 3'), findsNothing);
  });
}
