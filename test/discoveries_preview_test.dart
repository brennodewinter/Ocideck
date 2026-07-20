import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/discoveries_spec.dart';
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

Slide _discoveries(
  List<Discovery> discoveries, {
  String title = 'Wat we niet wisten te hebben',
}) {
  final spec = DiscoveriesSpec(title: title, discoveries: discoveries);
  return Slide.create(
    SlideType.discoveries,
  ).copyWith(title: spec.title, tableRows: spec.toTableRows());
}

/// The colour a piece of text is drawn in. The headline restates the worst
/// row's figure, so the same string can legitimately appear twice; both are
/// drawn the same and the first will do.
Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).first).style?.color;

/// The rendered width of the exposure bar in row [index].
double _barWidth(WidgetTester tester, int index) =>
    tester.getSize(find.byKey(ValueKey('discoveries-bar-$index'))).width;

void main() {
  testWidgets('renders the title, each find, its kind and its owner', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _discoveries(const [
          Discovery(
            name: 'betaalportaal-acc.example.nl',
            kind: 'Webapplicatie',
            daysUnnoticed: 412,
            owner: 'Team Betalen',
          ),
        ]),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Wat we niet wisten te hebben'), findsOneWidget);
    expect(find.text('betaalportaal-acc.example.nl'), findsOneWidget);
    expect(find.text('Webapplicatie'), findsOneWidget);
    expect(find.text('Team Betalen'), findsOneWidget);
  });

  testWidgets('the slide leads with the longest exposure, not with the count', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _discoveries(const [
          Discovery(name: 'a', daysUnnoticed: 12),
          Discovery(name: 'b', daysUnnoticed: 412),
        ]),
      ),
    );
    await tester.pump();

    // 412 days restated as months, drawn in the alarm colour.
    expect(find.text('14 maanden'), findsWidgets);
    expect(_colorOf(tester, '14 maanden'), AppTheme.danger700);
  });

  testWidgets('a short exposure keeps its days', (tester) async {
    await tester.pumpWidget(
      _host(_discoveries(const [Discovery(name: 'a', daysUnnoticed: 9)])),
    );
    await tester.pump();

    expect(find.text('9 dagen'), findsWidgets);
    expect(find.textContaining('maand'), findsNothing);
  });

  testWidgets('one day and one month are singular', (tester) async {
    await tester.pumpWidget(
      _host(_discoveries(const [Discovery(name: 'a', daysUnnoticed: 1)])),
    );
    await tester.pump();

    expect(find.text('1 dag'), findsWidgets);
    expect(find.text('1 dagen'), findsNothing);
  });

  testWidgets('without any exposure figure the slide makes no headline', (
    tester,
  ) async {
    // A first scan has no history to measure against and must not imply one.
    await tester.pumpWidget(
      _host(
        _discoveries(const [
          Discovery(name: 'a', kind: 'Webapplicatie', owner: 'Team A'),
        ]),
      ),
    );
    await tester.pump();

    expect(find.text('a'), findsOneWidget);
    expect(find.textContaining('langst'), findsNothing);
    // And the row says so rather than showing a nought.
    expect(find.text('onbekend'), findsOneWidget);
    expect(find.text('0 dagen'), findsNothing);
  });

  testWidgets('an unowned find is named in red, an owned one is not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _discoveries(const [
          Discovery(name: 'a', daysUnnoticed: 10, owner: 'Team A'),
          Discovery(name: 'b', daysUnnoticed: 10),
        ]),
      ),
    );
    await tester.pump();

    expect(_colorOf(tester, 'geen eigenaar'), AppTheme.danger700);
    expect(_colorOf(tester, 'Team A'), isNot(AppTheme.danger700));
  });

  testWidgets('bars share one scale across the rows', (tester) async {
    // Per-row scaling would draw ten days the width of four hundred and the
    // picture would contradict the figures.
    await tester.pumpWidget(
      _host(
        _discoveries(const [
          Discovery(name: 'lang', daysUnnoticed: 400),
          Discovery(name: 'kort', daysUnnoticed: 100),
        ]),
      ),
    );
    await tester.pump();

    // 400 against 100 on a shared scale: four times the width, near enough.
    expect(_barWidth(tester, 0), closeTo(_barWidth(tester, 1) * 4, 1));
  });

  testWidgets('six finds with long names still fit', (tester) async {
    // Six is the documented maximum, so six must fit — with hostnames of real
    // length, a kind under each and an owner beside it.
    await tester.pumpWidget(
      _host(
        _discoveries(const [
          Discovery(
            name: 'betaalportaal-acceptatie.example.nl',
            kind: 'Webapplicatie',
            daysUnnoticed: 412,
            owner: 'Team Betalen',
          ),
          Discovery(
            name: 'oud-intranet.example.nl',
            kind: 'Webapplicatie',
            daysUnnoticed: 280,
          ),
          Discovery(
            name: 'mail-relay-03.example.nl',
            kind: 'Mailserver',
            daysUnnoticed: 190,
            owner: 'Infrastructuur',
          ),
          Discovery(
            name: 'wildcard *.test.example.nl',
            kind: 'Certificaat',
            daysUnnoticed: 96,
          ),
          Discovery(
            name: 'api-gateway-staging.example.nl',
            kind: 'API',
            daysUnnoticed: 41,
            owner: 'Team Platform',
          ),
          Discovery(
            name: 'files.example.nl',
            kind: 'Bestandsdeling',
            owner: 'Onbekend team',
          ),
        ]),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('betaalportaal-acceptatie.example.nl'), findsOneWidget);
    expect(find.text('files.example.nl'), findsOneWidget);
  });

  testWidgets('the footer counts the finds and the ownerless ones', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _discoveries(const [
          Discovery(name: 'a', daysUnnoticed: 10, owner: 'Team A'),
          Discovery(name: 'b', daysUnnoticed: 10),
          Discovery(name: 'c', daysUnnoticed: 10),
        ]),
      ),
    );
    await tester.pump();

    expect(find.text('3 ontdekkingen  ·  2 geen eigenaar'), findsOneWidget);
  });

  testWidgets('with every find owned the footer leaves the tally out', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _discoveries(const [
          Discovery(name: 'a', daysUnnoticed: 10, owner: 'Team A'),
        ]),
      ),
    );
    await tester.pump();

    // "0 geen eigenaar" is noise; the good news is that the phrase is absent.
    expect(find.text('1 ontdekking'), findsOneWidget);
    expect(find.textContaining('geen eigenaar'), findsNothing);
  });

  testWidgets('an empty slide renders without a row', (tester) async {
    await tester.pumpWidget(_host(_discoveries(const [])));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Wat we niet wisten te hebben'), findsOneWidget);
  });
}
