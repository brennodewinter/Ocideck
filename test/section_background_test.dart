import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/markdown_editor_field.dart';
import 'package:ocideck/widgets/editors/section_editor.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// De tussentitel draagt nu dezelfde achtergrondafbeelding als de titeldia. Deze
/// test dekt beide kanten: de editor toont de beeldbediening zodra er een beeld
/// staat, en de preview rendert de dia in beide modi (schermvullend en met een
/// band eronder) zonder te struikelen.
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 1200, height: 2600, child: child)),
  ),
);

Slide _sectionWithImage() => Slide.create(
  SlideType.section,
).copyWith(title: 'Deel twee', imagePath: 'images/test.png', imageSize: 120);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  group('SectionEditor background image', () {
    Finder fieldByLabel(String label) => find.descendant(
      of: find.byWidgetPredicate(
        (w) =>
            (w is EditorField && w.label == label) ||
            (w is MarkdownEditorField && w.label == label),
      ),
      matching: find.byType(TextField),
    );

    Future<Slide? Function()> pump(WidgetTester tester, Slide slide) async {
      Slide? updated;
      await tester.binding.setSurfaceSize(const Size(1200, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(SectionEditor(slide: slide, onUpdate: (s) => updated = s)),
      );
      await tester.pumpAndSettle();
      return () => updated;
    }

    testWidgets('shows the two text fields', (tester) async {
      await pump(tester, Slide.create(SlideType.section));
      expect(fieldByLabel('Tussentitel (H1)'), findsOneWidget);
      expect(fieldByLabel('Ondertitel / toelichting'), findsOneWidget);
    });

    testWidgets('image controls appear once a background image is set', (
      tester,
    ) async {
      await pump(tester, _sectionWithImage());
      expect(find.text('Afbeelding vult hele slide'), findsOneWidget);
      expect(find.text('Grijze waas over afbeelding'), findsOneWidget);
      expect(find.text('Titeltekstkleur'), findsOneWidget);
    });

    testWidgets('the grey-veil checkbox toggles titleImageOverlay', (
      tester,
    ) async {
      final latest = await pump(tester, _sectionWithImage());
      await tester.tap(
        find.ancestor(
          of: find.text('Grijze waas over afbeelding'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      await tester.pump();
      expect(latest()!.titleImageOverlay, isFalse);
    });

    testWidgets('the text-colour chips set the override', (tester) async {
      final latest = await pump(tester, _sectionWithImage());
      await tester.tap(find.widgetWithText(ChoiceChip, 'Licht'));
      await tester.pump();
      expect(latest()!.titleTextColorOverride, '#FFFFFF');
    });

    testWidgets('"fill slide" on turns imageSize to 0', (tester) async {
      final latest = await pump(tester, _sectionWithImage());
      await tester.tap(
        find.ancestor(
          of: find.text('Afbeelding vult hele slide'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      await tester.pump();
      expect(latest()!.imageSize, 0);
    });
  });

  group('_SectionPreview background image', () {
    Future<void> pumpPreview(WidgetTester tester, Slide slide) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 1280,
                height: 720,
                child: SlidePreviewWidget(
                  slide: slide,
                  themeProfile: const ThemeProfile(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('renders full-bleed (imageSize 0) with the veil, no crash', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        _sectionWithImage().copyWith(imageSize: 0, titleImageOverlay: true),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SlidePreviewWidget), findsOneWidget);
    });

    testWidgets('renders the top-zone band (imageSize != 0), no crash', (
      tester,
    ) async {
      await pumpPreview(tester, _sectionWithImage().copyWith(imageSize: 120));
      expect(tester.takeException(), isNull);
      expect(find.byType(SlidePreviewWidget), findsOneWidget);
    });
  });
}
