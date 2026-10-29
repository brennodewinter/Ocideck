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
