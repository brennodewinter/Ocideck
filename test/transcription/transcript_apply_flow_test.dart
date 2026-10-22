// De toepassingsweg van de definitieve pass (#2511): een verzoek via
// `transcriptApplyRequestProvider` wordt door de documenteditor
// beantwoord — stil als de tekst ongemoeid is, via de zichtbare
// vergelijking als iemand hem aangeraakt heeft.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/services/transcription/transcript_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/transcript_document_extras.dart';

const _doc =
    '<!-- transcript version=1 -->\n'
    '# Transcript — gesprek\n'
    '\n'
    'Bron: opname.wav\n'
    '\n'
    '---\n'
    '\n'
    'Provisionele tekst.\n';

Widget _app(ProviderContainer container, DocumentNotifier notifier) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: TranscriptDocumentExtras()),
      ),
    );

void main() {
  late ProviderContainer container;
  late DocumentNotifier notifier;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    notifier = DocumentNotifier()..loadDocument(MarkdownDocument.parse(_doc));
    container = ProviderContainer(
      overrides: [documentProvider.overrideWith((ref) => notifier)],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('ongemoeide provisionele tekst wordt stil vervangen', (
    tester,
  ) async {
    await tester.pumpWidget(_app(container, notifier));
    await tester.pump();

    final applied = container
        .read(transcriptApplyRequestProvider.notifier)
        .request(
          incoming: 'Definitieve tekst.\n',
          baseline: 'Provisionele tekst.\n',
        );
    await tester.pump();

    expect(await applied, isTrue);
    expect(
      transcriptBodyText(notifier.currentState.document!.source)!.trim(),
      'Definitieve tekst.',
    );
    // Geen dialoog voor een ongemoeide tekst.
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('aangepaste tekst vraagt de vergelijking; toepassen wint', (
    tester,
  ) async {
    notifier.edit(
      applyTranscriptBody(_doc, 'Handmatig gecorrigeerd.\n'),
      coalesceKey: null,
    );
    await tester.pumpWidget(_app(container, notifier));
    await tester.pump();

    final applied = container
        .read(transcriptApplyRequestProvider.notifier)
        .request(
          incoming: 'Definitieve tekst.\n',
          baseline: 'Provisionele tekst.\n',
        );
    await tester.pumpAndSettle();

    // De zichtbare vergelijking: beide teksten staan ernaast.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Huidige tekst'), findsOneWidget);
    expect(find.text('Nieuwe tekst'), findsOneWidget);

    await tester.tap(find.text('Nieuwe tekst toepassen'));
    await tester.pumpAndSettle();

    expect(await applied, isTrue);
    expect(
      transcriptBodyText(notifier.currentState.document!.source)!.trim(),
      'Definitieve tekst.',
    );
  });

  testWidgets('behouden laat de eigen tekst staan en meldt "niet toegepast"', (
    tester,
  ) async {
    notifier.edit(
      applyTranscriptBody(_doc, 'Handmatig gecorrigeerd.\n'),
      coalesceKey: null,
    );
    await tester.pumpWidget(_app(container, notifier));
    await tester.pump();

    final applied = container
        .read(transcriptApplyRequestProvider.notifier)
        .request(incoming: 'Definitieve tekst.\n');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Huidige tekst behouden'));
    await tester.pumpAndSettle();

    expect(await applied, isFalse);
    expect(
      transcriptBodyText(notifier.currentState.document!.source)!.trim(),
      'Handmatig gecorrigeerd.',
    );
  });
}
