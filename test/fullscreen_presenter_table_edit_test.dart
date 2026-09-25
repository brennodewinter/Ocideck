import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

void main() {
  Slide editableTable() => Slide.create(SlideType.table).copyWith(
    title: 'Cijfers',
    tableEditable: true,
    tableRows: [
      ['Kolom', 'Waarde'],
      ['Omzet', '100'],
    ],
  );

  Future<void> openTable(
    WidgetTester tester, {
    List<Slide>? slides,
    ValueChanged<Slide>? onSessionEdit,
    AudienceWindowHandle? audience,
    bool activate = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenPresenter(
          slides: slides ?? [editableTable()],
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
          onSessionEdit: onSessionEdit,
          audience: audience,
        ),
      ),
    );
    await tester.pump();
    if (activate) {
      await tester.tap(find.byTooltip('Tabel bewerken (E)'));
      await tester.pump();
      await tester.pump();
    }
  }

  TextEditingController controllerWith(WidgetTester tester, String text) =>
      tester
          .widget<TextField>(find.widgetWithText(TextField, text))
          .controller!;

  bool hasPrimaryFocus(WidgetTester tester, String text) => tester
      .widget<TextField>(find.widgetWithText(TextField, text))
      .focusNode!
      .hasPrimaryFocus;

  TextEditingController focusedController(WidgetTester tester) => tester
      .widgetList<TextField>(find.byType(TextField))
      .singleWhere((field) => field.focusNode!.hasPrimaryFocus)
      .controller!;

  testWidgets('activeren focust de eerste cel en selecteert haar inhoud', (
    tester,
  ) async {
    await openTable(tester);

    final controller = controllerWith(tester, 'Kolom');
    expect(hasPrimaryFocus(tester, 'Kolom'), isTrue);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
      reason: 'doortypen na activeren hoort de geselecteerde cel te vervangen',
    );
  });

  testWidgets('een begrensde projectietabel blijft veilig alleen-lezen', (
    tester,
  ) async {
    final edits = <Slide>[];
    final slide = editableTable().copyWith(
      tableRows: [
        ['Kolom', 'Waarde'],
        ['Zichtbaar', '1'],
        ['Verborgen', '2'],
      ],
      viewLimit: const DisplayWindowSpec(limit: 1),
    );
    await openTable(
      tester,
      slides: [slide],
      onSessionEdit: edits.add,
      activate: false,
    );

    expect(find.byTooltip('Tabel bewerken (E)'), findsNothing);
    expect(find.text('Zichtbaar'), findsOneWidget);
    expect(find.text('Verborgen'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(edits, isEmpty);
  });

  testWidgets('typen midden in een cel bewaart cursor en focus', (
    tester,
  ) async {
    Slide? updated;
    await openTable(tester, onSessionEdit: (slide) => updated = slide);
    await tester.tap(find.widgetWithText(TextField, 'Omzet'));
    await tester.pump();

    final before = controllerWith(tester, 'Omzet');
    before.selection = const TextSelection.collapsed(offset: 2);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'OmXzet',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    final after = controllerWith(tester, 'OmXzet');
    expect(after.selection, const TextSelection.collapsed(offset: 3));
    expect(hasPrimaryFocus(tester, 'OmXzet'), isTrue);
    expect(updated?.tableRows[1][0], 'OmXzet');
  });

  testWidgets('Tab en Shift+Tab lopen voor- en achteruit door de cellen', (
    tester,
  ) async {
    await openTable(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(hasPrimaryFocus(tester, 'Waarde'), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump();
    expect(hasPrimaryFocus(tester, 'Kolom'), isTrue);
  });

  testWidgets('Tab op de laatste cel voegt een rij toe en focust haar begin', (
    tester,
  ) async {
    Slide? updated;
    await openTable(tester, onSessionEdit: (slide) => updated = slide);
    await tester.tap(find.widgetWithText(TextField, '100'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();

    expect(updated?.tableRows, [
      ['Kolom', 'Waarde'],
      ['Omzet', '100'],
      ['', ''],
    ]);
    final emptyFields = find.widgetWithText(TextField, '');
    expect(
      tester
          .widgetList<TextField>(emptyFields)
          .any((field) => field.focusNode!.hasPrimaryFocus),
      isTrue,
    );
  });

  testWidgets('Enter gaat naar dezelfde kolom in de volgende rij', (
    tester,
  ) async {
    await openTable(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(focusedController(tester).text, '100');
  });

  testWidgets('Shift+Enter voegt een regeleinde toe in dezelfde cel', (
    tester,
  ) async {
    Slide? updated;
    await openTable(tester, onSessionEdit: (slide) => updated = slide);
    await tester.tap(find.widgetWithText(TextField, '100'));
    await tester.pump();

    final value = controllerWith(tester, '100');
    value.selection = const TextSelection.collapsed(offset: 3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(focusedController(tester).text, '100\n');
    expect(
      focusedController(tester).selection,
      const TextSelection.collapsed(offset: 4),
    );
    expect(updated?.tableRows[1][1], '100\n');
  });

  testWidgets('een geplakt raster vult cellen en laat de tabel meegroeien', (
    tester,
  ) async {
    Slide? updated;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': 'Naam\tScore\nJan\t8\nPiet\t9\n'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openTable(tester, onSessionEdit: (slide) => updated = slide);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    expect(updated?.tableRows, [
      ['Naam', 'Score'],
      ['Jan', '8'],
      ['Piet', '9'],
    ]);
  });

  testWidgets(
    'elke live wijziging bewaart de sessie en synchroniseert publiek',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
      final tableUpdates = <Map<String, dynamic>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
        call,
      ) async {
        if (call.method != 'invokeMethod') return null;
        final envelope = Map<String, dynamic>.from(call.arguments as Map);
        if (envelope['method'] != 'tableUpdate') return null;
        tableUpdates.add(
          Map<String, dynamic>.from(envelope['arguments'] as Map),
        );
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          bridge,
          null,
        ),
      );

      final sessionEdits = <Slide>[];
      await openTable(
        tester,
        onSessionEdit: sessionEdits.add,
        audience: AudienceWindowHandle(
          WindowController.fromWindowId('test'),
          closeImpl: (_) async {},
        ),
      );
      await tester.tap(find.widgetWithText(TextField, '100'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '100'), '250');
      await tester.pump();

      expect(sessionEdits.last.tableRows[1][1], '250');
      expect(tableUpdates.last['slideIndex'], 0);
      expect(tableUpdates.last['tableRows'], sessionEdits.last.tableRows);

      await tester.pumpWidget(const SizedBox());
    },
  );
}
