import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/widgets/dialogs/open_presentation_dialog.dart';
import 'package:ocideck/widgets/dialogs/scan_library_dialog.dart';

import 'support/pump_until.dart';

/// In de bestandsdialogen werken navigatietoetsen volgens de focus.
/// Buiten de velden kiezen ze een rij (#1934). Enter opent het gekozen
/// resultaat, ook vanuit het zoekveld.
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

Future<void> _openAndScan(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.tap(find.text('open'));
  await tester.pump();
  await pumpUntil(
    tester,
    () =>
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty,
    reason: 'de mapscan bleef laden',
  );
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('open_keyboard_test');
    File('${dir.path}/alpha.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Alpha\n---\n\n# Alpha\n',
    );
    File('${dir.path}/bravo.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Bravo\n---\n\n# Bravo\n',
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('Enter from the search field opens the first row', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        );
      }),
    );
    await _openAndScan(tester);

    // Het zoekveld heeft autofocus; Enter opent de eerste rij.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.browseRequested, isFalse);
    expect(result!.paths, isNotEmpty);
    expect(result!.paths.first, endsWith('alpha.md'));
  });

  testWidgets('arrows keep both Open dialog fields in text editing', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        );
      }),
    );
    await _openAndScan(tester);

    final search = find.byType(TextField).first;
    await tester.enterText(search, 'a');
    final editable = find.descendant(
      of: search,
      matching: find.byType(EditableText),
    );
    final controller = tester.widget<EditableText>(editable).controller;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.selection, const TextSelection.collapsed(offset: 1));

    await tester.tap(find.byKey(const Key('open-tag-filter')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result?.paths.single, endsWith('alpha.md'));
  });

  testWidgets('End in the Scan Library query keeps the result unchanged', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await ScanLibraryDialog.show(
          context,
          fileService: _fileService(dir.path),
          recentFiles: ['${dir.path}/alpha.md'],
        );
      }),
    );
    await _openAndScan(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, endsWith('alpha.md'));
  });

  testWidgets('Tab to a button, then arrow down selects the first row', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        );
      }),
    );
    await _openAndScan(tester);

    // Tab uit het zoekveld naar de mapkeuze-knop; pijltje omlaag kiest de
    // eerste rij, Enter opent hem.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.paths.first, endsWith('alpha.md'));
  });

  testWidgets('arrow down twice selects the second row', (tester) async {
    final service = _fileService(dir.path);
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        );
      }),
    );
    await _openAndScan(tester);

    // Tab naar de knop, dan twee keer omlaag.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.paths.first, endsWith('bravo.md'));
  });

  testWidgets('arrow up from the first row stays on the first row', (
    tester,
  ) async {
    final service = _fileService(dir.path);
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        );
      }),
    );
    await _openAndScan(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.paths.first, endsWith('alpha.md'));
  });

  testWidgets('Home jumps to the first row', (tester) async {
    final service = _fileService(dir.path);
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        );
      }),
    );
    await _openAndScan(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.paths.first, endsWith('alpha.md'));
  });

  testWidgets('End jumps to the last row', (tester) async {
    final service = _fileService(dir.path);
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await OpenPresentationDialog.show(
          context,
          fileService: service,
          libraries: [LibraryFolder(name: 'Test', path: dir.path)],
        );
      }),
    );
    await _openAndScan(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.paths.first, endsWith('bravo.md'));
  });
}
