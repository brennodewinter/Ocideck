import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/resizable_dialog_box.dart';

Widget _host() {
  AppLocalizations.setActiveLanguageCode('nl');
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: const Scaffold(body: DialogResizableDemo()),
  );
}

/// Minimal host: een ResizableDialogBox met een Column die de handle
/// rechtsonder toont, zoals de echte dialogen dat doen.
class DialogResizableDemo extends StatelessWidget {
  const DialogResizableDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ResizableDialogBox(
        initialWidth: 500,
        height: 300,
        builder: (context, handle) => Container(
          color: Colors.white,
          child: Column(
            children: [
              const Expanded(child: Text('inhoud')),
              Align(alignment: Alignment.centerRight, child: handle),
            ],
          ),
        ),
      ),
    );
  }
}

/// De SizedBox die ResizableDialogBox rendert — het directe kind van de
/// State. Er staan meerdere SizedBoxes in de boom (MaterialApp, Scaffold),
/// dus beperk tot de descendant van ResizableDialogBox.
SizedBox boxOf(WidgetTester tester) {
  return tester
      .widgetList<SizedBox>(
        find.descendant(
          of: find.byType(ResizableDialogBox),
          matching: find.byType(SizedBox),
        ),
      )
      .first;
}

void main() {
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('starts at the initial width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final box = boxOf(tester);
    expect(box.width, 500);
    expect(box.height, 300);
  });

  testWidgets('dragging the handle widens and narrows (#1217)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    SizedBox box() => boxOf(tester);
    expect(box().width, 500);

    // Naar rechts slepen verbreedt (touch-slop slokt een paar px op).
    await tester.drag(find.byIcon(Icons.drag_indicator), const Offset(80, 0));
    await tester.pump();
    final wider = box().width ?? 500;
    expect(wider, greaterThan(500.0));

    // Naar links slepen vernauwt weer.
    await tester.drag(find.byIcon(Icons.drag_indicator), const Offset(-40, 0));
    await tester.pump();
    expect(box().width ?? wider, lessThan(wider));
  });

  testWidgets('width clamps to minWidth and does not go negative (#1217)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // Ver naar links slepen mag niet onder minWidth (420) komen.
    await tester.drag(
      find.byIcon(Icons.drag_indicator),
      const Offset(-2000, 0),
    );
    await tester.pump();
    expect(boxOf(tester).width, 420);
  });

  testWidgets('width clamps to maxWidth when provided (#1217)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppLocalizations.setActiveLanguageCode('nl');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Center(
            child: ResizableDialogBox(
              initialWidth: 500,
              height: 300,
              maxWidth: 700,
              builder: (context, handle) => Container(
                color: Colors.white,
                child: Column(
                  children: [
                    const Expanded(child: Text('inhoud')),
                    Align(alignment: Alignment.centerRight, child: handle),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Ver naar rechts slepen mag niet over maxWidth (700) komen.
    await tester.drag(find.byIcon(Icons.drag_indicator), const Offset(2000, 0));
    await tester.pump();
    expect(boxOf(tester).width, 700);
  });

  testWidgets('handle carries a localized tooltip', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Breedte aanpassen'), findsOneWidget);
  });
}
