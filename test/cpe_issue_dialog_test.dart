import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/cpe_issue_dialog.dart';
import 'package:ocideck/widgets/forms/form_fill_view.dart';

void main() {
  testWidgets('group form opens and prevents issuing incomplete certificates', (
    tester,
  ) async {
    AppLocalizations.setActiveLanguageCode('nl');
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CpeIssueDialog(
                  template: File(
                    'assets/document_templates/cpe.nl.md',
                  ).readAsStringSync(),
                  language: 'nl',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FormFillView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('PE-bewijzen maken'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text(
        'Controleer de verplichte velden en de naam, het e-mailadres en de uren van elke deelnemer.',
      ),
      findsOneWidget,
    );
    expect(find.byType(CpeIssueDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
