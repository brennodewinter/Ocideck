import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';

/// Coverage for the reusable editor building blocks in `_editor_field.dart`:
/// [EditorField], [EditorFieldList], [editorScrollList], [ImageZoomControl] and
/// [SectionLabel]. These are the shared widgets every slide editor composes, so
/// exercising them here lifts the whole editor family's coverage in one place.
const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
];

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: _delegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

// [EditorField] is a Riverpod ConsumerStatefulWidget, so it needs a scope.
Widget _scoped(Widget child) => ProviderScope(child: _app(child));

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('EditorField', () {
    testWidgets('renders label + hint and edits flow through the controller', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final emitted = <String>[];
      controller.addListener(() => emitted.add(controller.text));

      await tester.pumpWidget(
        _scoped(
          EditorField(
            label: 'Titel',
            controller: controller,
            hint: 'Slide titel',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Titel'), findsOneWidget);
      // Hint text renders inside the field while it is empty.
      expect(find.text('Slide titel'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Hallo wereld');
      await tester.pump();

      expect(controller.text, 'Hallo wereld');
      expect(emitted.last, 'Hallo wereld');
    });

    testWidgets('honours maxLines for a multi-line field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _scoped(
          EditorField(label: 'Notities', controller: controller, maxLines: 4),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, 4);
      expect(field.minLines, 1);
      // An empty hint stays empty rather than rendering the label as a hint.
      expect(find.text('Notities'), findsOneWidget);
    });
  });

  testWidgets('SectionLabel renders its localized caption', (tester) async {
    await tester.pumpWidget(_app(const SectionLabel('Bullets (links)')));
    await tester.pump();
    expect(find.text('Bullets (links)'), findsOneWidget);
  });

  group('editorScrollList', () {
    testWidgets('nested variant shrink-wraps and cannot scroll on its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          editorScrollList(
            nestedInScrollView: true,
            children: const [Text('Alpha'), Text('Bravo')],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.shrinkWrap, isTrue);
      expect(list.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets('standalone variant is a scrollable page list', (tester) async {
      await tester.pumpWidget(
        _app(
          editorScrollList(
            nestedInScrollView: false,
            children: const [Text('Solo')],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Solo'), findsOneWidget);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.shrinkWrap, isFalse);
      expect(list.physics, isA<AlwaysScrollableScrollPhysics>());
    });
  });

  group('EditorFieldList', () {
    testWidgets('lays out every child (nested, non-scrolling)', (tester) async {
      await tester.pumpWidget(
        _app(
          const EditorFieldList(
            nestedInScrollView: true,
            children: [Text('Een'), Text('Twee'), Text('Drie')],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Een'), findsOneWidget);
      expect(find.text('Twee'), findsOneWidget);
      expect(find.text('Drie'), findsOneWidget);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.shrinkWrap, isTrue);
    });
  });

  group('ImageZoomControl', () {
    testWidgets('panel-width mode shows a bare % and snaps slider input', (
      tester,
    ) async {
      var value = 40;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (_, setState) => ImageZoomControl(
              value: value,
              step: 5,
              minValue: 20,
              maxValue: 70,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      await tester.pump();

      // maxValue <= 100 → the label is just a percentage (panel-width mode).
      expect(find.text('40%'), findsWidgets);

      // Feed a value between two steps: it must snap to the nearest multiple.
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(63.0);
      await tester.pump();
      expect(value, 65);
    });

    testWidgets('reset control returns to 100% when zoomed', (tester) async {
      var value = 40;
      await tester.pumpWidget(
        _app(
          ImageZoomControl(
            value: value,
            step: 5,
            minValue: 20,
            maxValue: 70,
            onChanged: (v) => value = v,
          ),
        ),
      );
      await tester.pump();

      // Zoomed (effective != 100) → the refresh button is enabled.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(value, 100);
    });

    testWidgets('zoom-mode labels cover in / full / out', (tester) async {
      Widget zoom(int v) => _app(
        ImageZoomControl(
          value: v,
          onChanged: (_) {},
          step: 10,
          minValue: 20,
          maxValue: 300,
        ),
      );

      await tester.pumpWidget(zoom(150));
      await tester.pump();
      expect(find.textContaining('Ingezoomd'), findsOneWidget);
      expect(find.textContaining('van de foto zichtbaar'), findsOneWidget);

      await tester.pumpWidget(zoom(100));
      await tester.pump();
      expect(find.text('Volledig zichtbaar (100%)'), findsOneWidget);

      await tester.pumpWidget(zoom(80));
      await tester.pump();
      expect(find.text('Uitgezoomd 80%'), findsOneWidget);
    });
  });

  group('reportImageImportFailure', () {
    Future<BuildContext> pumpContext(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      return ctx;
    }

    testWidgets('every real failure surfaces a SnackBar', (tester) async {
      for (final failure in const [
        ImageImportFailure.rejected,
        ImageImportFailure.noClipboardImage,
        ImageImportFailure.writeFailed,
        ImageImportFailure.memoryBudgetExceeded,
      ]) {
        final ctx = await pumpContext(tester);
        reportImageImportFailure(ctx, failure);
        await tester.pump();
        expect(
          find.byType(SnackBar),
          findsOneWidget,
          reason: '$failure should toast',
        );
        // Tear the tree down so the SnackBar does not leak into the next case.
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('cancelled and null stay silent', (tester) async {
      final ctx = await pumpContext(tester);
      reportImageImportFailure(ctx, ImageImportFailure.cancelled);
      reportImageImportFailure(ctx, null);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
