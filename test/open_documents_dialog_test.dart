import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
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
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    home: Scaffold(body: SizedBox(width: 400, height: 500, child: child)),
  );
}

Future<void> _openAndScan(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'het voorbeeld bleef laden',
    );

    expect(find.text('verslag.md'), findsOneWidget);
    expect(find.textContaining('De cijfers van dit kwartaal.'), findsWidgets);
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
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'het voorbeeld bleef laden',
    );

    expect(find.byType(SlidePreviewWidget), findsOneWidget);
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
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'het voorbeeld bleef laden',
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
