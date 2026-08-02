import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/improvement_y01.dart';
import 'package:ocideck/widgets/dialogs/improvement_project_setup_dialog.dart';

class _Harness extends StatefulWidget {
  const _Harness({
    this.languageCode,
    this.brightness = Brightness.light,
    this.textScaler = TextScaler.noScaling,
  });

  final String? languageCode;
  final Brightness brightness;
  final TextScaler textScaler;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  ImprovementY01Metric? result;
  bool completed = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: widget.languageCode == null ? null : Locale(widget.languageCode!),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    themeMode: widget.brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: widget.textScaler),
      child: child!,
    ),
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await ImprovementProjectSetupDialog.show(context);
          completed = true;
        },
        child: const Text('open'),
      ),
    ),
  );
}

Future<_HarnessState> _open(
  WidgetTester tester, {
  String? languageCode,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    _Harness(
      languageCode: languageCode,
      brightness: brightness,
      textScaler: textScaler,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester.state<_HarnessState>(find.byType(_Harness));
}

void main() {
  testWidgets('returns Y-01 and all entered optional values', (tester) async {
    final harness = await _open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('improvementY01Name')),
      'Doorlooptijd orderintake',
    );
    await tester.tap(find.text('Nog geen specificatielimiet'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'USL (bovengrens)'),
      '12,5',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'LSL (ondergrens)'),
      '7.5',
    );
    await tester.tap(find.text('Optionele Y-01-velden'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Eenheid'), 'dagen');
    await tester.enterText(
      find.widgetWithText(TextField, 'Procesdoel (target)'),
      '9',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Baseline'), '14');
    await tester.enterText(find.widgetWithText(TextField, 'Doel'), '8');
    await tester.tap(find.byKey(const ValueKey('improvementProjectStart')));
    await tester.pumpAndSettle();

    expect(harness.completed, isTrue);
    expect(harness.result, isNotNull);
    expect(harness.result!.name, 'Doorlooptijd orderintake');
    expect(harness.result!.unit, 'dagen');
    expect(harness.result!.usl, 12.5);
    expect(harness.result!.lsl, 7.5);
    expect(harness.result!.target, 9);
    expect(harness.result!.baseline, 14);
    expect(harness.result!.goal, 8);
  });

  testWidgets('cancel returns null', (tester) async {
    final harness = await _open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('improvementY01Name')),
      'Deze waarde mag niet terugkomen',
    );
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(harness.completed, isTrue);
    expect(harness.result, isNull);
    expect(find.text('Primaire Y-metriek (Y-01)'), findsNothing);
  });

  testWidgets('stays operable in German at 200% in light and dark', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final harness = await _open(
        tester,
        languageCode: 'de',
        brightness: brightness,
        textScaler: TextScaler.linear(2),
      );
      await tester.enterText(
        find.byKey(const ValueKey('improvementY01Name')),
        'Durchlaufzeit',
      );
      expect(tester.takeException(), isNull, reason: brightness.name);

      await tester.tap(find.byKey(const ValueKey('improvementProjectStart')));
      await tester.pumpAndSettle();
      expect(harness.completed, isTrue, reason: brightness.name);
      expect(harness.result!.name, 'Durchlaufzeit', reason: brightness.name);
      expect(tester.takeException(), isNull, reason: brightness.name);
    }
  });
}
