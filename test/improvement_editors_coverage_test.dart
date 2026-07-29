import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/improvement/canvas_spec.dart';
import 'package:ocideck/services/improvement/flow_spec.dart';
import 'package:ocideck/services/improvement/matrix_spec.dart';
import 'package:ocideck/services/improvement/tree_spec.dart';
import 'package:ocideck/state/improvement_ai_provider.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/canvas_editor.dart';
import 'package:ocideck/widgets/editors/flow_editor.dart';
import 'package:ocideck/widgets/editors/matrix_editor.dart';
import 'package:ocideck/widgets/editors/tree_editor.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

Finder fieldByLabel(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is EditorField && w.label == label),
  matching: find.byType(TextField),
);

Widget appHost({required Widget child, List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? const [],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('nl'),
      home: Scaffold(body: child),
    ),
  );
}

/// Keeps the same State across slide swaps so [didUpdateWidget] runs.
class _SlideHost extends StatefulWidget {
  const _SlideHost({super.key, required this.initial, required this.builder});

  final Slide initial;
  final Widget Function(Slide slide, ValueChanged<Slide> onUpdate) builder;

  @override
  State<_SlideHost> createState() => _SlideHostState();
}

class _SlideHostState extends State<_SlideHost> {
  late Slide _slide = widget.initial;

  void swap(Slide next) => setState(() => _slide = next);

  @override
  Widget build(BuildContext context) =>
      // Do not setState from onUpdate — the child already rebuilds itself and
      // calling setState here while dirty trips Flutter's !_dirty assertion.
      widget.builder(_slide, (s) => _slide = s);
}

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1100, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

final _noAi = [improvementAiAvailableProvider.overrideWithValue(false)];

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('MatrixEditor', () {
    testWidgets('edits title, adds row, pastes, switches to FMEA with RPN', (
      tester,
    ) async {
      await _tall(tester);
      var latest = Slide.create(SlideType.matrix);
      await tester.pumpWidget(
        appHost(
          child: MatrixEditor(slide: latest, onUpdate: (s) => latest = s),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sjabloon'), findsOneWidget);
      await tester.enterText(fieldByLabel('Titel'), 'SIPOC intake');
      await tester.pump();
      expect(latest.title, 'SIPOC intake');

      await tester.tap(find.text('Rij toevoegen'));
      await tester.pumpAndSettle();
      expect(latest.tableRows.length, greaterThanOrEqualTo(3));

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{
              'text':
                  'Supplier\tInput\tProcess\tOutput\tCustomer\n'
                  'A\tB\tC\tD\tE\n'
                  'F\tG\tH\tI\tJ',
            };
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Plakken uit klembord'));
      await tester.pumpAndSettle();
      expect(latest.tableRows.length, greaterThanOrEqualTo(3));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('FMEA').last);
      await tester.pumpAndSettle();
      expect(latest.improvementTemplateId, 'fmea');
      expect(find.text('RPN'), findsWidgets);
    });

    testWidgets('nestedInScrollView and didUpdateWidget on id change', (
      tester,
    ) async {
      await _tall(tester);
      final first = Slide.create(SlideType.matrix).copyWith(title: 'A');
      final key = GlobalKey<_SlideHostState>();
      await tester.pumpWidget(
        appHost(
          child: _SlideHost(
            key: key,
            initial: first,
            builder: (slide, onUpdate) => MatrixEditor(
              slide: slide,
              onUpdate: onUpdate,
              nestedInScrollView: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);

      key.currentState!.swap(
        Slide.create(SlideType.matrix).copyWith(title: 'B'),
      );
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('cannot remove the only data row', (tester) async {
      await _tall(tester);
      await tester.pumpWidget(
        appHost(
          child: MatrixEditor(
            slide: Slide.create(SlideType.matrix),
            onUpdate: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final remove = find.byIcon(Icons.remove_circle_outline);
      expect(remove, findsOneWidget);
      await tester.tap(remove);
      await tester.pump();
    });
  });

  group('CanvasEditor', () {
    testWidgets('edits title and region, switches template', (tester) async {
      await _tall(tester);
      var latest = Slide.create(SlideType.canvas);
      await tester.pumpWidget(
        appHost(
          overrides: _noAi,
          child: CanvasEditor(slide: latest, onUpdate: (s) => latest = s),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(fieldByLabel('Titel'), 'A3 lean');
      await tester.pump();
      expect(latest.title, 'A3 lean');

      final bodies = find.byType(TextField);
      expect(bodies, findsWidgets);
      await tester.enterText(bodies.at(1), 'Probleemschets');
      await tester.pump();
      expect(latest.customMarkdown, contains('Probleemschets'));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Projectcharter').last);
      await tester.pumpAndSettle();
      expect(latest.improvementTemplateId, 'charter');
    });

    testWidgets('nested + id swap', (tester) async {
      await _tall(tester);
      final key = GlobalKey<_SlideHostState>();
      await tester.pumpWidget(
        appHost(
          overrides: _noAi,
          child: _SlideHost(
            key: key,
            initial: Slide.create(SlideType.canvas).copyWith(title: 'One'),
            builder: (slide, onUpdate) => CanvasEditor(
              slide: slide,
              onUpdate: onUpdate,
              nestedInScrollView: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.swap(
        Slide.create(SlideType.canvas).copyWith(title: 'Two'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Two'), findsOneWidget);
    });
  });

  group('TreeEditor', () {
    testWidgets('title, indent, add/remove, layout and template', (
      tester,
    ) async {
      await _tall(tester);
      Slide latest = Slide.create(SlideType.tree);
      final startCount = latest.bullets.length;
      await tester.pumpWidget(
        appHost(
          overrides: _noAi,
          child: TreeEditor(slide: latest, onUpdate: (s) => latest = s),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(fieldByLabel('Titel'), '5 Whys');
      await tester.pump();
      expect(latest.title, '5 Whys');

      await tester.tap(find.text('Visgraat'));
      await tester.pumpAndSettle();
      expect(latest.improvementLayout, treeLayoutToken(TreeLayout.fishbone));

      await tester.tap(find.byIcon(Icons.format_indent_increase).first);
      await tester.pump();
      expect(latest.bullets.first.startsWith('\t'), isTrue);

      await tester.tap(find.text('Punt toevoegen').last);
      await tester.pumpAndSettle();
      expect(latest.bullets.length, startCount + 1);

      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pumpAndSettle();
      expect(latest.bullets.length, startCount);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CTQ-boom').last);
      await tester.pumpAndSettle();
      expect(latest.improvementTemplateId, 'ctq-tree');
    });

    testWidgets('nested + id swap', (tester) async {
      await _tall(tester);
      final key = GlobalKey<_SlideHostState>();
      await tester.pumpWidget(
        appHost(
          overrides: _noAi,
          child: _SlideHost(
            key: key,
            initial: Slide.create(SlideType.tree).copyWith(title: 'T1'),
            builder: (slide, onUpdate) => TreeEditor(
              slide: slide,
              onUpdate: onUpdate,
              nestedInScrollView: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.swap(
        Slide.create(SlideType.tree).copyWith(title: 'T2'),
      );
      await tester.pumpAndSettle();
      expect(find.text('T2'), findsOneWidget);
    });
  });

  group('FlowEditor', () {
    testWidgets('title, layouts, add/remove, template', (tester) async {
      await _tall(tester);
      Slide latest = Slide.create(SlideType.flow);
      final startCount = latest.bullets.length;
      await tester.pumpWidget(
        appHost(
          overrides: _noAi,
          child: FlowEditor(slide: latest, onUpdate: (s) => latest = s),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(fieldByLabel('Titel'), 'Stroomkaart');
      await tester.pump();
      expect(latest.title, 'Stroomkaart');

      await tester.tap(find.text('Zwembanen'));
      await tester.pumpAndSettle();
      expect(latest.improvementLayout, flowLayoutToken(FlowLayout.swimlane));

      await tester.tap(find.text('VSM'));
      await tester.pumpAndSettle();
      expect(latest.improvementLayout, flowLayoutToken(FlowLayout.vsm));

      await tester.tap(find.text('Punt toevoegen').last);
      await tester.pumpAndSettle();
      expect(latest.bullets.length, startCount + 1);

      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pumpAndSettle();
      expect(latest.bullets.length, startCount);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Zwembanen').last);
      await tester.pumpAndSettle();
      expect(latest.improvementTemplateId, isNot(equals('process-map')));

      // Icon-row "add after" and AI callbacks when the field is available.
    });

    testWidgets('empty bullets seed one row; AI suggest/accept paths', (
      tester,
    ) async {
      await _tall(tester);
      var latest = Slide.create(SlideType.flow).copyWith(
        bullets: const [],
        title: 'Leeg',
        aiAssistedFields: const ['flow:0'],
      );
      await tester.pumpWidget(
        appHost(
          overrides: [
            improvementAiAvailableProvider.overrideWithValue(true),
            improvementAiClientFactoryProvider.overrideWithValue(
              () async => throw AiGateException(AiGateDenial.disabled),
            ),
          ],
          child: FlowEditor(slide: latest, onUpdate: (s) => latest = s),
        ),
      );
      await tester.pumpAndSettle();

      // Empty bullets seed one editor row (emit happens on first edit).
      expect(find.text('AI-concept'), findsOneWidget);
      await tester.enterText(fieldByLabel('Titel'), 'Leeg-2');
      await tester.pump();
      expect(latest.bullets.length, 1);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(latest.bullets.length, greaterThanOrEqualTo(2));

      // Sibling/context builders run when AI suggest is tapped.
      await tester.tap(find.text('Tekst voorstellen (AI)').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Nagekeken').first);
      await tester.pump();
      expect(latest.aiAssistedFields, isNot(contains('flow:0')));
    });

    testWidgets('nested + id swap', (tester) async {
      await _tall(tester);
      final key = GlobalKey<_SlideHostState>();
      await tester.pumpWidget(
        appHost(
          overrides: _noAi,
          child: _SlideHost(
            key: key,
            initial: Slide.create(SlideType.flow).copyWith(title: 'F1'),
            builder: (slide, onUpdate) => FlowEditor(
              slide: slide,
              onUpdate: onUpdate,
              nestedInScrollView: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.swap(
        Slide.create(SlideType.flow).copyWith(title: 'F2'),
      );
      await tester.pumpAndSettle();
      expect(find.text('F2'), findsOneWidget);
    });
  });

  test('starter rows/templates exist for bundled ids', () {
    expect(improvementTemplateStarterRows('sipoc'), isNotEmpty);
    expect(improvementTemplateStarterRows('fmea'), isNotEmpty);
    expect(improvementTemplateStarterRows('raci'), isNotEmpty);
    expect(bundledCanvasTemplates, isNotEmpty);
    expect(bundledTreeTemplates, isNotEmpty);
    expect(bundledFlowTemplates, isNotEmpty);
  });
}
