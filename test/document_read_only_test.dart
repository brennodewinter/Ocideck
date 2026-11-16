import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';

/// De alleen-lezenvergrendeling van een uitgedeeld document (`ocideck_read_only`)
/// — de document-tegenhanger van `ocideck_play_only` bij decks (#2912).
void main() {
  group('MarkdownDocument.readOnly', () {
    test('een platte .md is niet vergrendeld', () {
      expect(MarkdownDocument.parse('# Tekst\n').readOnly, isFalse);
    });

    test('vergrendelen en weer ontgrendelen is byte-chirurgisch', () {
      const plain = '# Tekst\n\nGewoon.\n';
      final locked = MarkdownDocument.parse(plain).withReadOnly(true);
      expect(locked.readOnly, isTrue);
      expect(locked.source, contains('ocideck_read_only'));
      // De vergrendelde bron herleeft als vergrendeld document.
      expect(MarkdownDocument.parse(locked.source).readOnly, isTrue);
      // En de uitgang brengt de oorspronkelijke bytes terug.
      expect(locked.withReadOnly(false).source, plain);
    });

    test('de vergrendeling laat bestaande front matter ongemoeid', () {
      final doc = MarkdownDocument.parse(
        '---\ntheme: rapport\n---\n\n# Tekst\n',
      ).withReadOnly(true);
      expect(doc.styleName, 'rapport');
      expect(doc.readOnly, isTrue);
      final unlocked = doc.withReadOnly(false);
      expect(unlocked.readOnly, isFalse);
      expect(unlocked.styleName, 'rapport');
    });
  });

  group('vergrendelde documentweergave', () {
    Widget editorApp(DocumentNotifier n) => ProviderScope(
      overrides: [documentProvider.overrideWith((ref) => n)],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DocumentEditorScreen(),
      ),
    );

    testWidgets(
      'een vergrendeld document toont de inhoud zonder bewerkingsoppervlak',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1300, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final n = DocumentNotifier()
          ..loadDocument(
            MarkdownDocument.parse(
              '# Verspreid stuk\n\nLees maar.\n',
            ).withReadOnly(true),
          );
        await tester.pumpWidget(editorApp(n));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // De inhoud is er, de editor is het niet: geen schrijfvlak, geen
        // stand-keuze, geen werkbalk-menu.
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.text('Verspreid stuk'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Visueel'), findsNothing);
        expect(find.byIcon(Icons.more_vert), findsNothing);
      },
    );
  });
}
