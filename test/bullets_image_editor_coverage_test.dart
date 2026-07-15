import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/bullets_image_editor.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';

/// Behaviour coverage for [BulletsImageEditor]: title, list-style switching,
/// bullet-marker override, add/remove/reorder/paste of bullets, checklist +
/// numbering toggles, the image zoom control and the image bar's callbacks.
const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  FlutterQuillLocalizations.delegate,
];

/// The image bar is a Riverpod `ConsumerWidget`, so the editor needs a
/// `ProviderScope` and a bounded canvas (the reorderable/list children have no
/// intrinsic height).
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 1400, height: 2000, child: child)),
  ),
);

/// Stubs the picker/paste channels so `_pickImage` / `_pasteImage` resolve to a
/// known path without touching a real file dialog or the clipboard.
class _FakeImageService extends ImageService {
  final String? pickedPath;
  final String? pastedPath;

  _FakeImageService({this.pickedPath, this.pastedPath});

  @override
  Future<ImageImportOutcome> pickImageDetailed({String? projectPath}) async =>
      pickedPath == null
      ? const ImageImportOutcome.failed(ImageImportFailure.cancelled)
      : ImageImportOutcome.success(pickedPath!);

  @override
  Future<ImageImportOutcome> pasteImageDetailed({String? projectPath}) async =>
      pastedPath == null
      ? const ImageImportOutcome.failed(ImageImportFailure.noClipboardImage)
      : ImageImportOutcome.success(pastedPath!);
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Slide bulletsImage({
    List<String> bullets = const ['Punt'],
    ListStyle listStyle = ListStyle.bullets,
    String imagePath = '',
  }) => Slide.create(
    SlideType.bulletsImage,
  ).copyWith(bullets: bullets, listStyle: listStyle, imagePath: imagePath);

  testWidgets('editing the title emits the new title', (tester) async {
    var updated = bulletsImage();
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Mijn slide');
    await tester.pump();
    expect(updated.title, 'Mijn slide');
  });

  testWidgets('list-style + bullet-marker selectors drive the slide', (
    tester,
  ) async {
    var updated = bulletsImage();
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );

    // Bullets mode → the marker override picker is offered.
    expect(find.text('Opsommingsteken'), findsOneWidget);
    await tester.tap(find.text('Pootje'));
    await tester.pump();
    expect(updated.bulletMarkerOverride, BulletMarker.paw);
    await tester.tap(find.text('Stip'));
    await tester.pump();
    expect(updated.bulletMarkerOverride, BulletMarker.dot);
    await tester.tap(find.text('Thema'));
    await tester.pump();
    expect(updated.bulletMarkerOverride, isNull);

    // Numbered → the marker picker disappears; numbered markers render.
    await tester.tap(find.text('Nummering'));
    await tester.pumpAndSettle();
    expect(updated.listStyle, ListStyle.numbered);
    expect(find.text('Opsommingsteken'), findsNothing);
    expect(find.text('1.'), findsOneWidget);

    // Rich text → markdown editor, bullet controls gone.
    await tester.tap(find.text('Teksteditor'));
    await tester.pumpAndSettle();
    expect(updated.listStyle, ListStyle.richText);
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    expect(find.text('Bullet toevoegen'), findsNothing);

    // Back to plain bullets.
    await tester.tap(find.text('Opsomming'));
    await tester.pumpAndSettle();
    expect(updated.listStyle, ListStyle.bullets);
  });

  testWidgets('rich-text edits emit customMarkdown', (tester) async {
    var updated = bulletsImage(listStyle: ListStyle.richText);
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    // The legacy markdown editor defaults to a WYSIWYG view, so drive its
    // controller directly — its listener is what emits customMarkdown.
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    final editor = tester.widget<MarkdownNotesEditor>(
      find.byType(MarkdownNotesEditor),
    );
    editor.controller.text = 'Vrije tekst';
    await tester.pump();
    expect(updated.customMarkdown, 'Vrije tekst');
  });

  testWidgets('add / remove / reset bullets', (tester) async {
    var updated = bulletsImage(bullets: const ['Een']);
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    // Add a bullet via the bottom button.
    await tester.tap(find.text('Bullet toevoegen'));
    await tester.pump();
    expect(updated.bullets.length, 2);

    // Remove the second one again.
    await tester.tap(find.byKey(const ValueKey('remove-bullet-1')));
    await tester.pump();
    expect(updated.bullets.length, 1);

    // Removing the last remaining bullet clears it rather than deleting it.
    await tester.tap(find.byKey(const ValueKey('remove-bullet-0')));
    await tester.pump();
    expect(updated.bullets, const ['']);
  });

  testWidgets('reordering rows moves the matching bullet', (tester) async {
    var updated = bulletsImage(bullets: const ['A', 'B', 'C']);
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    // The patched ReorderableListView pre-adjusts newIndex, so moving row 0 to
    // index 2 lands it after the others.
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(0, 2);
    await tester.pump();
    expect(updated.bullets, const ['B', 'C', 'A']);
  });

  testWidgets('multi-line clipboard paste splits into separate bullets', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'Regel een\nRegel twee\nRegel drie'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    var updated = bulletsImage(bullets: const ['Punt']);
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    // Focus the (only) bullet field — index 0 is the title.
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(updated.bullets, const ['Regel een', 'Regel twee', 'Regel drie']);
  });

  testWidgets('single-line paste inserts into the focused bullet', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'Enkele regel'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    var updated = bulletsImage(bullets: const ['']);
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(updated.bullets, const ['Enkele regel']);
  });

  testWidgets('keyboard: Enter adds, Tab indents, Backspace removes', (
    tester,
  ) async {
    var updated = bulletsImage(bullets: const ['Een']);
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    // Enter at the end of a bullet appends a new one.
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(updated.bullets.length, 2);

    // Tab indents the first bullet one level (a leading tab).
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(updated.bullets.first.startsWith('\t'), isTrue);

    // Backspace on the empty trailing bullet removes it.
    await tester.tap(find.byType(TextField).at(2));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(updated.bullets.length, 1);
  });

  testWidgets('checklist mode: item toggle + progress switch', (tester) async {
    var updated = bulletsImage(
      bullets: const ['Taak een', 'Taak twee'],
      listStyle: ListStyle.checklist,
    );
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    // The only Switch in checklist mode is the progress toggle.
    expect(find.text('Voortgangsgrafiek tonen'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(updated.showChecklistProgress, isTrue);

    // Ticking the first item's checkbox marks it done.
    await tester.tap(find.byKey(const ValueKey('checklist-item-0')));
    await tester.pump();
    expect(checklistItemChecked(updated.bullets.first), isTrue);
  });

  testWidgets(
    'continue-numbering toggle appears for a numbered split continuation',
    (tester) async {
      var updated = bulletsImage(
        bullets: const ['Zesde', 'Zevende'],
        listStyle: ListStyle.numbered,
      );
      await tester.pumpWidget(
        _host(
          BulletsImageEditor(
            slide: updated,
            onUpdate: (s) => updated = s,
            imageService: ImageService(),
            previousSlideIsNumbered: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Doornummeren vanaf vorige slide'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(updated.continueNumbering, isTrue);
    },
  );

  testWidgets('image zoom control changes the panel width', (tester) async {
    // No image path keeps the panel short enough that the zoom control stays
    // within the lazy list's viewport.
    var updated = bulletsImage();
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(60.0);
    await tester.pump();
    expect(updated.imageSize, 60);
  });

  testWidgets('image bar callbacks update the slide', (tester) async {
    var updated = bulletsImage(imagePath: 'foto.png');
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    final bar = tester.widget<ImagePickerBar>(find.byType(ImagePickerBar));

    // Carousel/library pick reports path + caption.
    bar.onPicked('nieuw.png', 'Bijschrift');
    expect(updated.imagePath, 'nieuw.png');
    expect(updated.imageCaption, 'Bijschrift');

    // Manual caption edit.
    bar.onCaptionChanged!('© Fotograaf');
    expect(updated.imageCaption, '© Fotograaf');

    // A human alt-text edit is not an AI draft.
    bar.onAltTextChanged!('Beschrijving');
    expect(updated.imageAltText, 'Beschrijving');
    expect(updated.aiAssistedFields.contains('imageAltText'), isFalse);

    // An AI-suggested alt-text carries the provenance marker...
    bar.onAltTextSuggested!('AI beschrijving');
    expect(updated.imageAltText, 'AI beschrijving');
    expect(updated.aiAssistedFields.contains('imageAltText'), isTrue);

    // ...which "reviewed" then clears.
    // Re-read the bar so it reflects the AI-draft slide before accepting.
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();
    tester
        .widget<ImagePickerBar>(find.byType(ImagePickerBar))
        .onAltTextAccepted!();
    expect(updated.aiAssistedFields.contains('imageAltText'), isFalse);

    // Clear removes the image and its caption.
    tester.widget<ImagePickerBar>(find.byType(ImagePickerBar)).onClear!();
    expect(updated.imagePath, '');
    expect(updated.imageCaption, '');
  });

  testWidgets('the image bar renders caption + alt-text fields for an image', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: bulletsImage(imagePath: 'foto.png'),
          onUpdate: (_) {},
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    // The path is shown, and the caption + alt-text + copy/clear controls exist.
    expect(find.text('foto.png'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);
  });

  testWidgets('browse and paste image import through the service', (
    tester,
  ) async {
    var updated = bulletsImage();
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: _FakeImageService(
            pickedPath: 'gekozen.png',
            pastedPath: 'geplakt.png',
          ),
        ),
      ),
    );
    await tester.pump();

    // "Van computer…" runs the file-picker path.
    await tester.tap(find.text('Van computer…'));
    await tester.pumpAndSettle();
    expect(updated.imagePath, 'gekozen.png');

    // The paste icon runs the clipboard-image path.
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pumpAndSettle();
    expect(updated.imagePath, 'geplakt.png');
  });
}
