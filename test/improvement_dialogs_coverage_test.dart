import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/improvement_inference_dialog.dart';
import 'package:ocideck/widgets/dialogs/improvement_msa_dialog.dart';
import 'package:ocideck/widgets/dialogs/improvement_regression_dialog.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Widget appHost(Widget home) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('nl'),
    home: home,
  );

  Future<void> wideSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  group('ImprovementMsaDialog', () {
    const balanced = '''
Part\tOperator\tValue
P1\tA\t1
P1\tA\t2
P1\tB\t3
P1\tB\t4
P2\tA\t5
P2\tA\t6
P2\tB\t7
P2\tB\t8
''';

    testWidgets('Berekenen shows % study variation for a balanced table', (
      tester,
    ) async {
      await wideSurface(tester);
      await tester.pumpWidget(
        appHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  ImprovementMsaDialog.show(context, initialTable: balanced),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Gage R&R (ANOVA)'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Tolerantie (optioneel)'),
        '20',
      );
      await tester.tap(find.text('Berekenen'));
      await tester.pumpAndSettle();

      expect(find.textContaining('% study variation'), findsOneWidget);
      expect(find.textContaining('ndc'), findsOneWidget);

      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(find.text('Gage R&R (ANOVA)'), findsNothing);
    });

    testWidgets('shows refusal for unreadable paste', (tester) async {
      await wideSurface(tester);
      await tester.pumpWidget(
        appHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ImprovementMsaDialog.show(
                context,
                initialTable: 'not a table',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Berekenen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('StatsRefusal'), findsOneWidget);
    });

    testWidgets('show with initialMeasurements pre-fills the table', (
      tester,
    ) async {
      await wideSurface(tester);
      await tester.pumpWidget(
        appHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ImprovementMsaDialog.show(
                context,
                initialMeasurements: const [
                  [
                    [1.0, 2.0],
                    [3.0, 4.0],
                  ],
                  [
                    [5.0, 6.0],
                    [7.0, 8.0],
                  ],
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('P1'), findsWidgets);
      await tester.tap(find.text('Berekenen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('% study variation'), findsOneWidget);
    });
  });

  group('ImprovementInferenceDialog', () {
    testWidgets('one-sample t runs on pasted column', (tester) async {
      await wideSurface(tester);
      await tester.pumpWidget(
        appHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ImprovementInferenceDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '1\n2\n3\n4\n5');
      await tester.tap(find.text('Berekenen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('StatsRefusal'), findsNothing);
      // Result body should appear (t statistic / p-value wording varies).
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('refuses too little data', (tester) async {
      await wideSurface(tester);
      await tester.pumpWidget(
        appHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ImprovementInferenceDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5');
      await tester.tap(find.text('Berekenen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('StatsRefusal'), findsOneWidget);
    });
  });

  group('ImprovementRegressionDialog', () {
    testWidgets('shows slope for aligned X/Y columns', (tester) async {
      await wideSurface(tester);
      await tester.pumpWidget(
        appHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ImprovementRegressionDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '1\n2\n3\n4');
      await tester.enterText(fields.at(1), '2\n4\n6\n8');
      await tester.tap(find.text('Berekenen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('StatsRefusal'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('refuses mismatched lengths', (tester) async {
      await wideSurface(tester);
      await tester.pumpWidget(
        appHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ImprovementRegressionDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '1\n2');
      await tester.enterText(fields.at(1), '2');
      await tester.tap(find.text('Berekenen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('StatsRefusal'), findsOneWidget);
    });
  });
}
