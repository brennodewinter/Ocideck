@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// De vertalersroute: één taal eruit als plat JSON, en er weer in terug.
///
/// Bestaat omdat de drempel voor een moedertaalspreker die één slechte zin wil
/// verbeteren anders Dart-syntaxis, een `part`-bestand en `make check` is
/// (#633). Wat hier bewaakt wordt zijn de twee eigenschappen waar een vertaler
/// op moet kunnen rekenen: dat zijn wijziging **precies** terugkomt, en dat het
/// gereedschap weigert in plaats van half werk te leveren als hij op een oudere
/// versie werkte.
void main() {
  late Directory temp;
  late String repoRoot;

  setUp(() {
    repoRoot = Directory.current.path;
    temp = Directory.systemTemp.createTempSync('l10n_po');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  ProcessResult run(List<String> args) => Process.runSync('dart', [
    'run',
    'tool/l10n_po.dart',
    ...args,
  ], workingDirectory: repoRoot);

  test('export levert de vertalingen van één taal als platte JSON', () {
    final out = '${temp.path}/ga.json';
    final r = run(['export', 'ga', out]);
    expect(r.exitCode, 0, reason: '${r.stderr}');

    final map =
        jsonDecode(File(out).readAsStringSync()) as Map<String, dynamic>;
    expect(
      map.length,
      greaterThan(2000),
      reason: 'het hele corpus, niet een deel',
    );
    // De Nederlandse bronstring ís de sleutel — zo ziet de vertaler altijd
    // waarvan hij een vertaling maakt, zonder het Dart-bestand ernaast.
    expect(map.keys.every((k) => k.isNotEmpty), isTrue);
    expect(map.values.every((v) => v is String), isTrue);
  });

  test('een onbekende taal wordt geweigerd, niet stil overgeslagen', () {
    final r = run(['export', 'xx', '${temp.path}/x.json']);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('onbekende taal'));
  });

  test('een onbekende sleutel laat het hele bestand afketsen', () {
    // Bijna altijd betekent dit dat de vertaler op een oudere versie werkte.
    // Stilzwijgend doorgaan is dan de manier waarop zijn werk half landt — en
    // erger: een nieuwe string zou zo in één taal kunnen bestaan en in dertig
    // niet, precies wat `add_l10n.dart` afdwingt te voorkomen.
    final bad = '${temp.path}/bad.json';
    File(bad).writeAsStringSync(jsonEncode({'Deze sleutel bestaat niet': 'x'}));
    final r = run(['import', 'ga', bad]);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('onbekende sleutel'));
    expect(
      r.stderr.toString(),
      contains('add_l10n'),
      reason: 'de melding moet de juiste route noemen, niet alleen de fout',
    );
  });

  test('geen JSON is een nette weigering, geen stacktrace', () {
    final bad = '${temp.path}/bad.json';
    File(bad).writeAsStringSync('dit is geen json');
    final r = run(['import', 'ga', bad]);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('geen geldige JSON'));
  });

  test('een ronde-trip zonder wijziging raakt geen enkel bestand aan', () {
    // De scherpste toets die er is: exporteren en meteen terugimporteren mag
    // nul strings bijwerken. Doet het er wél één, dan verliest of vervormt de
    // heenweg iets — een aanhalingsteken, een regeleinde, een euroteken — en
    // dan zou elke vertaalronde ongemerkte wijzigingen meebrengen.
    final out = '${temp.path}/ga.json';
    expect(run(['export', 'ga', out]).exitCode, 0);
    final r = run(['import', 'ga', out]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stderr.toString(), contains('0 string(s) bijgewerkt'));
  });
}
