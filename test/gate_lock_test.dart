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

  // `gate_lock.sh` is een POSIX-shellscript, en `Process.run` op Windows start
  // dat niet ("%1 is not a valid Win32 application"). Het slot bestaat voor de
  // machine waarop `make check` draait — macOS en Linux; geen enkele poort die
  // merges gate't draait Windows. Het onder Git Bash toetsen zou een draaipunt
  // toetsen dat niemand gebruikt, dus slaan we over met een reden (zelfde keuze
  // als in release_auto_version_test.dart).
  final skipOnWindows = Platform.isWindows
      ? 'gate_lock.sh is POSIX-only; Process.run start geen .sh op Windows'
      : null;

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
  }, skip: skipOnWindows);

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
  }, skip: skipOnWindows);

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
  }, skip: skipOnWindows);

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
  }, skip: skipOnWindows);

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
  }, skip: skipOnWindows);

  test('zonder commando is het een gebruiksfout, geen stilte', () async {
    final result = await run([]);
    expect(result.exitCode, 2);
  }, skip: skipOnWindows);

  /// De CMake-stempel. Elke worktree noemt dezelfde fysieke buildmap anders,
  /// en CMake weigert dan hard in plaats van te herconfigureren. Serialiseren
  /// maakt dat erger, niet beter: elke run stempelt op zijn eigen pad, dus de
  /// volgende faalt gegarandeerd. Het slot ruimt daarom op.
  Directory writeCache(String stampedDir) {
    final build = Directory(
      '${sandbox.path}/.dart_tool/hooks_runner/shared/dartcv4/build/7ad245dadc',
    )..createSync(recursive: true);
    File(
      '${build.path}/CMakeCache.txt',
    ).writeAsStringSync('CMAKE_CACHEFILE_DIR:INTERNAL=$stampedDir\n');
    Directory('${build.path}/CMakeFiles').createSync();
    // Het gedownloade bronarchief mag niet sneuvelen: opnieuw ophalen loopt
    // stuk op de 429 van GitHub.
    Directory('${build.path}/_deps').createSync();
    return build;
  }

  test('een cache van een andere worktree wordt opgeruimd', () async {
    final build = writeCache('/ergens/anders/dartcv4/build/7ad245dadc');

    final result = await run(['sh', '-c', 'echo gedraaid']);

    expect(result.exitCode, 0);
    expect(File('${build.path}/CMakeCache.txt').existsSync(), isFalse);
    expect(Directory('${build.path}/CMakeFiles').existsSync(), isFalse);
    expect(
      Directory('${build.path}/_deps').existsSync(),
      isTrue,
      reason: 'zonder _deps volgt een herdownload, en die weigert GitHub',
    );
    expect(result.stderr, contains('/ergens/anders'));
  }, skip: skipOnWindows);

  test('een cache van deze worktree blijft staan', () async {
    final build = writeCache(
      '${sandbox.path}/.dart_tool/hooks_runner/shared/dartcv4/build/7ad245dadc',
    );

    final result = await run(['sh', '-c', 'echo gedraaid']);

    expect(result.exitCode, 0);
    expect(
      File('${build.path}/CMakeCache.txt').existsSync(),
      isTrue,
      reason: 'onnodig wissen kost een volledige herbouw van OpenCV',
    );
    expect(Directory('${build.path}/CMakeFiles').existsSync(), isTrue);
  }, skip: skipOnWindows);

  test('de bouw laat kernen vrij', () async {
    // Zonder rem bouwt CMake met zoveel taken als er kernen zijn; op een
    // laptop trok dat meer stroom dan de adapter kon leveren.
    final cores = Platform.numberOfProcessors;
    final result = await run([
      'sh',
      '-c',
      r'echo "niveau=$CMAKE_BUILD_PARALLEL_LEVEL"',
    ]);

    final level = int.parse(
      RegExp(r'niveau=(\d+)').firstMatch('${result.stdout}')!.group(1)!,
    );
    expect(level, greaterThanOrEqualTo(2));
    if (cores > 6) expect(level, lessThan(cores));
  }, skip: skipOnWindows);

  test('een eigen rem blijft staan', () async {
    final result = await run(
      ['sh', '-c', r'echo "niveau=$CMAKE_BUILD_PARALLEL_LEVEL"'],
      env: {'CMAKE_BUILD_PARALLEL_LEVEL': '3'},
    );

    expect(result.stdout, contains('niveau=3'));
  }, skip: skipOnWindows);
}
