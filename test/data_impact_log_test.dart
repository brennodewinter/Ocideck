import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/data_impact_log.dart';
import 'package:ocideck/widgets/dialogs/settings/data_impact_log_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  test(
    'audit retains the latest 200 events with notice version and UTC time',
    () async {
      for (var i = 0; i < 205; i++) {
        await DataImpactLog.record(
          'module.ai',
          i.isEven ? 'shown' : 'accepted',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      final events = prefs
          .getStringList(DataImpactLog.key)!
          .map((s) => jsonDecode(s) as Map)
          .toList();
      expect(events, hasLength(200));
      expect(events.first['decision'], 'accepted');
      expect(events.last['decision'], 'shown');
      expect(
        events.every(
          (e) =>
              e['id'] == 'module.ai' &&
              e['version'] == 1 &&
              (e['at'] as String).endsWith('Z'),
        ),
        isTrue,
      );
    },
  );

  testWidgets('consent log displays and copies the recorded decision', (
    tester,
  ) async {
    await DataImpactLog.record('module.ai', 'shown');
    await DataImpactLog.record('module.ai', 'accepted');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
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
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DataImpactLogSection()),
        ),
      ),
    );
    await tester.tap(find.text('Toestemmingslogboek'));
    await tester.pumpAndSettle();
    final visible = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(visible, contains('"decision":"accepted"'));
    expect(visible, contains('"id":"module.ai"'));
    await tester.tap(find.text('Kopiëren'));
    await tester.pumpAndSettle();
    expect(copied, contains('"decision":"accepted"'));
    expect(copied, contains('"version":1'));
  });
}
