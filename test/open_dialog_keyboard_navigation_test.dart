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

import 'support/pump_until.dart';

/// Toetsenbordbediering van de openen-dialoog (#1934): pijltje omlaag kiest
/// de eerste rij, Enter opent hem, en de geselecteerde rij draagt een
/// zichtbare focusrand. De toetsen werken vanuit het zoekveld — pijltjes
/// in het zoekveld bewegen de cursor en worden niet afgevangen, maar
/// pijltjes vanaf een knop of Enter vanuit het zoekveld bereiken de
/// dialoog-handler.
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
