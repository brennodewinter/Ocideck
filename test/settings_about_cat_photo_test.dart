import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De kattenfoto's in "Over OciDeck" staan als smalle strook in de kaart; een
/// klik moet de foto op ware grootte tonen. Deze test bewaakt die klikroute.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('een klik op een kattenfoto opent de zoomweergave', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();

    const tooltip = 'Bekijk de foto op ware grootte';
    await tester.scrollUntilVisible(
      find.byTooltip(tooltip).first,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    // Drie mascottes, dus drie klikbare foto's.
    expect(find.byTooltip(tooltip), findsNWidgets(3));

    await tester.tap(find.byTooltip(tooltip).first);
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    // Het onderschrift noemt de kat; Branie staat bovenaan.
    expect(find.text('Branie'), findsWidgets);

    // Esc brengt je terug naar het venster.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
