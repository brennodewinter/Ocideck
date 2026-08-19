import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/utils/document_front_matter.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De Stijl-kiezer in de documenteditor: kiezen zet `theme:` in de frontmatter,
/// 'Geen' haalt hem er byte-getrouw weer uit, en de body bewerken laat de stijl
/// staan. De frontmatter is nooit tekst in de editor — de kiezer beheert hem.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(DocumentNotifier notifier) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => notifier)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

  Future<void> pickStyle(WidgetTester tester, String item) async {
    await tester.tap(find.textContaining('Stijl:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pump();
  }

  Future<void> pickTlp(WidgetTester tester, String item) async {
    await tester.tap(find.byKey(const Key('document-tlp-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pump();
  }

  testWidgets('een stijl kiezen schrijft `theme:` in de frontmatter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // Standaard geen stijl.
    expect(find.text('Stijl: Geen'), findsOneWidget);

    await pickStyle(tester, 'Security');

    expect(n.currentState.document!.styleName, 'Security');
    expect(
      n.currentState.document!.source,
      '---\ntheme: Security\n---\n\n# Kop\n\nTekst.',
    );
    // De body (wat de editor toont) bevat de frontmatter niet.
    expect(n.currentState.document!.body, '# Kop\n\nTekst.');
    expect(find.text('Stijl: Security'), findsOneWidget);
    expect(n.currentState.isDirty, isTrue);
  });

  testWidgets("'Geen' kiezen haalt de stijl er byte-getrouw weer uit", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const plain = '# Kop\n\nTekst.';
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(plain));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await pickStyle(tester, 'LibreKAT');
    expect(n.currentState.document!.styleName, 'LibreKAT');

    await pickStyle(tester, 'Geen (platte tekst)');
    expect(n.currentState.document!.styleName, isNull);
    expect(n.currentState.document!.source, plain);
  });

  testWidgets('de body bewerken laat de stijl-frontmatter staan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await pickStyle(tester, 'LibreKAT');

    // Naar Bron: het tekstveld toont de body zónder frontmatter.
    await tester.tap(find.text('Bron'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '# Kop\n\nTekst.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '# Nieuw\n\nMeer.');
    await tester.pump();

    expect(
      n.currentState.document!.source,
      '---\ntheme: LibreKAT\n---\n\n# Nieuw\n\nMeer.',
    );
    expect(n.currentState.document!.styleName, 'LibreKAT');
  });

  testWidgets('één TLP-keuze schrijft documentmetadata en is één undo-stap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const plain = '# Kop\n\nTekst.';
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(plain));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await pickTlp(tester, 'TLP:AMBER');

    expect(n.currentState.document!.tlp, TlpLevel.amber);
    expect(n.currentState.document!.source, '---\ntlp: amber\n---\n\n$plain');
    expect(n.currentState.document!.body, plain);
    expect(n.currentState.isDirty, isTrue);
    expect(find.byKey(const Key('document-header-tlp')), findsOneWidget);
    expect(find.byKey(const Key('document-footer-tlp')), findsOneWidget);
    final pageIndicator = tester.getRect(
      find.byKey(const Key('document-page-indicator')),
    );
    final footerBand = tester.getRect(
      find.byKey(const Key('document-footer-band')),
    );
    expect(pageIndicator.bottom, lessThanOrEqualTo(footerBand.top));

    n.undo();
    await tester.pump();

    expect(n.currentState.document!.source, plain);
    expect(n.currentState.document!.tlp, TlpLevel.none);
    expect(find.byKey(const Key('document-header-tlp')), findsNothing);
    expect(find.byKey(const Key('document-footer-tlp')), findsNothing);
    expect(n.canUndo, isFalse);
  });

  testWidgets(
    'Document · Eigenschappen bewaart vaste en vrije velden in één stap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const profile = ThemeProfile(
        name: 'Veldenstijl',
        documentHeaderText: '{title} · {project-id}',
        documentFooterText: '{author} — {subtitle}',
      );
      SharedPreferences.setMockInitialValues({
        'themeProfiles': jsonEncode([profile.toJson()]),
      });
      const body = '# Kop\n\nTekst.';
      const original = '---\ntheme: Veldenstijl\n---\n\n$body';
      final n = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse(original));
      await tester.pumpWidget(harness(n));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Document · Eigenschappen'), findsOneWidget);
      await tester.tap(find.text('Document · Eigenschappen'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('document-fields-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('document-field-title')),
        'Kwartaalaudit',
      );
      await tester.enterText(
        find.byKey(const Key('document-field-subtitle')),
        'Bestuurlijke samenvatting',
      );
      await tester.enterText(
        find.byKey(const Key('document-field-author')),
        'Ada Lovelace',
      );
      await tester.tap(find.byKey(const Key('document-field-add')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('document-field-name-0')),
        'project-id',
      );
      await tester.enterText(
        find.byKey(const Key('document-field-value-0')),
        'P-42',
      );
      await tester.tap(find.byKey(const Key('document-fields-save')));
      await tester.pumpAndSettle();

      expect(n.currentState.document!.fields, {
        'title': 'Kwartaalaudit',
        'subtitle': 'Bestuurlijke samenvatting',
        'author': 'Ada Lovelace',
        'project-id': 'P-42',
      });
      expect(n.currentState.document!.body, body);
      expect(
        n.currentState.document!.source,
        contains('title: Kwartaalaudit\n'),
      );
      expect(
        n.currentState.document!.source.indexOf('title: Kwartaalaudit'),
        lessThan(n.currentState.document!.source.indexOf('---\n\n$body')),
      );

      final header = tester.widget<InlineMarkdownText>(
        find.byKey(const Key('document-header-text')),
      );
      final footer = tester.widget<InlineMarkdownText>(
        find.byKey(const Key('document-footer-text')),
      );
      expect(header.text, r'Kwartaalaudit · P\-42');
      expect(footer.text, 'Ada Lovelace — Bestuurlijke samenvatting');
      expect(find.text('{title}', findRichText: true), findsNothing);
      expect(find.text('{author}', findRichText: true), findsNothing);
      expect(n.canUndo, isTrue);

      n.undo();
      await tester.pump();
      expect(n.currentState.document!.source, original);
      expect(n.currentState.document!.fields, isEmpty);
      expect(n.canUndo, isFalse);
    },
  );

  testWidgets('dubbele vrije velden zijn zichtbaar en blokkeren opslaan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const source =
        '---\n'
        'title: Eerste\n'
        'title: Tweede\n'
        '---\n\n'
        '# Rapport';
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(source));
    await tester.pumpWidget(harness(n));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document · Eigenschappen'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('document-fields-duplicate-warning')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('document-field-name-0')))
          .controller!
          .text,
      'title',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('document-field-value-0')))
          .controller!
          .text,
      'Tweede',
    );

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('document-fields-save')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('document-fields-dialog')), findsOneWidget);
    expect(n.currentState.document!.source, source);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('document-fields-save')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('document-fields-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-fields-dialog')), findsNothing);
    expect(
      RegExp(
        r'^title:',
        multiLine: true,
      ).allMatches(n.currentState.document!.source),
      hasLength(1),
    );
  });

  testWidgets('veldgrenzen geven een fout en begrenzen toevoegen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final source = [
      '---',
      for (var i = 0; i < kMaxDocumentFields; i++) 'field-$i: x',
      '---',
      '',
      '# Rapport',
    ].join('\n');
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(source));
    await tester.pumpWidget(harness(n));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document · Eigenschappen'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('document-fields-count-error')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('document-field-add')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('document-field-value-0')),
      'x' * (kMaxDocumentFieldValueLength + 1),
    );
    await tester.pump();
    expect(
      find.text('Een veldwaarde mag maximaal 4096 tekens bevatten.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('document-fields-dialog')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('document-fields-save')))
          .onPressed,
      isNull,
    );
    expect(n.currentState.document!.source, source);
  });

  testWidgets('meer dan 100 bronvelden opent begrensd en fail-closed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final source = [
      '---',
      for (var i = 0; i <= 1000; i++) 'field-$i: waarde',
      '---',
      '',
      '# Rapport',
    ].join('\n');
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(source));
    await tester.pumpWidget(harness(n));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document · Eigenschappen'));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const Key('document-fields-dialog'));
    expect(
      find.byKey(const Key('document-fields-count-error')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      findsNWidgets(3),
    );
    expect(find.byKey(const Key('document-field-name-0')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('document-fields-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('document-field-add')))
          .onPressed,
      isNull,
    );
    expect(n.currentState.document!.source, source);
  });
}
