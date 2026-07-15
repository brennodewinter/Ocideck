import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/title_editor.dart';

/// Behaviour coverage for [TitleEditor]: it edits a title slide's title and
/// subtitle, and — once a background image is set — its "fill slide" toggle,
/// grey-veil overlay toggle and the title-text-colour override chips.
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 1200, height: 2600, child: child)),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is EditorField && w.label == label),
    matching: find.byType(TextField),
  );

  Future<Slide? Function()> pump(WidgetTester tester, Slide slide) async {
    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(TitleEditor(slide: slide, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

  Slide titleWithImage() => Slide.create(
    SlideType.title,
  ).copyWith(imagePath: 'images/test.png', imageSize: 120);

  testWidgets('renders the title and subtitle fields', (tester) async {
    await pump(tester, Slide.create(SlideType.title));

    expect(fieldByLabel('Titel (H1)'), findsOneWidget);
    expect(fieldByLabel('Subtitel (H2)'), findsOneWidget);
  });

  testWidgets('typing the title emits an updated slide', (tester) async {
    final latest = await pump(tester, Slide.create(SlideType.title));

    await tester.enterText(fieldByLabel('Titel (H1)'), 'Mijn presentatie');
    await tester.pump();

    expect(latest()!.title, 'Mijn presentatie');
  });

  testWidgets('typing the subtitle emits an updated slide', (tester) async {
    final latest = await pump(tester, Slide.create(SlideType.title));

    await tester.enterText(fieldByLabel('Subtitel (H2)'), 'Een ondertitel');
    await tester.pump();

    expect(latest()!.subtitle, 'Een ondertitel');
  });

  testWidgets('image controls appear once a background image is set', (
    tester,
  ) async {
    await pump(tester, titleWithImage());

    expect(find.text('Afbeelding vult hele slide'), findsOneWidget);
    expect(find.text('Grijze waas over afbeelding'), findsOneWidget);
    expect(find.text('Titeltekstkleur'), findsOneWidget);
  });

  testWidgets('the grey-veil overlay checkbox toggles titleImageOverlay', (
    tester,
  ) async {
    // titleImageOverlay defaults to true; tapping the checkbox turns it off.
    final latest = await pump(tester, titleWithImage());

    await tester.tap(
      find.ancestor(
        of: find.text('Grijze waas over afbeelding'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    await tester.pump();

    expect(latest()!.titleImageOverlay, isFalse);
  });

  testWidgets('the title-text-colour chips set the override', (tester) async {
    final latest = await pump(tester, titleWithImage());

    await tester.tap(find.widgetWithText(ChoiceChip, 'Licht'));
    await tester.pump();
    expect(latest()!.titleTextColorOverride, '#FFFFFF');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Donker'));
    await tester.pump();
    expect(latest()!.titleTextColorOverride, '#111827');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Thema'));
    await tester.pump();
    expect(latest()!.titleTextColorOverride, '');
  });

  testWidgets('"fill slide" on turns imageSize to 0 (cover)', (tester) async {
    final latest = await pump(tester, titleWithImage());

    await tester.tap(
      find.ancestor(
        of: find.text('Afbeelding vult hele slide'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    await tester.pump();

    expect(latest()!.imageSize, 0);
  });

  testWidgets('"fill slide" off restores a zoom value', (tester) async {
    // Starting from a filled image (imageSize 0), turning the toggle off
    // restores the default 100% zoom.
    final latest = await pump(
      tester,
      Slide.create(SlideType.title).copyWith(imagePath: 'images/test.png'),
    );

    await tester.tap(
      find.ancestor(
        of: find.text('Afbeelding vult hele slide'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    await tester.pump();

    expect(latest()!.imageSize, 100);
    expect(tester.takeException(), isNull);
  });
}
