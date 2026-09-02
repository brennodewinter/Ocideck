import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/open_presentation_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1927: twee keer Ctrl/Cmd+O achter elkaar stapelde twee openen-dialogen.
///
/// De routewissel van `showDialog` is pas in de volgende frame in de
/// focusboom te zien, dus een tweede toetsaanslag binnen datzelfde frame komt
/// nog bij de app-brede binding aan — precies wat er gebeurt als je de
/// sneltoets twee keer snel indrukt.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
  }

  /// Twee aanslagen zonder frame ertussen: de dialoog is dan nog niet in de
  /// focusboom verwerkt, dus beide komen bij dezelfde binding aan.
  Future<void> pressOpenTwice(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('twee keer Ctrl+O opent één openen-dialoog', (tester) async {
    await pumpShell(tester);

    await pressOpenTwice(tester, LogicalKeyboardKey.controlLeft);

    expect(find.byType(OpenPresentationDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('twee keer Cmd+O opent één openen-dialoog', (tester) async {
    await pumpShell(tester);

    await pressOpenTwice(tester, LogicalKeyboardKey.metaLeft);

    expect(find.byType(OpenPresentationDialog), findsOneWidget);
  });

  testWidgets('na sluiten opent de sneltoets de dialoog opnieuw', (
    tester,
  ) async {
    await pumpShell(tester);

    await pressOpenTwice(tester, LogicalKeyboardKey.controlLeft);
    expect(find.byType(OpenPresentationDialog), findsOneWidget);

    // De bewaking mag zich niet vastzetten: sluiten en opnieuw openen hoort
    // gewoon te werken.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(OpenPresentationDialog), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(OpenPresentationDialog), findsOneWidget);
  });
}
