import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/document_dossier_store.dart';
import 'package:ocideck/services/open_file_channel.dart';
import 'package:ocideck/widgets/dossier/dossier_overview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

class _DossierPicker extends FileSelectorPlatform {
  _DossierPicker(this.directory);
  final String directory;
  String? document;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    return directory;
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => document == null ? null : XFile(document!);

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => FileSaveLocation('$directory/dossier-export.pdf');
}

void main() {
  late Directory temp;
  late _DossierPicker picker;
  late FileSelectorPlatform previous;

  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    temp = await Directory.systemTemp.createTemp('ocideck-dossier-journey-');
    picker = _DossierPicker(temp.path);
    previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = picker;
  });

  tearDown(() async {
    FileSelectorPlatform.instance = previous;
    await temp.delete(recursive: true);
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
  }

  Future<void> tapUntil(
    WidgetTester tester,
    Finder action,
    bool Function() done,
  ) async {
    await tester.runAsync(() => tester.tap(action));
    await pumpUntil(tester, done);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> dossierMenu(WidgetTester tester, String action) async {
    await tester.tap(find.byTooltip('Dossier'));
    await tester.pumpAndSettle();
    if (action == 'Dossier openen…') {
      await tapUntil(
        tester,
        find.text(action).last,
        () => find.text('Alleen overzicht').evaluate().isNotEmpty,
      );
    } else {
      await tester.tap(find.text(action).last);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('create dossier, open its document, and return to cover', (
    tester,
  ) async {
    await start(tester);
    await dossierMenu(tester, 'Nieuw dossier');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Onderzoek 2026');
    await tester.enterText(
      find.byType(TextField).last,
      'Bronnen voor het besluit',
    );
    await tapUntil(
      tester,
      find.text('Dossier maken'),
      () => find.byType(DossierOverview).evaluate().isNotEmpty,
    );

    expect(find.byType(DossierOverview), findsOneWidget);
    expect(find.text('Bronnen voor het besluit'), findsOneWidget);
    final store = DocumentDossierStore(
      File(
        '${temp.listSync().whereType<Directory>().single.path}/dossier.json',
      ),
    );
    expect(
      (await tester.runAsync(store.load))!.description,
      'Bronnen voor het besluit',
    );

    await tapUntil(
      tester,
      find.text('Als document openen'),
      () => find.text('Terug naar dossier').evaluate().isNotEmpty,
    );
    expect(find.text('Terug naar dossier'), findsOneWidget);
    await tester.tap(find.text('Terug naar dossier'));
    await tester.pumpAndSettle();
    expect(find.byType(DossierOverview), findsOneWidget);
  });

  testWidgets('add a Markdown source through the dossier action', (
    tester,
  ) async {
    final source = File('${temp.path}/besluit.md');
    await tester.runAsync(() => source.writeAsString('# Besluit'));
    final store = DocumentDossierStore(
      File('${temp.path}/Dossier/dossier.json'),
    );
    await tester.runAsync(() => store.create('Dossier'));
    picker.document = store.manifestFile.path;

    await start(tester);
    await dossierMenu(tester, 'Dossier openen…');
    await tester.tap(find.text('Alleen overzicht'));
    await tester.pumpAndSettle();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      kOpenFileChannel,
      (call) async => call.method == 'pickFile' ? [source.path] : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        kOpenFileChannel,
        null,
      ),
    );

    await tapUntil(
      tester,
      find.text('Documenten toevoegen'),
      () => find.text('besluit').evaluate().isNotEmpty,
    );
    final dossier = (await tester.runAsync(store.load))!;
    expect(dossier.entries.single.originalName, 'besluit.md');
    expect(dossier.entries.single.sha256, hasLength(64));
  });

  testWidgets(
    'open existing dossier, verify sources, and navigate document tabs',
    (tester) async {
      final source = File('${temp.path}/bron.md');
      await tester.runAsync(() => source.writeAsString('# Bron\n\nBewijsstuk'));
      final store = DocumentDossierStore(
        File('${temp.path}/Dossier/dossier.json'),
      );
      await tester.runAsync(() async {
        var dossier = await store.create(
          'Dossier',
          description: 'Inhoud en bijlagen',
        );
        dossier = await store.addFile(dossier, source);
      });
      picker.document = store.manifestFile.path;

      await start(tester);
      await dossierMenu(tester, 'Dossier openen…');
      expect(find.text('Alleen overzicht'), findsOneWidget);
      await tester.tap(find.text('Alleen overzicht'));
      await tester.pumpAndSettle();
      expect(find.byType(DossierOverview), findsOneWidget);
      expect(find.text('bron'), findsWidgets);

      await tapUntil(
        tester,
        find.text('Alles controleren'),
        () => find.text('SHA-256 klopt').evaluate().isNotEmpty,
      );
      final checked = (await tester.runAsync(store.load))!;
      expect(checked.entries.single.checkedAt, isNotNull);
      expect(find.text('SHA-256 klopt'), findsWidgets);

      await tapUntil(
        tester,
        find.byTooltip('Document openen').first,
        () => find.text('Terug naar dossier').evaluate().isNotEmpty,
      );
      expect(find.text('Terug naar dossier'), findsOneWidget);
      await tester.tap(find.text('Terug naar dossier'));
      await tester.pumpAndSettle();
      expect(find.byType(DossierOverview), findsOneWidget);

      await tester.tap(find.text('Alle documenten openen'));
      await tester.pumpAndSettle();
      expect(find.byType(DossierOverview), findsOneWidget);
    },
  );

  testWidgets('edit source facts and export a PDF from the dossier', (
    tester,
  ) async {
    final source = File('${temp.path}/rapport.md');
    await tester.runAsync(
      () => source.writeAsString(
        '# Rapport\n\nEen leesbare samenvatting van de bevindingen.',
      ),
    );
    final store = DocumentDossierStore(File('${temp.path}/Zaak/dossier.json'));
    await tester.runAsync(() async {
      var dossier = await store.create('Zaak');
      dossier = await store.addFile(dossier, source);
    });
    picker.document = store.manifestFile.path;
    await start(tester);
    await dossierMenu(tester, 'Dossier openen…');
    await tester.tap(find.text('Alleen overzicht'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Documentgegevens bewerken').first);
    await tester.tap(find.text('Documentgegevens bewerken').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(1),
      'De kern van het rapport.',
    );
    await tester.enterText(find.byType(TextField).at(2), '2026-10-15');
    await tester.enterText(find.byType(TextField).at(3), 'Onderzoeksteam');
    await tapUntil(
      tester,
      find.text('Opslaan'),
      () =>
          find.byType(AlertDialog).evaluate().isEmpty &&
          find.text('De kern van het rapport.').evaluate().isNotEmpty,
    );
    final updated = (await tester.runAsync(store.load))!;
    expect(updated.entries.single.description, 'De kern van het rapport.');
    expect(updated.entries.single.documentDate, '2026-10-15');
    expect(updated.entries.single.author, 'Onderzoeksteam');

    await tester.tap(find.text('Dossier als PDF exporteren'));
    await tester.pumpAndSettle();
    expect(find.text('Tussenpagina vóór elk document'), findsOneWidget);
    final output = File('${temp.path}/dossier-export.pdf');
    await tapUntil(tester, find.text('PDF maken'), output.existsSync);
    final bytes = (await tester.runAsync(output.readAsBytes))!;
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
