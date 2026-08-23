import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/findings_summary_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
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

Slide _summary() {
  final spec = FindingsSummarySpec.fromSeverities('Bevindingen', const [
    Cvss4Severity.critical,
    Cvss4Severity.high,
    Cvss4Severity.high,
    Cvss4Severity.medium,
    Cvss4Severity.low,
    Cvss4Severity.none,
  ]);
  return Slide.create(
    SlideType.findingsSummary,
  ).copyWith(title: spec.title, tableRows: spec.toTableRows());
}

void main() {
  testWidgets('findingsSummary renders a severity bar chart and total', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_summary()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The chart is drawn with fl_chart (PENTEST_MIAUW §11).
    expect(find.byType(BarChart), findsOneWidget);
    // The derived total (6 findings) is shown; locale-independent number.
    expect(find.textContaining('6'), findsWidgets);
  });

  testWidgets('always names the retest-resolved total', (tester) async {
    final spec = FindingsSummarySpec.fromSeverities('Bevindingen', const [
      Cvss4Severity.high,
    ], resolved: 2);
    final slide = Slide.create(
      SlideType.findingsSummary,
    ).copyWith(title: spec.title, tableRows: spec.toTableRows());
    await tester.pumpWidget(_host(slide));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Opgelost na hertest: 2'), findsOneWidget);
  });

  testWidgets('findingsSummary with no findings still renders', (tester) async {
    final empty = Slide.create(SlideType.findingsSummary);
    await tester.pumpWidget(_host(empty));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsOneWidget);
  });
}
