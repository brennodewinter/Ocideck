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
import 'package:ocideck/widgets/dialogs/slide_diff_dialog.dart';
import 'package:ocideck/widgets/dialogs/slide_finder_dialog.dart';

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

/// Opens [dialog], lets its on-disk scan complete, and types [query] into the
/// search box. The whole flow runs inside [WidgetTester.runAsync] so the
/// dialog's real file-I/O scan actually resolves (a fake-async pump never lets
/// dart:io futures complete). [then] runs one more interaction before settling.
Future<void> _openAndSearch(
  WidgetTester tester, {
  required void Function(BuildContext context) show,
  required String query,
  Future<void> Function()? then,
}) async {
  await tester.binding.setSurfaceSize(const Size(1800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.runAsync(() async {
    await tester.pumpWidget(_host(show));
    await tester.tap(find.text('open'));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 400)); // scan
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, query);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    if (then != null) await then();
  });
  await tester.pump();
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dedup_dialogs_');
    // Deck A: a "Netwerksegmentatie" slide (S).
    File('${dir.path}/deck_a.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Deck A\n---\n\n'
      '# Titel A\n\n'
      '---\n\n'
      '# Netwerksegmentatie\n\n- In scope\n',
    );
    // Deck B: a byte-identical copy of S (must de-duplicate away) plus a
    // same-title variant (a look-alike, so a "Verschillen" action appears).
    File('${dir.path}/deck_b.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Deck B\n---\n\n'
      '# Netwerksegmentatie\n\n- In scope\n\n'
      '---\n\n'
      '# Netwerksegmentatie\n\n- Out of scope\n',
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void showFinder(BuildContext context) => SlideFinderDialog.show(
    context,
    fileService: _fileService(dir.path),
    initialDirectory: dir.path,
    onAdd: (Slide _) {},
  );

  testWidgets('Slide zoeken toont een identieke slide één keer met een teller', (
    tester,
  ) async {
    await _openAndSearch(tester, show: showFinder, query: 'Netwerksegmentatie');

    // The identical slide (deck A · slide 2 and deck B · slide 1) collapses to
    // one card carrying the "copies" badge; the summary reports one hidden dupe.
    expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);
    expect(find.textContaining('verborgen'), findsOneWidget);
  });

  testWidgets('Slide zoeken markeert gelijkende slides met "Verschillen"', (
    tester,
  ) async {
    await _openAndSearch(tester, show: showFinder, query: 'Netwerksegmentatie');

    // S and the "Out of scope" variant share a title → both offer a compare.
    expect(find.text('Verschillen'), findsNWidgets(2));
  });

  testWidgets('"Verschillen" opent een vergelijking met het afwijkende veld', (
    tester,
  ) async {
    await _openAndSearch(
      tester,
      show: showFinder,
      query: 'Netwerksegmentatie',
      then: () async {
        await tester.tap(find.text('Verschillen').first);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      },
    );

    expect(find.byType(SlideDiffDialog), findsOneWidget);
    // The bullets differ (In scope vs Out of scope), so the list names them.
    expect(find.text('Opsomming'), findsOneWidget);
    expect(find.textContaining('Out of scope'), findsWidgets);
  });

  testWidgets('Slides importeren ontdubbelt identieke slides over decks heen', (
    tester,
  ) async {
    await _openAndSearch(
      tester,
      show: (context) => ImportSlidesDialog.show(
        context,
        fileService: _fileService(dir.path),
        initialDirectory: dir.path,
      ),
      query: 'Netwerksegmentatie',
    );

    // The identical slide is shown once with a badge; the look-alike variant
    // offers a compare.
    expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);
    expect(find.text('Verschillen'), findsWidgets);
  });
}
