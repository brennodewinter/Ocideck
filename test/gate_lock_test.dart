import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Het poortslot serialiseert zware poortruns die één native-assets-cache
/// delen (`scripts/gate_lock.sh`).
///
/// Elke worktree laat `.dart_tool/hooks_runner/shared` naar dezelfde map
/// wijzen. Zonder slot lopen twee gelijktijdige runs elkaars `dartcv4/.lock`
/// af, waarna `make check` faalt op een wíllekeurige poort — de poort wijst dan
/// naar de verkeerde plek, en dat is erger dan traag zijn.
///
/// Deze toets draait het script in een **eigen** tijdelijke map. Dat is geen
/// nettigheid maar noodzaak: gebruikt hij het echte slot, dan wacht hij tijdens
/// `make check` op de poort die hem zelf draait, en staat de suite stil.
void main() {
  late Directory sandbox;
  final script = File('scripts/gate_lock.sh').absolute.path;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('gate_lock_test');
    // Geen symlink: dan is het slot van deze map alleen, precies zoals een
    // worktree die niets deelt.
    Directory('${sandbox.path}/.dart_tool').createSync(recursive: true);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Future<ProcessResult> run(
    List<String> command, {
    Map<String, String> env = const {},
  }) => Process.run(
    script,
    command,
    workingDirectory: sandbox.path,
    environment: env,
  );

  test('twee runs overlappen niet', () async {
    final log = '${sandbox.path}/log.txt';
    // Allebei schrijven start en eind; met een slot horen ze na elkaar te
    // staan, zonder slot door elkaar.
    final first = run([
      'sh',
      '-c',
      'echo A-start >> $log; sleep 2; echo A-eind >> $log',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final second = run([
      'sh',
      '-c',
      'echo B-start >> $log; echo B-eind >> $log',
    ]);
    await Future.wait([first, second]);

    final lines = File(log).readAsLinesSync();
    expect(lines, ['A-start', 'A-eind', 'B-start', 'B-eind']);
  });

  test('een slot van een verdwenen proces houdt niemand tegen', () async {
    // Zonder deze tak blokkeert één afgebroken run iedereen tot iemand het slot
    // met de hand weghaalt.
    final lock = Directory('${sandbox.path}/.dart_tool/ocideck-gate.lock')
      ..createSync(recursive: true);
    // Pid 999999 bestaat vrijwel zeker niet; het slot is dus een wees.
    File('${lock.path}/holder').writeAsStringSync(
      'pid=999999\nworktree=/weg\nstart=toen\ncommando=weg\n',
    );

    final result = await run(['sh', '-c', 'echo gedraaid']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('gedraaid'));
    expect(result.stderr, contains('bestaat niet meer'));
  });

  test('de uitkomst van het commando is de uitkomst van het slot', () async {
    final result = await run(['sh', '-c', 'exit 3']);
    expect(
      result.exitCode,
      3,
      reason: 'een falende poort moet falen, niet verdwijnen in het slot',
    );
    expect(
      Directory('${sandbox.path}/.dart_tool/ocideck-gate.lock').existsSync(),
      isFalse,
      reason: 'ook na een fout hoort het slot weer vrij te zijn',
    );
  });

  test('OCIDECK_NO_GATE_LOCK slaat het slot over', () async {
    final result = await run(
      ['sh', '-c', 'echo zonder-slot'],
      env: {'OCIDECK_NO_GATE_LOCK': '1'},
    );
    expect(result.exitCode, 0);
    expect(result.stdout, contains('zonder-slot'));
    expect(
      Directory('${sandbox.path}/.dart_tool/ocideck-gate.lock').existsSync(),
      isFalse,
    );
  });

  test('wachten heeft een grens en zegt waar het slot staat', () async {
    final lock = Directory('${sandbox.path}/.dart_tool/ocideck-gate.lock')
      ..createSync(recursive: true);
    // Een houder die wél bestaat: het eigen testproces.
    File(
      '${lock.path}/holder',
    ).writeAsStringSync('pid=$pid\nworktree=/bezig\nstart=nu\ncommando=iets\n');

    final result = await run(
      ['sh', '-c', 'echo mag-niet'],
      env: {'OCIDECK_GATE_LOCK_TIMEOUT': '5'},
    );
    expect(result.exitCode, 75);
    expect(result.stderr, contains('/bezig'));
    expect(
      result.stderr,
      contains(lock.path),
      reason: 'de melding moet zeggen wélk slot je desnoods weghaalt',
    );
  });

  test('zonder commando is het een gebruiksfout, geen stilte', () async {
    final result = await run([]);
    expect(result.exitCode, 2);
  });
}
