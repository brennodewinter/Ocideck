import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/widgets/dialogs/finalize_seal_dialog.dart';

void main() {
  testWidgets(
    'legacy signature fields survive confirmation; cancelling returns no change',
    (tester) async {
      AppLocalizations.setActiveLanguageCode('nl');
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FinalizeSealResult? result;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await FinalizeSealDialog.show(
                    context,
                    initial: const DocumentSignature(
                      name: 'Tester',
                      role: 'Onderzoeker',
                      typedSignature: 'Tester',
                    ),
                  );
                  completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Verzegelen'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result!.signature!.name, 'Tester');
      expect(result!.signature!.role, 'Onderzoeker');
      expect(result!.signature!.typedSignature, 'Tester');
      expect(result!.signature!.date, matches(r'^\d{4}-\d{2}-\d{2}$'));
      completed = false;
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
    },
  );
}
