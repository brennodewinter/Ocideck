// Widget-toetsen voor de documentmodus-dialogen (DOCUMENT_MODE.md §11.2/§11.3):
// de export-dialoog en de twee conversie-dialogen. Ze bewijzen de eerlijke
// bewoording (Opslaan vs Exporteren, geen PDF-belofte) en dat de gekozen
// profiel/formaat-waarden bij bevestigen doorstromen — plus dat het zegel-verlies
// expliciet in beeld staat bij deck → document.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/widgets/dialogs/convert_to_document_dialog.dart';
import 'package:ocideck/widgets/dialogs/convert_to_presentation_dialog.dart';
import 'package:ocideck/widgets/dialogs/document_export_dialog.dart';

Widget _app(Widget home) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  home: home,
);

void main() {
  group('DocumentExportDialog', () {
    testWidgets('toont de eerlijke bewoording en de PDF-regel', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => DocumentExportDialog.show(
                context,
                privacyChecksEnabled: true,
                onExport: (_, _) async => null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Je byte-getrouwe origineel bewaar je met Opslaan'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Voor PDF: open de HTML en print via je browser'),
        findsOneWidget,
      );
    });

    testWidgets('geeft het gekozen profiel en formaat door bij bevestigen', (
      tester,
    ) async {
      PrivacyExportProfile? gotProfile;
      DocumentExportFormat? gotFormat;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => DocumentExportDialog.show(
                context,
                privacyChecksEnabled: true,
                onExport: (profile, format) async {
                  gotProfile = profile;
                  gotFormat = format;
                  return '/tmp/rapport-geredigeerd.html';
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Kies Geredigeerd + HTML.
      await tester.tap(find.text('Geredigeerd'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HTML'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exporteren…'));
      await tester.pumpAndSettle();

      expect(gotProfile, PrivacyExportProfile.redacted);
      expect(gotFormat, DocumentExportFormat.html);
      // Het resultaatpad staat in beeld.
      expect(find.textContaining('rapport-geredigeerd.html'), findsOneWidget);
    });

    testWidgets('biedt geen presentatiepakket als documentformaat', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => DocumentExportDialog.show(
                context,
                privacyChecksEnabled: true,
                onExport: (profile, format) async => '/tmp/doc.md',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Pakket (.ocideck)'), findsNothing);
    });
  });

  group('ConvertToPresentationDialog', () {
    testWidgets('toont het aantal dia\'s en de drop-lijst', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await ConvertToPresentationDialog.show(
                    context,
                    slideCount: 4,
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('4'), findsWidgets);
      expect(
        find.textContaining('je originele bestand blijft ongewijzigd'),
        findsOneWidget,
      );
      expect(find.textContaining('wordt een diagrens'), findsOneWidget);
      await tester.tap(find.text('Converteren'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('ConvertToDocumentDialog', () {
    testWidgets('benoemt het zegel-verlies expliciet', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await ConvertToDocumentDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('draagt geen zegel'), findsOneWidget);
      await tester.tap(find.text('Converteren'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });
}
