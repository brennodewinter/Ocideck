import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
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

Slide _scope() {
  const spec = ScopeMatrixSpec(
    title: 'Scope',
    rows: [
      ScopeRow(
        object: 'https://app.example',
        type: ScopeObjectType.web,
        status: ScopeStatus.tested,
      ),
      ScopeRow(object: '10.0.0.0/24', type: ScopeObjectType.infra),
    ],
  );
  return Slide.create(
    SlideType.scopeMatrix,
  ).copyWith(title: spec.title, tableRows: spec.toTableRows());
}

void main() {
  testWidgets(
    'scopeMatrix renders objects with derived standards and coverage',
    (tester) async {
      await tester.pumpWidget(_host(_scope()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('https://app.example'), findsOneWidget);
      expect(find.text('10.0.0.0/24'), findsOneWidget);
      // Standards are derived from the object type (§10.7).
      expect(find.text('WSTG'), findsOneWidget); // web
      expect(find.text('PTES'), findsOneWidget); // infra
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    },
  );
}
