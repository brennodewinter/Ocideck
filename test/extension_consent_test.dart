import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/data_impact_log.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/widgets/dialogs/settings/extension_consent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  for (final accept in [true, false]) {
    testWidgets('AI activation requires consent: accepted=$accept', (
      tester,
    ) async {
      bool enabled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => consentToggle(
                  context,
                  ModuleId.ai,
                  (v) => enabled = v,
                )(true),
                child: const Text('enable'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('enable'));
      await tester.pumpAndSettle();
      expect(enabled, isFalse);
      expect(find.textContaining('persoonsgegevens'), findsOneWidget);
      await tester.tap(find.text(accept ? 'Doorgaan' : 'Annuleren'));
      await tester.pumpAndSettle();
      expect(enabled, accept);
      final events = (await SharedPreferences.getInstance())
          .getStringList(DataImpactLog.key)!
          .map((s) => jsonDecode(s) as Map)
          .toList();
      expect(events.map((e) => e['decision']), [
        'shown',
        accept ? 'accepted' : 'declined',
      ]);
      expect(
        events.every((e) => e['id'] == 'module.ai' && e['version'] == 1),
        isTrue,
      );
    });
  }

  testWidgets('dismissal refuses; disabling never asks', (tester) async {
    bool enabled = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => consentToggle(
                    context,
                    ModuleId.ai,
                    (v) => enabled = v,
                  )(true),
                  child: const Text('enable'),
                ),
                TextButton(
                  onPressed: () => consentToggle(
                    context,
                    ModuleId.ai,
                    (v) => enabled = v,
                  )(false),
                  child: const Text('disable'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('disable'));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('enable'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    final events = (await SharedPreferences.getInstance()).getStringList(
      DataImpactLog.key,
    )!;
    expect(jsonDecode(events.last)['decision'], 'declined');
  });

  test('offline reference and authoring modules need no outbound consent', () {
    expect(moduleRisk(ModuleId.elearning), isNull);
    for (final id in [
      ModuleId.ai,
      ModuleId.onlineStorage,
      ModuleId.collaboration,
      ModuleId.videoCalls,
      ModuleId.transcription,
      ModuleId.libreplan,
      ModuleId.forms,
    ]) {
      expect(moduleRisk(id), isNotEmpty);
    }
  });
}
