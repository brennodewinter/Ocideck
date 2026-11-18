import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

/// "Zoek op deze computer" op het welkomstscherm: `_scanLibrary` in
/// `lib/widgets/shell/shell_actions_pickers.dart` opent de
/// `ScanLibraryDialog`, neemt het gekozen pad over en voert het door de
/// gedeelde openroute (media-classificatie vóór `openFileByPath`, #2932).
/// De scan draait tegen een echte FileService op een temp-home met één
/// recent bestand — hetzelfde harnas als `scan_dialogs_smoke_test`.
void main() {
  late Directory tmp;
  late String demoPath;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_scan');
    // De scan levert het platformpad terug; gemengde scheidingstekens laten
    // de tekstvergelijking op Windows onterecht op een time-out uitlopen.
    demoPath = p.join(tmp.path, 'demo.md');
    File(demoPath).writeAsStringSync('# Bibliotheekdemo\n');
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'recentFiles': [demoPath],
      'storageConnections': jsonEncode([
        LocalConnection(
          id: 'lokaal',
          name: 'Mijn presentaties',
          path: tmp.path,
        ).toJson(),
      ]),
    });
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('een gevonden bibliotheekbestand opent als tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );

    await tester.tap(find.text('Zoek op deze computer'));
    await tester.pump();
    // De dialoog scant echte mappen; wacht tot de voortgang wegvalt in
    // plaats van op een klok.
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de bibliotheekscan bleef laden',
    );

    await tester.tap(find.text('Bibliotheekdemo'));
    await pumpUntil(
      tester,
      () => container.read(tabsProvider).current?.openFilePath == demoPath,
      reason: 'het gekozen bestand opende niet als tab',
    );
  });
}
