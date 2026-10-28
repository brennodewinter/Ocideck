import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/diagnostics/diagnostics.dart';
import 'package:ocideck/services/diagnostics/log_file.dart';
import 'package:ocideck/utils/log.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';
import 'support/temp_dir.dart';

/// De kaart "Diagnose" in Over OciDeck (#2618): de route waarlangs een
/// gebruiker het logboek bij een melding voegt. "Diagnose kopiëren" moet een
/// plakklare tekst op het klembord zetten, en "Logmap openen" kan alleen als
/// er een logbestand is.
void main() {
  late Directory dir;
  String? clipboard;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
    dir = Directory.systemTemp.createTempSync('ocideck_diag_');
    clipboard = null;
  });

  tearDown(() async {
    Diagnostics.debugUse(null);
    await deleteTempDir(dir);
  });

  Future<void> openAbout(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
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
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(
                  context,
                  initialSection: SettingsSection.about,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Diagnose kopiëren'));
    await tester.pumpAndSettle();
  }

  testWidgets('Diagnose kopiëren zet een plakklaar rapport op het klembord', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Diagnostics.debugUse(LogFile.open(dir));
    });
    logWarning('Outbox: wachtende commit onleesbaar');
    await openAbout(tester);

    await tester.tap(find.text('Diagnose kopiëren'));
    // Het rapport leest het logbestand: echte schijf-IO, buiten de nepklok.
    final done = find.text('Diagnose gekopieerd naar het klembord.');
    await pumpUntil(
      tester,
      () => clipboard != null && done.evaluate().isNotEmpty,
      reason: 'het rapport kwam niet op het klembord',
    );

    expect(clipboard, startsWith('**OciDeck-diagnose**'));
    expect(clipboard, contains('WARN Outbox: wachtende commit onleesbaar'));
    expect(find.text('Diagnose gekopieerd naar het klembord.'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Logmap openen'),
              matching: find.bySubtype<OutlinedButton>(),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('zonder logbestand kan de logmap niet open', (tester) async {
    await openAbout(tester);
    final open = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Logmap openen'),
        matching: find.bySubtype<OutlinedButton>(),
      ),
    );
    expect(open.onPressed, isNull);
  });
}
