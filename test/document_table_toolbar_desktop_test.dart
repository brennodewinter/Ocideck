import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De tabelwerkbalk mag een desktop-muisklik overleven (#2140).
///
/// Op desktop unfocust `EditableText.onTapOutside` de cel al bij pointer-down;
/// de werkbalk-hold liep één frame later af terwijl pointer-up — en dus
/// `onPressed` — pas daarna komt. De werkbalk verdween onder de cursor en de
/// rij kwam er niet eens. Deze test meet met echte pointer-timing: down, een
/// paar frames, pas dan up.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('rij eronder via de werkbank: actie én focus blijven (#2140)', (
    tester,
  ) async {
    // De race bestaat alleen waar pointer-down de cel unfocust: desktop.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const doc =
        'Vooraf.\n\n| Naam | Waarde |\n| --- | --- |\n| Alfa | 1 |\n';
    final notifier = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse(doc));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentProvider.overrideWith((_) => notifier)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DocumentEditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Naar de Bron-stand: daar heeft de werkbalk geen Quill-TapRegion om zich
    // heen, dus unfocust pointer-down de cel — precies de kwetsbare route.
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is SegmentedButton),
        matching: find.text('Bron'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Focus een cel — dan verschijnt de werkbalk.
    final cell = find.descendant(
      of: find.byType(Table),
      matching: find.widgetWithText(TextField, 'Alfa'),
    );
    expect(cell, findsOneWidget);
    await tester.showKeyboard(cell);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Rij eronder'), findsOneWidget);

    // Een echte klik: down … een paar frames … pas dan up.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Rij eronder')),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byTooltip('Rij eronder'),
      findsOneWidget,
      reason: 'de werkbalk moet pointer-down overleven tot de knop vuurt',
    );
    await gesture.up();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // De rij is er één rijker en een tabelcel heeft de focus terug.
    final regels = notifier.currentState.document!.body
        .split('\n')
        .where((l) => l.startsWith('|'))
        .length;
    expect(regels, 4, reason: 'een rij erboven de bestaande drie regels');
    final cells = tester.widgetList<TextField>(
      find.descendant(of: find.byType(Table), matching: find.byType(TextField)),
    );
    expect(
      cells.any((f) => f.focusNode?.hasFocus ?? false),
      isTrue,
      reason: 'na de werkbalkactie staat de focus weer in een tabelcel',
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
