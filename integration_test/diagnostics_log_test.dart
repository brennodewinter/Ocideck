// Integratietest: het logbestand (#2618) in een echte app-engine, in de échte
// app-supportmap van dít platform.
//
// ── Waarom dit bestaat naast test/log_file_test.dart ─────────────────────────
//
// De unit-tests bewijzen rotatie, sanering en de sessiemarkering in een
// tijdelijke map op de Dart-VM. Wat ze niet kunnen zien, is precies waar het
// logbestand voor bestaat: of het op Windows werkelijk geschreven wordt — in
// `%APPDATA%`, met de virusscanner ertussen, met een hernoeming over een
// bestaand bestand bij rotatie — en of het eerste frame daar echt valt. Deze
// test draait als app op het platform zelf, net als bij de gebruiker.
//
// Draaien:
//   flutter test integration_test/diagnostics_log_test.dart -d macos
//   flutter test integration_test/diagnostics_log_test.dart -d windows
//   flutter test integration_test/diagnostics_log_test.dart -d linux

import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/services/diagnostics/diagnostics.dart';
import 'package:ocideck/services/diagnostics/ui_stall_watch.dart';
import 'package:ocideck/utils/log.dart';
import 'package:path/path.dart' as p;

const _name = 'integratietest';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mijlpalen, eerste frame en een stallregel landen op schijf', (
    tester,
  ) async {
    await Diagnostics.start(name: _name);
    final dir = Diagnostics.logDirectory;
    expect(
      dir,
      isNotNull,
      reason:
          'geen app-supportmap, of het logbestand '
          'kon er niet worden aangemaakt',
    );
    addTearDown(() {
      for (final f in dir!.listSync().whereType<File>()) {
        if (p.basename(f.path).startsWith('$_name.')) f.deleteSync();
      }
    });
    logMilestone('main');

    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: Text('x')),
    );
    await tester.binding.waitUntilFirstFrameRasterized.timeout(
      const Duration(seconds: 30),
    );
    logMilestone('eerste frame');
    Diagnostics.firstFrameShown();

    // Een eigen melder die de venstertoestand niet vraagt: op een CI-runner kan
    // het venster op de achtergrond staan, en dan zou de echte melder de
    // blokkade terecht negeren.
    final watch = UiStallWatch(lifecycle: () => AppLifecycleState.resumed)
      ..start();
    addTearDown(watch.stop);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    noteWork('integratietest-blokkade');
    final busy = Stopwatch()..start();
    while (busy.elapsedMilliseconds < 800) {}
    await Future<void>.delayed(const Duration(milliseconds: 700));

    await closeLog();
    final log = File(p.join(dir!.path, '$_name.log')).readAsStringSync();
    expect(log, contains('INFO sessie: OciDeck '));
    expect(log, contains('opstart: main'));
    expect(log, contains('opstart: eerste frame'));
    expect(log, contains('werk: integratietest-blokkade'));
    expect(
      File(p.join(dir.path, '$_name.sessie')).existsSync(),
      isFalse,
      reason: 'een nette afsluiting haalt de sessiemarkering weg',
    );
  });
}
