// Het logbestand van een desktopbuild (#2618): begrensd, roterend, en met een
// sessiemarkering die een niet-nette afsluiting bij de volgende start meldt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/diagnostics/diagnostics.dart';
import 'package:ocideck/services/diagnostics/log_file.dart';
import 'package:ocideck/utils/log.dart';
import 'package:path/path.dart' as p;

import 'support/temp_dir.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ocideck_log_'));

  tearDown(() async {
    installLogSink(null);
    await deleteTempDir(dir);
  });

  File file(String name) => File(p.join(dir.path, name));

  String line(int i) => 'regel ${i.toString().padLeft(4, '0')}\n';

  test('tot het eerste frame staat elke regel meteen op schijf', () {
    final log = LogFile.open(dir);
    log.write(line(1));
    expect(file('ocideck.log').readAsStringSync(), line(1));
  });

  test('roteert bij de grens en houdt nooit meer dan twee bestanden', () {
    final log = LogFile.open(dir, maxBytes: 200);
    for (var i = 0; i < 100; i++) {
      log.write(line(i));
    }
    final names = dir.listSync().map((e) => p.basename(e.path)).toSet();
    expect(names, {'ocideck.log', 'ocideck.1.log'});
    for (final name in names) {
      expect(file(name).lengthSync(), lessThanOrEqualTo(200), reason: name);
    }
    expect(file('ocideck.log').readAsStringSync(), endsWith(line(99)));
    expect(file('ocideck.1.log').readAsStringSync(), isNot(contains(line(0))));
  });

  test('na het eerste frame op de achtergrond, en close spoelt door', () async {
    final log = LogFile.open(dir)..writeInBackground();
    for (var i = 0; i < 60; i++) {
      log.write(line(i));
    }
    await log.close();
    expect(
      file('ocideck.log').readAsStringSync(),
      List.generate(60, line).join(),
    );
  });

  test('roteert ook op de achtergrond', () async {
    final log = LogFile.open(dir, maxBytes: 200)..writeInBackground();
    for (var i = 0; i < 40; i++) {
      log.write(line(i));
      await log.tail(0);
    }
    for (final name in ['ocideck.log', 'ocideck.1.log']) {
      expect(file(name).lengthSync(), lessThanOrEqualTo(200), reason: name);
    }
    expect(file('ocideck.log').readAsStringSync(), endsWith(line(39)));
  });

  test(
    'een vloed terwijl de schijf bezig is, wordt geteld en niet gebufferd',
    () async {
      final log = LogFile.open(dir, maxBytes: 400)..writeInBackground();
      for (var i = 0; i < 60; i++) {
        log.write(line(i));
      }
      await log.close();
      final text = file('ocideck.log').readAsStringSync();
      expect(text, contains(line(10)));
      expect(text, isNot(contains(line(11))));
      expect(text, contains('49 regels overgeslagen'));
      expect(file('ocideck.log').lengthSync(), lessThanOrEqualTo(400));
    },
  );

  test('een bestaand bestand telt mee voor de grens', () {
    file('ocideck.log').writeAsBytesSync(List.filled(190, 0x61));
    LogFile.open(dir, maxBytes: 200).write(line(1));
    expect(file('ocideck.1.log').lengthSync(), 190);
    expect(file('ocideck.log').readAsStringSync(), line(1));
  });

  test('tail leest over beide bestanden heen', () async {
    final log = LogFile.open(dir, maxBytes: 200);
    for (var i = 0; i < 30; i++) {
      log.write(line(i));
    }
    final last = await log.tail(15);
    expect(last, hasLength(15));
    expect(last.last, 'regel 0029');
    expect(last.first, 'regel 0015');
  });

  group('sessiemarkering', () {
    test('een nette afsluiting laat geen markering achter', () async {
      final log = LogFile.open(dir, sessionInfo: 'gestart om tien uur');
      expect(file('ocideck.sessie').existsSync(), isTrue);
      expect(log.previousSession, isNull);
      await log.close();
      expect(file('ocideck.sessie').existsSync(), isFalse);
      expect(LogFile.open(dir, sessionInfo: 'x').previousSession, isNull);
    });

    test('blijft de markering liggen, dan meldt de volgende start dat', () {
      LogFile.open(dir, sessionInfo: 'gestart om tien uur');
      // Geen close: de app is gecrasht of beëindigd.
      final next = LogFile.open(dir, sessionInfo: 'gestart om elf uur');
      expect(next.previousSession, 'gestart om tien uur');
      expect(
        file('ocideck.sessie').readAsStringSync().trim(),
        'gestart om elf uur',
      );
    });

    test('het beamervenster houdt geen markering bij', () {
      LogFile.open(dir, name: 'beamer');
      expect(file('beamer.sessie').existsSync(), isFalse);
    });
  });

  test('een logbestand dat niet wil, hindert de app niet', () {
    final log = LogFile.open(dir);
    Directory(file('ocideck.log').path).createSync();
    expect(() => log.write(line(1)), returnsNormally);
    expect(() => log.write(line(2)), returnsNormally);
  });

  test(
    'Diagnostics.report draagt versie, systeem en de laatste regels',
    () async {
      final log = LogFile.open(dir);
      Diagnostics.debugUse(log);
      addTearDown(() => Diagnostics.debugUse(null));
      logWarning('Outbox: iets');
      final report = await Diagnostics.report();
      expect(report, startsWith('**OciDeck-diagnose**\n\n- OciDeck '));
      expect(report, contains(Platform.operatingSystem));
      // Plakklaar voor een issue: de regels staan in een codeblok.
      final block = RegExp(r'````text\n([\s\S]*)\n````\n$').firstMatch(report);
      expect(block, isNotNull, reason: report);
      expect(block![1], contains('WARN Outbox: iets'));
    },
  );
}
