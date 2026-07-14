import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/privacy_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke test for the settings dialog. Its tab bodies are built into an
/// IndexedStack, so a single render exercises every tab; tapping the nav icons
/// then exercises the tab-selection path.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SettingsDialog renders and switches tabs', (tester) async {
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
    expect(find.byType(SettingsDialog), findsOneWidget);

    // Walk the navigation rail to exercise each tab's selection, including the
    // Security tab (shield) and the branded footer that opens "Over OciDeck".
    for (final icon in const [
      Icons.format_paint_outlined,
      Icons.slideshow_outlined,
      Icons.speed_outlined,
      Icons.privacy_tip_outlined,
      Icons.shield_outlined,
      Icons.cloud_outlined,
      Icons.info_outline,
      Icons.tune,
    ]) {
      final finder = find.byIcon(icon);
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder.first);
        await tester.pumpAndSettle();
      }
    }

    expect(find.byType(SettingsDialog), findsOneWidget);
  });

  // De CVE-schakelaar zet je bloot: de zoekterm gaat naar de mirror en bij een
  // misser ook naar ENISA en MITRE. De badge moet dat zichtbaar maken, náást de
  // schakelaar, en niet stilletjes verdwijnen als iemand de sectie herschikt.
  testWidgets('the CVE lookup toggle carries a privacy badge', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context, initialTab: 5),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Het Beveiliging-tabblad draagt er inmiddels twee: één bij de online
    // zoekopdracht (wat je prijsgeeft) en één bij de lokale database (dat je
    // dan niets meer prijsgeeft). Die van de online schakelaar moet de keten
    // benoemen die de zoekterm doorstuurt.
    final tooltips = tester
        .widgetList<PrivacyBadge>(find.byType(PrivacyBadge))
        .map((b) => b.tooltip)
        .toList();

    expect(tooltips, isNotEmpty);
    expect(
      tooltips.any((t) => t.contains('ENISA') && t.contains('MITRE')),
      isTrue,
      reason:
          'de badge bij de online CVE-schakelaar noemt de doorstuurketen niet',
    );
  });
}
