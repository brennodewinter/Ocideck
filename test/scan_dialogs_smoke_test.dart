import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/widgets/dialogs/import_slides_dialog.dart';
import 'package:ocideck/widgets/dialogs/open_presentation_dialog.dart';
import 'package:ocideck/widgets/dialogs/scan_library_dialog.dart';
import 'package:ocideck/widgets/dialogs/slide_finder_dialog.dart';

import 'support/pump_until.dart';

/// A FileService backed only by real, local services — enough for the dialogs
/// to perform their on-disk directory scans against a temp fixture.
FileService _fileService(String homeDir) {
  return FileService(
    MarkdownService(),
    ImageService(),
    () => const ThemeProfile(),
    homeDirectory: () => homeDir,
  );
}

/// A host that exposes a single "open" button whose onPressed runs [onPressed]
/// with a localized [BuildContext], mirroring the showDialog smoke pattern.
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

/// Pumps through the dialog's async directory scan and lets it settle.
Future<void> _openAndScan(WidgetTester tester) async {
  // A large surface avoids RenderFlex overflow in these wide, fixed-size
  // dialogs.
  await tester.binding.setSurfaceSize(const Size(1800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.tap(find.text('open'));
  await tester.pump(); // dialog appears (loading)
  // Wachten tot de scan klaar ís, niet tot een klok is afgelopen. Alle vier de
  // dialogen tonen een voortgangsindicator zolang ze de map aflopen en halen
  // die weg als ze klaar zijn — dat is dus de uitkomst waarop te wachten valt.
  //
  // Hier stond 400 ms plus vijf begrensde frames. Dat is een gok op hoe traag de
  // schijf vandaag is: te krap onder belasting, en elke groene draai betaalt de
  // volle 400 ms ook als de scan in 5 ms klaar was.
  //
  // `pumpAndSettle` kan hier niet: een knipperende tekstcursor (autofocus) en de
  // voortgangsindicator zelf laten de framewachtrij nooit leeglopen, dus die zou
  // aflopen op een time-out. `pumpUntil` pompt losse frames en heeft daar geen
  // last van.
  await pumpUntil(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    reason: 'de mapscan bleef laden',
  );
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('scan_test');
    File('${dir.path}/demo.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Demo\n---\n\n# Demo\n',
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('OpenPresentationDialog scans and renders', (
    WidgetTester tester,
  ) async {
    final FileService service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (BuildContext context) => OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        ),
      ),
    );

    await _openAndScan(tester);

    expect(find.byType(OpenPresentationDialog), findsOneWidget);
  });

  testWidgets('ScanLibraryDialog scans known locations and renders', (
    WidgetTester tester,
  ) async {
    final FileService service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (BuildContext context) => ScanLibraryDialog.show(
          context,
          fileService: service,
          recentFiles: <String>['${dir.path}/demo.md'],
        ),
      ),
    );

    await _openAndScan(tester);

    expect(find.byType(ScanLibraryDialog), findsOneWidget);
  });

  testWidgets('SlideFinderDialog scans and renders', (
    WidgetTester tester,
  ) async {
    final FileService service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (BuildContext context) => SlideFinderDialog.show(
          context,
          fileService: service,
          roots: [LibraryFolder(name: 'Test', path: dir.path)],
          onAdd: (Slide _) {},
        ),
      ),
    );

    await _openAndScan(tester);

    expect(find.byType(SlideFinderDialog), findsOneWidget);
  });

  testWidgets('ImportSlidesDialog scans and renders', (
    WidgetTester tester,
  ) async {
    final FileService service = _fileService(dir.path);
    await tester.pumpWidget(
      _host(
        (BuildContext context) => ImportSlidesDialog.show(
          context,
          fileService: service,
          initialDirectory: dir.path,
        ),
      ),
    );

    await _openAndScan(tester);

    expect(find.byType(ImportSlidesDialog), findsOneWidget);
  });
}
