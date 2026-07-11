import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/findings_summary_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/widgets/editors/findings_summary_editor.dart';

Widget _host({
  required Slide slide,
  required List<Cvss4Severity> deckFindingSeverities,
  required ValueChanged<Slide> onUpdate,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: FindingsSummaryEditor(
          slide: slide,
          onUpdate: onUpdate,
          deckFindingSeverities: deckFindingSeverities,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('"refresh from deck" fills the counts from the deck findings', (
    tester,
  ) async {
    Slide? emitted;
    final slide = Slide.create(SlideType.findingsSummary);
    await tester.pumpWidget(
      _host(
        slide: slide,
        deckFindingSeverities: const [
          Cvss4Severity.critical,
          Cvss4Severity.critical,
          Cvss4Severity.high,
          Cvss4Severity.none,
        ],
        onUpdate: (s) => emitted = s,
      ),
    );
    await tester.pump();

    // Locale-independent: tap the refresh button by its icon.
    await tester.tap(find.byIcon(Icons.autorenew));
    await tester.pump();

    expect(emitted, isNotNull);
    final spec = FindingsSummarySpec.fromSlide(
      emitted!.title,
      emitted!.tableRows,
    );
    expect(spec.countOf(Cvss4Severity.critical), 2);
    expect(spec.countOf(Cvss4Severity.high), 1);
    expect(spec.countOf(Cvss4Severity.medium), 0);
    expect(spec.countOf(Cvss4Severity.none), 1);
    expect(spec.total, 4);
  });
}
