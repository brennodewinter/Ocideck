import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/single_instance.dart';

void main() {
  late Directory tempDir;
  late String socketPath;
  late SingleInstanceGuard guard;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ocideck_si_test');
    socketPath = '${tempDir.path}/ocideck.sock';
    guard = SingleInstanceGuard(socketPath: socketPath);
  });

  tearDown(() async {
    await guard.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('primaire ontvangt paden van een tweede starter', () async {
    await guard.becomePrimary();
    final received = <List<String>>[];
    guard.onFiles = received.add;

    final second = SingleInstanceGuard(socketPath: socketPath);
    expect(await second.forwardToPrimary(['/tmp/deck.md']), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received, [
      ['/tmp/deck.md'],
    ]);
  });

  test('paden vóór de UI-handler bufferen tot onFiles gezet is', () async {
    await guard.becomePrimary();

    final second = SingleInstanceGuard(socketPath: socketPath);
    await second.forwardToPrimary(['/tmp/vroeg.ocideck']);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final received = <List<String>>[];
    guard.onFiles = received.add;
    expect(received, [
      ['/tmp/vroeg.ocideck'],
    ]);
  });

  test('alleen deck-achtige argumenten reizen mee', () async {
    await guard.becomePrimary();
    final received = <List<String>>[];
    guard.onFiles = received.add;

    final second = SingleInstanceGuard(socketPath: socketPath);
    await second.forwardToPrimary([
      '/tmp/deck.md',
      '--verbose',
      'notafile.txt',
      '/tmp/doc.zip',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received, [
      ['/tmp/deck.md', '/tmp/doc.zip'],
    ]);
  });

  test('achtergebleven socketbestand van een crash wordt opgeruimd', () async {
    // Een leeg socketbestand zonder luisteraar — het lijk van een crash.
    await File(socketPath).writeAsString('');
    await guard.becomePrimary();

    final second = SingleInstanceGuard(socketPath: socketPath);
    final received = <List<String>>[];
    guard.onFiles = received.add;
    expect(await second.forwardToPrimary(['/tmp/deck.md']), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received, hasLength(1));
  });

  test('een lege start activeert de primaire (#2679)', () async {
    await guard.becomePrimary();
    var activated = 0;
    guard.onActivate = () => activated++;
    final received = <List<String>>[];
    guard.onFiles = received.add;

    final second = SingleInstanceGuard(socketPath: socketPath);
    expect(await second.forwardToPrimary(const []), isTrue);
    expect(activated, 1);
    expect(received, isEmpty);
  });

  test('activatie vóór de handler blijft één keer liggen (#2679)', () async {
    await guard.becomePrimary();
    final second = SingleInstanceGuard(socketPath: socketPath);
    expect(await second.forwardToPrimary(const []), isTrue);

    var activated = 0;
    guard.onActivate = () => activated++;
    expect(activated, 1);
  });

  test(
    'een primaire die niet antwoordt geeft binnen de time-out false (#2679)',
    () async {
      // De Windows-spiegel (poll, time-out, dialoog) staat in
      // windows/runner/main.cpp en draait niet onder flutter test.
      final server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      addTearDown(server.close);
      server.listen((connection) async {
        await utf8.decoder.bind(connection).join();
      });

      final second = SingleInstanceGuard(
        socketPath: socketPath,
        replyTimeout: const Duration(milliseconds: 200),
      );
      final watch = Stopwatch()..start();
      expect(await second.forwardToPrimary(const []), isFalse);
      expect(second.primaryDidNotAnswer, isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test('forwardToPrimary is false zonder luisteraar', () async {
    final second = SingleInstanceGuard(socketPath: socketPath);
    expect(await second.forwardToPrimary(['/tmp/deck.md']), isFalse);
  });

  test('dispose ruimt het socketbestand op', () async {
    await guard.becomePrimary();
    expect(File(socketPath).existsSync(), isTrue);
    await guard.dispose();
    expect(File(socketPath).existsSync(), isFalse);
  });
}
