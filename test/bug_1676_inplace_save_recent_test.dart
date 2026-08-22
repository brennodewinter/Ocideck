import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart' show fileServiceProvider;
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/shell/document_save_actions.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'in-place save werkt de recente-bestanden-lijst bij (#1676)',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('ocideck_1676_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final path = p.join(temp.path, 'doc.md');

      // Schrijf het oorspronkelijke bestand.
      File(path).writeAsStringSync('# Oorspronkelijk\n');

      final doc = MarkdownDocument.parse('# Oorspronkelijk\n');
      final notifier = DocumentNotifier()..loadDocument(doc, filePath: path);

      // Bewerk het document (maakt het vuil).
      notifier.edit('# Gewijzigd\n');

      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentProvider.overrideWith((_) => notifier),
            fileServiceProvider.overrideWithValue(
              FileService(
                MarkdownService(),
                ImageService(),
                () => throw UnimplementedError(),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, r, _) {
                ref = r;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final saved = await tester.runAsync(
        () => saveDocumentWithDestination(
          tester.element(find.byType(SizedBox)),
          ref,
          notifier,
        ),
      );
      expect(saved, isTrue);

      // De recente-bestanden-lijst moet het pad bevatten, als document.
      final recent = ref.read(settingsProvider).recentFiles;
      final entry = recent.where((f) => f.path == path).toList();
      expect(entry, hasLength(1));
      expect(entry.single.kind, MarkdownKind.document);
    },
  );
}
