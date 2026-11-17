import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/transcription/speaker_corrections.dart';
import 'package:ocideck/services/transcription/transcript_document.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/widgets/dialogs/speaker_corrections_dialog.dart';

void main() {
  final source = buildTranscriptMarkdown(
    const TranscriptProvenance(
      title: 'Test',
      sourceLabel: 'test.wav',
      recordedAt: 'vandaag',
      sourceKindLabel: 'bestand',
    ),
    formatTranscriptBody(const [
      TranscriptSegment(text: 'Eerste zin. Andere stem.', speakerIds: ['a']),
      TranscriptSegment(text: 'Antwoord.', speakerIds: ['b']),
    ]),
  );
  Future<void> open(WidgetTester tester, void Function(String?) result) async {
    AppLocalizations.setActiveLanguageCode('nl');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result(await showSpeakerCorrectionsDialog(context, source)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> target(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spreker 2').last);
    await tester.pumpAndSettle();
  }

  testWidgets('assign selected fragment through dialog', (tester) async {
    String? result;
    await open(tester, (s) => result = s);
    await tester.tap(find.byType(Checkbox).first);
    await target(tester);
    await tester.tap(find.text('Toewijzen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();
    expect(SpeakerCorrections.read(result!)!.idsAt(0), ['b']);
  });
  testWidgets('merge previews affected count and asks confirmation', (
    tester,
  ) async {
    String? result;
    await open(tester, (s) => result = s);
    await target(tester);
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spreker 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samenvoegen (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Spreker 1 → Spreker 2 (1)'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Samenvoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();
    expect(SpeakerCorrections.read(result!)!.idsAt(0), ['b']);
  });
  testWidgets('split at caret then add and assign extra speaker', (
    tester,
  ) async {
    String? result;
    await open(tester, (s) => result = s);
    await tester.tap(find.byTooltip('Fragment splitsen').first);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.selection = const TextSelection.collapsed(offset: 12);
    await tester.tap(find.widgetWithText(TextButton, 'Fragment splitsen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nieuwe spreker'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Carla');
    await tester.tap(find.widgetWithText(TextButton, 'Toewijzen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();
    final reopened = SpeakerCorrections.read(result!)!;
    expect(reopened.lines, hasLength(3));
    expect(reopened.lines[1], '**Carla:** Andere stem.');
    expect(reopened.names[reopened.idsAt(1).single], 'Carla');
  });
}
