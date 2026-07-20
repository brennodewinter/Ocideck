import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/actions_spec.dart';
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

Slide _actions(List<ActionItem> items, {String title = 'Wat we vragen'}) {
  final spec = ActionsSpec(title: title, items: items);
  return Slide.create(
    SlideType.actions,
  ).copyWith(title: spec.title, tableRows: spec.toTableRows());
}

/// A date comfortably in the past, so "overdue" holds whenever this test runs.
final _longPast = DateTime(2020, 1, 15);

/// A date comfortably in the future, for the same reason.
final _farFuture = DateTime(2099, 12, 31);

void main() {
  testWidgets('renders the title, the action, its owner and deadline', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _actions([
          ActionItem(
            action: 'Testomgeving uit de lucht halen',
            owner: 'Team Platform',
            due: _farFuture,
          ),
        ]),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Wat we vragen'), findsOneWidget);
    expect(find.text('Testomgeving uit de lucht halen'), findsOneWidget);
    expect(find.text('Team Platform'), findsOneWidget);
    // Dates read as the footer writes them, so the deck has one format.
    expect(find.text('31-12-2099'), findsOneWidget);
  });

  testWidgets('only an ask is labelled', (tester) async {
    await tester.pumpWidget(
      _host(
        _actions(const [
          ActionItem(action: 'Mededeling', kind: ActionKind.info),
          ActionItem(action: 'Keuze nodig', kind: ActionKind.decision),
          ActionItem(action: 'Loopt vast', kind: ActionKind.escalation),
        ]),
      ),
    );
    await tester.pump();

    // An "info" chip on every other row would spend ink saying nothing is
    // required of the reader.
    expect(find.text('Besluit gevraagd'), findsOneWidget);
    expect(find.text('Escalatie'), findsOneWidget);
    expect(find.text('Ter informatie'), findsNothing);
  });

  testWidgets('a passed deadline is marked late', (tester) async {
    await tester.pumpWidget(
      _host(_actions([ActionItem(action: 'Al lang open', due: _longPast)])),
    );
    await tester.pump();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    final date = tester.widget<Text>(find.text('15-01-2020'));
    expect(date.style?.color, AppTheme.danger700);
  });

  testWidgets('a finished action is not marked late, however late it was', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _actions([
          ActionItem(
            action: 'Was laat, is klaar',
            due: _longPast,
            status: ActionStatus.done,
          ),
        ]),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    final date = tester.widget<Text>(find.text('15-01-2020'));
    expect(date.style?.color, isNot(AppTheme.danger700));
    // Done stays on the slide — that it is done is the news — but struck
    // through so it stops competing for attention.
    final action = tester.widget<Text>(find.text('Was laat, is klaar'));
    expect(action.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('an action without a deadline says so and is not late', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_actions(const [ActionItem(action: 'Nog te plannen')])),
    );
    await tester.pump();

    expect(find.text('geen datum'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('a full slate of eight items still fits', (tester) async {
    await tester.pumpWidget(
      _host(
        _actions([
          for (var i = 0; i < actionsMaxItems; i++)
            ActionItem(
              action: 'Een actie met een tamelijk lange omschrijving $i',
              owner: 'Team Platform en Infrastructuur',
              due: _farFuture,
              kind: i.isEven ? ActionKind.decision : ActionKind.info,
            ),
        ]),
      ),
    );
    await tester.pump();

    // Eight is the documented maximum, so eight must render without overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty actions slide renders its title alone', (tester) async {
    await tester.pumpWidget(_host(_actions(const [])));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Wat we vragen'), findsOneWidget);
  });
}
