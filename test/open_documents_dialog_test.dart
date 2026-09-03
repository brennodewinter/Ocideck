import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/widgets/dialogs/open_kind_chrome.dart';
import 'package:ocideck/widgets/dialogs/open_preview_pane.dart';
import 'package:ocideck/widgets/dialogs/open_presentation_dialog.dart';
import 'package:ocideck/widgets/dialogs/scan_library_dialog.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import 'support/pump_until.dart';

/// De openschermen tonen presentaties én documenten, met per rij te zien wát
/// het is — en desgewenst een gerenderd voorbeeld ernaast.
FileService _fileService(String homeDir) => FileService(
  MarkdownService(),
  ImageService(),
  () => const ThemeProfile(),
  homeDirectory: () => homeDir,
);

Widget _host(void Function(BuildContext context) onPressed) {
  AppLocalizations.setActiveLanguageCode('nl');
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => ElevatedButton(
          onPressed: () => onPressed(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Widget _bare(Widget child) {
  AppLocalizations.setActiveLanguageCode('nl');
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    home: Scaffold(body: SizedBox(width: 400, height: 500, child: child)),
  );
}

/// Een ruim venster: deze dialogen zijn breed, en het voorbeeld ernaast stapt
/// opzij zodra er te weinig ruimte is (zie [OpenPreviewSplit]). Via `tester.view`
/// en niet `setSurfaceSize`: alleen het eerste bereikt `MediaQuery.sizeOf`, en
/// dáár leest de dialoogbreedte zijn bovengrens.
void _wideWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _openAndScan(WidgetTester tester) async {
  _wideWindow(tester);
  await tester.tap(find.text('open'));
  await tester.pump();
  await pumpUntil(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    reason: 'de mapscan bleef laden',
  );
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('open_documents_test');
    File('${dir.path}/demo.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Demo\n---\n\n# Demo\n',
    );
    File(
      '${dir.path}/verslag.md',
    ).writeAsStringSync('# Kwartaalverslag\n\nDe cijfers van dit kwartaal.\n');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('open dialog lists a document next to a presentation', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (context) => OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        ),
      ),
    );

    await _openAndScan(tester);

    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('Kwartaalverslag'), findsOneWidget);
    // Wat je ziet staat er ook bij: dit is een presentatie, dat een document.
    expect(find.text('Presentatie'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);
    expect(find.text('Presentaties (1)'), findsOneWidget);
    expect(find.text('Documenten (1)'), findsOneWidget);
  });

  testWidgets('a list of one kind carries no kind labels', (tester) async {
    // Alleen presentaties: dan zegt "Presentatie" achter élke regel niets meer,
    // en de telling boven de lijst zegt het al.
    File('${dir.path}/verslag.md').deleteSync();
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (context) => OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        ),
      ),
    );

    await _openAndScan(tester);

    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('Presentatie'), findsNothing);
    expect(find.text('Documenten (0)'), findsOneWidget);
  });

  testWidgets('the kind filter narrows the list to one sort', (tester) async {
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (context) => OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        ),
      ),
    );

    await _openAndScan(tester);
    await tester.tap(find.text('Documenten (1)'));
    await tester.pump();

    expect(find.text('Kwartaalverslag'), findsOneWidget);
    expect(find.text('Demo'), findsNothing);
    // De aantallen blijven staan: ze horen bij de zoekactie, niet bij het filter.
    expect(find.text('Presentaties (1)'), findsOneWidget);
  });

  testWidgets('een lege bibliotheekmap zegt wat je kunt doen', (tester) async {
    // De map bestaat maar bevat geen markdown: de lege staat moet wijzen
    // naar Bladeren en een andere map, niet alleen 'geen treffers' tonen (#1962).
    final emptyDir = Directory.systemTemp.createTempSync('open_empty_test');
    addTearDown(() => emptyDir.deleteSync(recursive: true));
    final service = _fileService(emptyDir.path);
    await tester.pumpWidget(
      _host(
        (context) => OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Leeg', path: emptyDir.path)],
        ),
      ),
    );
    await _openAndScan(tester);
    expect(
      find.textContaining('Geen presentaties of documenten gevonden'),
      findsOneWidget,
    );
    // De Bladeren-knop staat in het lege vlak, niet alleen in de voet.
    expect(find.widgetWithText(OutlinedButton, 'Bladeren…'), findsWidgets);
  });

  testWidgets('the broad scan lists documents too', (tester) async {
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (context) => ScanLibraryDialog.show(
          context,
          fileService: service,
          recentFiles: <String>['${dir.path}/demo.md'],
        ),
      ),
    );

    await _openAndScan(tester);

    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('Kwartaalverslag'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);
  });

  testWidgets('with the setting on, the open dialog previews a row', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (context) => OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
          showPreview: true,
        ),
      ),
    );

    await _openAndScan(tester);
    expect(find.byType(OpenPreviewPane), findsOneWidget);
    // Nog niets aangewezen: het voorbeeld zegt wat het van je verwacht.
    expect(find.textContaining('Wijs een bestand aan'), findsOneWidget);

    // De knop naast de rij is de weg voor toetsenbord en aanraakscherm; de
    // muisaanwijzer doet hetzelfde.
    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pump(OpenPreviewPane.settleDelay);
    await pumpUntil(
      tester,
      () => find.byType(SlidePreviewWidget).evaluate().isNotEmpty,
      reason: 'het voorbeeld van de eerste rij kwam niet',
    );

    expect(find.byType(SlidePreviewWidget), findsOneWidget);
  });

  testWidgets('on a narrow window the preview and its button both step aside', (
    tester,
  ) async {
    // Een klein venster: de dialoog klemt op de schermbreedte, en dan past het
    // voorbeeld er niet meer naast.
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (context) => OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
          showPreview: true,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de mapscan bleef laden',
    );

    expect(find.byType(OpenPreviewPane), findsNothing);
    // Een knop die niets zichtbaars doet, hoort er dan ook niet te staan.
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.text('Demo'), findsOneWidget);
  });

  testWidgets('with the setting on, the broad scan shows the preview pane', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (context) => ScanLibraryDialog.show(
          context,
          fileService: service,
          recentFiles: <String>['${dir.path}/demo.md'],
          showPreview: true,
        ),
      ),
    );

    await _openAndScan(tester);

    expect(find.byType(OpenPreviewPane), findsOneWidget);
  });

  testWidgets('the preview renders a document before it is opened', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _bare(
        OpenPreviewPane(fileService: service, path: '${dir.path}/verslag.md'),
      ),
    );
    await tester.pump(OpenPreviewPane.settleDelay);
    await pumpUntil(
      tester,
      () => find
          .textContaining('De cijfers van dit kwartaal.')
          .evaluate()
          .isNotEmpty,
      reason: 'de documenttekst werd niet getekend',
    );

    expect(find.text('verslag.md'), findsOneWidget);
  });

  testWidgets('the preview shows the first slide of a presentation', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _bare(OpenPreviewPane(fileService: service, path: '${dir.path}/demo.md')),
    );
    await tester.pump(OpenPreviewPane.settleDelay);
    await pumpUntil(
      tester,
      () => find.byType(SlidePreviewWidget).evaluate().isNotEmpty,
      reason: 'de eerste dia werd niet getekend',
    );

    expect(find.text('demo.md'), findsOneWidget);
  });

  testWidgets('the preview refuses a file that opening would refuse', (
    tester,
  ) async {
    File(
      '${dir.path}/kwaad.md',
    ).writeAsStringSync('# Kop\n\n<script>steal()</script>\n');
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _bare(
        OpenPreviewPane(fileService: service, path: '${dir.path}/kwaad.md'),
      ),
    );
    await tester.pump(OpenPreviewPane.settleDelay);
    await pumpUntil(
      tester,
      () =>
          find.textContaining('kan niet worden getoond').evaluate().isNotEmpty,
      reason: 'de weigering werd niet gemeld',
    );

    expect(find.textContaining('kan niet worden getoond'), findsOneWidget);
    // De inhoud zelf komt er niet doorheen.
    expect(find.textContaining('Kop'), findsNothing);
  });

  testWidgets('without a file the preview says what it is waiting for', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    await tester.pumpWidget(
      _bare(OpenPreviewPane(fileService: service, path: null)),
    );
    await tester.pump();

    expect(find.text('Voorbeeld'), findsOneWidget);
    expect(find.textContaining('Wijs een bestand aan'), findsOneWidget);
  });

  group('OpenPreviewSplit', () {
    Future<void> pumpSplit(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width + 100, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AppLocalizations.setActiveLanguageCode('nl');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 400,
              child: const OpenPreviewSplit(
                list: Text('lijst'),
                pane: Text('voorbeeld'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows the preview beside the list when there is room', (
      tester,
    ) async {
      await pumpSplit(tester, 900);
      expect(find.text('lijst'), findsOneWidget);
      expect(find.text('voorbeeld'), findsOneWidget);
    });

    testWidgets('steps aside on a narrow window instead of squeezing', (
      tester,
    ) async {
      await pumpSplit(tester, 600);
      expect(find.text('lijst'), findsOneWidget);
      expect(find.text('voorbeeld'), findsNothing);
    });
  });

  group('OpenKindFilter', () {
    test('accepts what its name says', () {
      expect(OpenKindFilter.all.accepts(MarkdownKind.document), isTrue);
      expect(OpenKindFilter.all.accepts(MarkdownKind.presentation), isTrue);
      expect(
        OpenKindFilter.documents.accepts(MarkdownKind.presentation),
        isFalse,
      );
      expect(OpenKindFilter.documents.accepts(MarkdownKind.document), isTrue);
      expect(
        OpenKindFilter.presentations.accepts(MarkdownKind.presentation),
        isTrue,
      );
      expect(
        OpenKindFilter.presentations.accepts(MarkdownKind.document),
        isFalse,
      );
    });
  });
}
