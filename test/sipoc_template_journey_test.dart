import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/template_content_service.dart';
import 'package:ocideck/widgets/presentation/audience_window.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/export_bundle_fixture.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
  FlutterQuillLocalizations.delegate,
];

Widget _app(Widget home) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: _delegates,
  home: home,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String path;
  late Deck reopened;
  late Slide reopenedMatrix;
  late int reopenedIndex;
  late List<List<String>> filledRows;
  late String markdown;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final slides = await TemplateContentService().loadSlides(
      'procesverbetering-sipoc',
      languageCode: 'nl',
      deckTitle: 'SIPOC intake',
    );
    final matrixIndex = slides.indexWhere(
      (slide) => slide.type == SlideType.matrix,
    );
    final matrix = slides[matrixIndex];
    filledRows = <List<String>>[
      matrix.tableRows.first,
      for (var row = 1; row <= 7; row++)
        [
          'Leverancier $row',
          'Input $row',
          'Processtap $row',
          'Output $row',
          'Klant $row',
        ],
    ];
    slides[matrixIndex] = matrix.copyWith(tableRows: filledRows);
    final deck = Deck(title: 'SIPOC intake', language: 'nl', slides: slides);
    temp = await Directory.systemTemp.createTemp('ocideck_sipoc_');
    path = p.join(temp.path, 'sipoc.md');
    final files = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    await files.saveDeck(deck, path);
    reopened = (await files.openDeck(path))!;
    reopenedIndex = reopened.slides.indexWhere(
      (slide) => slide.type == SlideType.matrix,
    );
    reopenedMatrix = reopened.slides[reopenedIndex];
    markdown = MarkdownService().generateDeck(reopened);
  });

  tearDownAll(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('seven rows survive reopen and enter the matrix output', () {
    expect(reopenedMatrix.improvementTemplateId, 'sipoc');
    expect(reopenedMatrix.tableRows, filledRows);

    final rendered = renderMatrixSlide(
      MarpHtmlService.marpSlides(
        MarkdownService().generateDeck(
          Deck(title: 'SIPOC', slides: [reopenedMatrix]),
        ),
      ).single,
    );
    expect(rendered, contains('<svg'));
    expect(rendered, contains('Leverancier 7'));
    expect(rendered, contains('Klant 7'));
  });

  testWidgets('preview renders and feeds real PDF and HTML exports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 960,
                height: 540,
                child: SlidePreviewWidget(slide: reopenedMatrix),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final png = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }))!;
    expect(png, isNotEmpty);

    final outputs = (await tester.runAsync(() async {
      final exports = ExportService(
        htmlService: MarpHtmlService(
          loadAsset: (asset) => File(asset).readAsString(),
        ),
      );
      final pdf = await exports.export(path, ExportFormat.pdf, [
        png,
      ], outputDirectory: temp.path);
      final html = await exports.export(
        path,
        ExportFormat.html,
        const <Uint8List>[],
        outputDirectory: temp.path,
        audience: bundleFor(reopened, markdown: markdown),
      );
      return (
        pdf: pdf,
        pdfBytes: pdf.success
            ? await File(pdf.outputPath!).readAsBytes()
            : <int>[],
        html: html,
        htmlText: html.success
            ? await File(html.outputPath!).readAsString()
            : '',
      );
    }))!;
    final pdf = outputs.pdf;
    expect(pdf.success, isTrue, reason: pdf.error);
    expect(
      outputs.pdfBytes.take(4).toList(),
      <int>[0x25, 0x50, 0x44, 0x46], // %PDF
    );

    final html = outputs.html;
    expect(html.success, isTrue, reason: html.error);
    final htmlText = outputs.htmlText;
    expect(htmlText, startsWith('<!doctype html>'));
    expect(htmlText, contains('Leverancier 7'));
    expect(htmlText, contains('Klant 7'));
  });

  testWidgets('thumbnail renders the reopened seven-row matrix', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _app(
          Scaffold(
            body: SizedBox(
              width: 260,
              height: 260,
              child: SlideThumbnail(
                slide: reopenedMatrix,
                index: 0,
                slideCount: 1,
                reportLanguage: reopened.language,
                onTap: () {},
                onDuplicate: () {},
                onDelete: () {},
                onToggleSkip: () {},
                onCopyImage: () {},
                onSplit: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SlideThumbnail), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('presenter renders the reopened seven-row matrix', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        FullscreenPresenter(
          slides: reopened.slides,
          projectPath: null,
          themeProfile: const ThemeProfile(),
          reportLanguage: reopened.language,
          initialIndex: reopenedIndex,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(FullscreenPresenter), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('audience window renders the reopened seven-row matrix', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AudienceWindowApp(
        args: <String, dynamic>{'markdown': markdown, 'index': reopenedIndex},
      ),
    );
    await tester.pump();
    expect(find.byType(AudienceWindowApp), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
