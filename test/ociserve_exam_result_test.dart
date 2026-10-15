import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_exam_result.dart';
import 'package:ocideck/widgets/dialogs/ociserve_exam_results.dart';

Map<String, Object?> _released({Map<String, Object?> extra = const {}}) => {
  'attempt_id': 'a1',
  'exam_session_id': 's1',
  'title': 'Theorie',
  'status': 'released',
  'released_at': '2026-09-12T11:00:00Z',
  'total_items': 10,
  'correct_items': 7,
  'percentage': 70,
  'passed': true,
  ...extra,
};

void main() {
  group('OciServeExamResult.fromJson', () {
    test('leest een vrijgegeven uitslag met het oordeel van de server', () {
      final result = OciServeExamResult.fromJson(_released());

      expect(result.released, isTrue);
      expect(result.correctItems, 7);
      expect(result.totalItems, 10);
      expect(result.percentage, 70.0);
      expect(result.passed, isTrue);
    });

    test('zonder norm is er geen oordeel maar wel een percentage', () {
      final result = OciServeExamResult.fromJson(
        _released(extra: {'passed': null}),
      );

      expect(result.passed, isNull);
      expect(result.percentage, 70.0);
    });

    test('een niet-vrijgegeven poging heeft geen cijfers', () {
      final result = OciServeExamResult.fromJson({
        'attempt_id': 'a1',
        'exam_session_id': 's1',
        'title': 'Theorie',
        'status': 'submitted',
      });

      expect(result.released, isFalse);
      expect(result.totalItems, isNull);
      expect(result.passed, isNull);
    });

    test('weigert cijfers vóór de vrijgave', () {
      for (final field in [
        'total_items',
        'correct_items',
        'percentage',
        'passed',
      ]) {
        expect(
          () => OciServeExamResult.fromJson({
            'attempt_id': 'a1',
            'exam_session_id': 's1',
            'title': 'Theorie',
            'status': 'scored',
            field: field == 'passed' ? true : 1,
          }),
          throwsFormatException,
          reason: field,
        );
      }
    });

    test('weigert onmogelijke of onbekende velden', () {
      for (final bad in [
        _released(extra: {'correct_items': 11}),
        _released(extra: {'percentage': 101}),
        _released(extra: {'percentage': -1}),
        _released(extra: {'status': 'verzonnen'}),
        _released(extra: {'title': ''}),
        _released(extra: {'image_hash': '../../etc/passwd'}),
        _released(extra: {'onbekend': 1}),
        _released(extra: {'passed': 'ja'}),
      ]) {
        expect(
          () => OciServeExamResult.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('lijst weigert meer dan vijftig uitslagen', () {
      expect(
        () => OciServeExamResultList.fromJson({
          'results': List.filled(51, _released()),
          'server_time': '2026-09-12T12:00:00Z',
        }),
        throwsFormatException,
      );
    });
  });

  group('OciServeExamResultsSection', () {
    Future<void> show(
      WidgetTester tester,
      List<OciServeExamResult> results, {
      bool unavailable = false,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OciServeExamResultsSection(
            results: results,
            unavailable: unavailable,
          ),
        ),
      ),
    );

    testWidgets('toont niets zolang er geen uitslagen zijn', (tester) async {
      await show(tester, const []);

      expect(find.text('Mijn uitslagen'), findsNothing);
    });

    testWidgets('een vrijgegeven uitslag toont aantal, percentage en oordeel', (
      tester,
    ) async {
      await show(tester, [OciServeExamResult.fromJson(_released())]);

      expect(find.text('Mijn uitslagen'), findsOneWidget);
      expect(find.text('7 van 10 goed · 70%'), findsOneWidget);
      expect(find.text('Geslaagd'), findsOneWidget);
    });

    testWidgets('een onvoldoende toont "Niet geslaagd" met pictogram', (
      tester,
    ) async {
      await show(tester, [
        OciServeExamResult.fromJson(
          _released(
            extra: {'correct_items': 3, 'percentage': 33.3, 'passed': false},
          ),
        ),
      ]);

      expect(find.text('3 van 10 goed · 33,3%'), findsOneWidget);
      expect(find.text('Niet geslaagd'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });

    testWidgets('zonder norm staat er geen oordeel', (tester) async {
      await show(tester, [
        OciServeExamResult.fromJson(_released(extra: {'passed': null})),
      ]);

      expect(find.text('7 van 10 goed · 70%'), findsOneWidget);
      expect(find.text('Geslaagd'), findsNothing);
      expect(find.text('Niet geslaagd'), findsNothing);
    });

    testWidgets('voor de vrijgave staat er alleen dat de uitslag nog komt', (
      tester,
    ) async {
      await show(tester, [
        OciServeExamResult.fromJson({
          'attempt_id': 'a1',
          'exam_session_id': 's1',
          'title': 'Theorie',
          'status': 'scored',
        }),
      ]);

      expect(find.text('De uitslag is nog niet vrijgegeven.'), findsOneWidget);
      expect(find.textContaining('goed'), findsNothing);
    });

    testWidgets('een laadfout is zichtbaar', (tester) async {
      await show(tester, const [], unavailable: true);

      expect(
        find.text('De uitslagen konden niet worden geladen.'),
        findsOneWidget,
      );
    });
  });
}
