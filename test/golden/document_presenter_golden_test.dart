@Tags(['golden'])
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

const _surfaceKey = ValueKey('document-presenter-golden-surface');

const _doc = '''
# Risicoanalyse meldkamer

De beoordeling van 2026-06-30 door het team.

| Risico | Kans | Impact | Score |
| --- | --- | --- | --- |
| Brand in de serverruimte | 2 | 5 | 10 |
| Stroomuitval langer dan een dag | 3 | 4 | 12 |

---

# Aanpak

Maatregelen staan in het register.
''';

// De boundary staat bóven de MaterialApp zodat ook de Navigator-overlay —
// de afsluitdialoog — meekomt in de opname.
Widget _host() => RepaintBoundary(
  key: _surfaceKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Theme(
        data: AppTheme.fromProfile(AppAppearanceProfile.basic),
        child: const DocumentPresenterScreen(
          body: _doc,
          themeProfile: null,
          projectPath: null,
          editableTables: {0},
        ),
      ),
    ),
  ),
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('documentpresentatie: leesweergave van een pagina', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/document_presenter_page.png'),
    );
  });

  testWidgets('documentpresentatie: tabel in bewerkmodus', (tester) async {
    _size(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/document_presenter_edit.png'),
    );
  });

  testWidgets('documentpresentatie: afsluitkeuze na sessie-edit', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '10').first, '14');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/document_presenter_exit_choice.png'),
    );
  });
}
