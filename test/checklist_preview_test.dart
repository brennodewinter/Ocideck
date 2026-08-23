import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/checklist_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide) {
  return MaterialApp(
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
}

Slide _checklist() {
  const spec = ChecklistSpec(
    standardLabel: 'Checklist — OWASP WSTG',
    rows: [
      ChecklistRow(
        id: 'WSTG-ATHN-07',
        test: 'Testing for Weak Password Policy',
        status: ChecklistStatus.anomaly,
        findingId: 'F-03',
      ),
      ChecklistRow(id: 'WSTG-SESS-01', test: 'Session management'),
    ],
  );
  return Slide.create(
    SlideType.checklist,
  ).copyWith(title: spec.standardLabel, tableRows: spec.toTableRows());
}

void main() {
  testWidgets('checklist renders its rows, finding link and standard label', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_checklist()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('OWASP WSTG'), findsOneWidget);
    expect(find.text('WSTG-ATHN-07'), findsOneWidget);
    expect(find.text('F-03'), findsOneWidget); // finding link
    // The progress bar is present (derived tested/total).
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('checklist shows its linked scope object (feedback #8)', (
    tester,
  ) async {
    final slide = _checklist().copyWith(
      checklistScope: 'https://app.example/login',
    );
    await tester.pumpWidget(_host(slide));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('https://app.example/login'), findsOneWidget);
  });

  testWidgets('checklist without a scope object shows no scope line', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_checklist()));
    await tester.pump();

    expect(find.textContaining('Scope-object:'), findsNothing);
  });
}
