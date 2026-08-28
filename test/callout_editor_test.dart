import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/editors/callout_editor.dart';

/// Widget tests for [CalloutEditorDialog] — verifies the dialog renders with
/// its title, shows the slide's bullets, and has an add-callout button.

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: _delegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// The dialog content is 900×600, wider than the default 800×600 test surface.
Future<void> _setSurface(WidgetTester tester) =>
    tester.binding.setSurfaceSize(const Size(1200, 800));

/// A minimal valid 1×1 transparent PNG.
final _pngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ),
);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  testWidgets('dialog renders with title Afbeeldingsverwijzingen', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt', 'Tweede punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Afbeeldingsverwijzingen'), findsOneWidget);
  });

  testWidgets('bullet list shows bullets', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt', 'Tweede punt', 'Derde punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Eerste punt'), findsOneWidget);
    expect(find.text('Tweede punt'), findsOneWidget);
    expect(find.text('Derde punt'), findsOneWidget);
  });

  testWidgets('add callout button exists', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    // The "Toevoegen" (Add) button is shown for bullets without a callout.
    expect(find.text('Toevoegen'), findsOneWidget);
  });

  testWidgets('clicking add assigns a callout and emits via onUpdate', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Tap "Toevoegen" to add a callout to the first bullet.
    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();

    // The callout is emitted via onUpdate with reference 'A'.
    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.reference, 'A');
  });

  testWidgets('close button dismisses the dialog', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sluiten'), findsOneWidget);
    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.text('Afbeeldingsverwijzingen'), findsNothing);
  });

  testWidgets('presentation mode toggle exists (Pins / Gebieden)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pins'), findsOneWidget);
    expect(find.text('Gebieden'), findsOneWidget);
  });

  testWidgets('adding callout in region mode creates a CalloutRegion', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      calloutPresentation: CalloutPresentation.region,
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Switch to region mode.
    await tester.tap(find.text('Gebieden'));
    await tester.pumpAndSettle();

    // Tap "Toevoegen" to add a callout.
    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();

    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.targets.first, isA<CalloutRegion>());
    expect(updated.calloutPresentation, CalloutPresentation.region);
  });

  testWidgets('adding callout in pin mode creates a CalloutPoint', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();

    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.targets.first, isA<CalloutPoint>());
  });
}
