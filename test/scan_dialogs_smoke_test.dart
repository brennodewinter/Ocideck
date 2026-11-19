import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/widgets/dialogs/import_slides_dialog.dart';
import 'package:ocideck/widgets/dialogs/dialog_shell.dart';
import 'package:ocideck/widgets/dialogs/open_presentation_dialog.dart';
import 'package:ocideck/widgets/dialogs/scan_library_dialog.dart';
import 'package:ocideck/widgets/dialogs/slide_finder_dialog.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

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

  testWidgets(
    'Openen sorteert op presentatiedatum en toont wijzigingsdatum als terugval',
    (tester) async {
      void writeDeck(String title, String date, DateTime modified) {
        final file = File('${dir.path}/$title.md');
        file.writeAsStringSync(
          '---\nmarp: true\ntitle: $title\n'
          '${date.isEmpty ? '' : 'date: $date\n'}---\n\n# Dia\n',
        );
        file.setLastModifiedSync(modified);
      }

      File('${dir.path}/demo.md').deleteSync();
      writeDeck('A oudste', '2022-01-08', DateTime(2026, 2));
      writeDeck('B nieuwste', '2025-04-17', DateTime(2021, 2));
      writeDeck('C zonder datum', '', DateTime(2024, 2, 3, 12));
      await tester.pumpWidget(
        _host(
          (context) => OpenPresentationDialog.show(
            context,
            fileService: _fileService(dir.path),
            libraries: [LibraryFolder(name: 'Test', path: dir.path)],
          ),
        ),
      );
      await _openAndScan(tester);
      expect(find.textContaining('2025-04-17'), findsOneWidget);
      expect(find.text('Laatst gewijzigd op 2024-02-03'), findsOneWidget);

      double y(String title) => tester.getTopLeft(find.text(title)).dy;

      await tester.tap(find.byTooltip('Sorteren'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('Nieuwste eerst'),
          matching: find.byWidgetPredicate(
            (widget) => widget is CheckedPopupMenuItem,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(y('B nieuwste'), lessThan(y('C zonder datum')));
      expect(y('C zonder datum'), lessThan(y('A oudste')));

      await tester.tap(find.byTooltip('Sorteren'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('Oudste eerst'),
          matching: find.byWidgetPredicate(
            (widget) => widget is CheckedPopupMenuItem,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(y('A oudste'), lessThan(y('C zonder datum')));
      expect(y('C zonder datum'), lessThan(y('B nieuwste')));
    },
  );

  testWidgets('Openen ziet een extern aangemaakt bestand na verversen', (
    tester,
  ) async {
    File('${dir.path}/demo.md').deleteSync();
    await tester.pumpWidget(
      _host(
        (context) => OpenPresentationDialog.show(
          context,
          fileService: _fileService(dir.path),
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        ),
      ),
    );
    await _openAndScan(tester);

    File('${dir.path}/vers.md').writeAsStringSync('# Vers document\n');
    expect(find.text('Vers document'), findsNothing);

    await tester.tap(find.byTooltip('Vernieuwen'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de vernieuwde mapscan bleef laden',
    );
    expect(find.text('Vers document'), findsOneWidget);
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
    expect(find.byType(OciDialogShell), findsOneWidget);
  });

  testWidgets(
    'dia-import schaalt miniaturen zonder selectie of volgorde te verliezen',
    (tester) async {
      File('${dir.path}/demo.md').writeAsStringSync(
        '---\nmarp: true\ntitle: Demo\n---\n\n# Eerste dia\n\n---\n\n# Tweede dia\n',
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1800, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<Slide>? imported;
      await tester.pumpWidget(
        _host((context) async {
          imported = await ImportSlidesDialog.show(
            context,
            fileService: _fileService(dir.path),
            initialDirectory: dir.path,
          );
        }),
      );
      await _openAndScan(tester);

      final surface = find.byKey(const Key('oci-dialog-surface'));
      final cards = find.byType(SlidePreviewWidget);
      expect(tester.getSize(surface).width, greaterThan(1000));
      expect(cards, findsNWidgets(2));
      final originalWidth = tester.getSize(cards.first).width;
      await tester.tap(cards.last);
      await tester.tap(cards.first);
      await tester.pump();

      final slider = find.byKey(const Key('import-thumbnail-size'));
      await tester.tapAt(
        tester.getRect(slider).centerRight - const Offset(25, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(cards.first).width, greaterThan(originalWidth));
      expect(find.text('Importeren (2)'), findsOneWidget);

      tester.view.physicalSize = const Size(390, 640);
      await tester.binding.setSurfaceSize(const Size(390, 640));
      await tester.pumpAndSettle();
      expect(tester.getSize(surface).width, lessThan(390));
      expect(
        tester.getSize(cards.first).width,
        lessThan(tester.getSize(surface).width),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Importeren (2)'));
      await tester.pumpAndSettle();
      expect(imported?.map((slide) => slide.title), [
        'Eerste dia',
        'Tweede dia',
      ]);
    },
  );

  testWidgets('Slides importeren ziet een extern aangemaakt deck na verversen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        (context) => ImportSlidesDialog.show(
          context,
          fileService: _fileService(dir.path),
          initialDirectory: dir.path,
        ),
      ),
    );
    await _openAndScan(tester);

    File('${dir.path}/vers.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Vers deck\n---\n\n# Vers deck\n',
    );
    expect(find.text('Vers deck'), findsNothing);

    await tester.tap(find.byTooltip('Vernieuwen'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de vernieuwde mapscan bleef laden',
    );
    expect(find.text('Vers deck'), findsWidgets);
  });
}
