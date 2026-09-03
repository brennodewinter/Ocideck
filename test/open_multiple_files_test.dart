import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/open_presentation_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

/// #1928: meerdere bestanden tegelijk aanwijzen en in één keer openen.
///
/// De dialoog gaf tot nu toe precies één pad terug; wie drie presentaties
/// wilde, liep de hele dialoog drie keer door. Deze tests toetsen de
/// selectie-handgreep (Ctrl/Cmd-klik en Shift-klik) en wat de dialoog dan
/// oplevert.
FileService _fileService(String homeDir) => FileService(
  MarkdownService(),
  ImageService(),
  () => const ThemeProfile(),
  homeDirectory: () => homeDir,
);

/// Host die het resultaat van de dialoog vasthoudt, zodat een test kan zien
/// wélke paden eruit kwamen.
Widget _host(
  FileService service,
  String dir,
  void Function(OpenSearchResult?) onResult,
) {
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
          onPressed: () async {
            onResult(
              await OpenPresentationDialog.show(
                context,
                fileService: service,
                libraries: [LibraryFolder(name: 'Test', path: dir)],
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
}

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

/// Klik op de rij met [title], met [modifier] ingedrukt wanneer die er is.
Future<void> _tapRow(
  WidgetTester tester,
  String title, {
  LogicalKeyboardKey? modifier,
}) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  await tester.tap(find.text(title));
  await tester.pump();
  if (modifier != null) await tester.sendKeyUpEvent(modifier);
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('open_multiple_test');
    // Drie decks met titels die alfabetisch de lijstvolgorde vastleggen: de
    // dialoog sorteert op weergavetitel, en Shift-klik meet een bereik.
    for (final name in ['Alfa', 'Bravo', 'Charlie']) {
      File('${dir.path}/${name.toLowerCase()}.md').writeAsStringSync(
        '---\nmarp: true\ntheme: ocideck\ntitle: $name\n---\n\n# $name\n',
      );
    }
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('een kale klik opent nog steeds dat ene bestand', (tester) async {
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host(_fileService(dir.path), dir.path, (r) => result = r),
    );
    await _openAndScan(tester);

    await _tapRow(tester, 'Bravo');
    await tester.pumpAndSettle();

    expect(result!.paths, ['${dir.path}/bravo.md']);
  });

  testWidgets('Ctrl-klik wijst aan zonder te openen, de knop opent alles', (
    tester,
  ) async {
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host(_fileService(dir.path), dir.path, (r) => result = r),
    );
    await _openAndScan(tester);

    await _tapRow(tester, 'Alfa', modifier: LogicalKeyboardKey.controlLeft);
    await _tapRow(tester, 'Charlie', modifier: LogicalKeyboardKey.controlLeft);
    // Nog niets geopend: de dialoog staat er nog en wacht op de knop.
    expect(find.byType(OpenPresentationDialog), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('Openen (2)'));
    await tester.pumpAndSettle();

    expect(result!.paths, ['${dir.path}/alfa.md', '${dir.path}/charlie.md']);
    // Een dia-index hoort bij één bestand; bij een stapel is er geen treffer.
    expect(result!.slideIndex, isNull);
  });

  testWidgets('Cmd-klik werkt net als Ctrl-klik', (tester) async {
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host(_fileService(dir.path), dir.path, (r) => result = r),
    );
    await _openAndScan(tester);

    await _tapRow(tester, 'Alfa', modifier: LogicalKeyboardKey.metaLeft);
    await _tapRow(tester, 'Bravo', modifier: LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text('Openen (2)'));
    await tester.pumpAndSettle();

    expect(result!.paths, ['${dir.path}/alfa.md', '${dir.path}/bravo.md']);
  });

  testWidgets('Ctrl-klik op een aangewezen rij haalt hem er weer af', (
    tester,
  ) async {
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host(_fileService(dir.path), dir.path, (r) => result = r),
    );
    await _openAndScan(tester);

    await _tapRow(tester, 'Alfa', modifier: LogicalKeyboardKey.controlLeft);
    await _tapRow(tester, 'Bravo', modifier: LogicalKeyboardKey.controlLeft);
    await _tapRow(tester, 'Bravo', modifier: LogicalKeyboardKey.controlLeft);

    expect(find.text('Openen (1)'), findsOneWidget);
    await tester.tap(find.text('Openen (1)'));
    await tester.pumpAndSettle();

    expect(result!.paths, ['${dir.path}/alfa.md']);
  });

  testWidgets('Shift-klik neemt het hele bereik mee', (tester) async {
    OpenSearchResult? result;
    await tester.pumpWidget(
      _host(_fileService(dir.path), dir.path, (r) => result = r),
    );
    await _openAndScan(tester);

    await _tapRow(tester, 'Alfa', modifier: LogicalKeyboardKey.controlLeft);
    await _tapRow(tester, 'Charlie', modifier: LogicalKeyboardKey.shiftLeft);

    expect(find.text('Openen (3)'), findsOneWidget);
    await tester.tap(find.text('Openen (3)'));
    await tester.pumpAndSettle();

    expect(result!.paths, [
      '${dir.path}/alfa.md',
      '${dir.path}/bravo.md',
      '${dir.path}/charlie.md',
    ]);
  });

  testWidgets('zonder selectie staat er geen openen-knop', (tester) async {
    await tester.pumpWidget(_host(_fileService(dir.path), dir.path, (_) {}));
    await _openAndScan(tester);

    // Een klik op de rij opent al; een knop die hetzelfde nog eens belooft
    // maakt het scherm alleen drukker.
    expect(find.textContaining('Openen ('), findsNothing);
    // De handgreep staat er wel: zonder die regel vindt niemand hem.
    expect(
      find.text('Klik met Ctrl/Cmd of Shift om meerdere bestanden te kiezen.'),
      findsOneWidget,
    );
  });

  testWidgets('twee aangewezen presentaties openen in twee tabbladen', (
    tester,
  ) async {
    // De hele reis, door de echte shell: bibliotheek instellen, Ctrl/Cmd+O,
    // twee rijen aanwijzen, "Openen (2)". De dialoogtests hierboven zien
    // alleen wat de dialoog teruggeeft; deze ziet wat er dan gebeurt.
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    await container
        .read(settingsProvider.notifier)
        .addLibrary('Test', dir.path);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs.length, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de mapscan bleef laden',
    );

    await _tapRow(tester, 'Alfa', modifier: LogicalKeyboardKey.controlLeft);
    await _tapRow(tester, 'Charlie', modifier: LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Openen (2)'));
    // Openen leest écht van schijf (de veiligheidsscan én de parse), en dat is
    // geen microtask die pumpAndSettle uitzit.
    await pumpUntil(
      tester,
      () => container.read(tabsProvider).tabs.length >= 2,
      reason: 'het tweede tabblad kwam niet',
    );
    await tester.pumpAndSettle();

    // Het lege starttabblad wordt hergebruikt voor het eerste bestand, het
    // tweede krijgt een eigen tabblad — en dat is het actieve.
    final tabs = container.read(tabsProvider);
    expect(tabs.tabs.length, 2);
    expect(
      tabs.tabs.map((t) => t.deckNotifier.currentState.filePath).toList(),
      ['${dir.path}/alfa.md', '${dir.path}/charlie.md'],
    );
    expect(tabs.clampedIndex, 1);
  });
}
