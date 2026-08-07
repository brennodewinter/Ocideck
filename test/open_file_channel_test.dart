import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/open_file_channel.dart';

/// De kanaallogica achter Finder-"Open met" en de filterloze macOS-kiezer
/// (ocideck/open_file), getest via [OpenFileChannel.activate] /
/// [pickUnfilteredMacFile] zodat hij op elk platform onder de dekking valt —
/// [OpenFileChannel.start] zelf gaat alleen op macOS echt aan.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = kOpenFileChannel;
  const codec = StandardMethodCodec();

  Object? launchFiles;
  final opened = <List<String>>[];
  final pickCalls = <Map<Object?, Object?>>[];
  String? pickResult;

  setUp(() {
    launchFiles = null;
    opened.clear();
    pickCalls.clear();
    pickResult = null;
    // De inbound-handler is globaal per kanaalnaam; zonder wissen luistert de
    // activate() van een vorig testgeval hier nog mee.
    channel.setMethodCallHandler(null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'getLaunchFiles') return launchFiles;
      if (call.method == 'pickFile') {
        pickCalls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return pickResult;
      }
      return null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  /// Een binnenkomende oproep van de hostkant, zoals AppDelegate die stuurt.
  Future<void> hostCalls(String method, Object? arguments) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      null,
    );
  }

  test('koude start: de meegegeven bestanden komen bij de callback', () async {
    launchFiles = ['a.md', 'b.ocideck'];
    final ofc = OpenFileChannel((paths) async => opened.add(paths));
    await ofc.activate();
    expect(opened, [
      ['a.md', 'b.ocideck'],
    ]);
  });

  test('koude start zonder bestanden: geen callback', () async {
    launchFiles = null;
    final ofc = OpenFileChannel((paths) async => opened.add(paths));
    await ofc.activate();
    expect(opened, isEmpty);
  });

  test('warme start: openFiles van de host bereikt de callback', () async {
    final ofc = OpenFileChannel((paths) async => opened.add(paths));
    await ofc.activate();
    await hostCalls('openFiles', ['c.md']);
    expect(opened, [
      ['c.md'],
    ]);
  });

  test(
    'niet-strings worden eruit gefilterd, rommel geeft geen callback',
    () async {
      final ofc = OpenFileChannel((paths) async => opened.add(paths));
      await ofc.activate();
      await hostCalls('openFiles', ['d.md', 42, null]);
      await hostCalls('openFiles', 'geen lijst');
      await hostCalls('ietsAnders', ['e.md']);
      expect(opened, [
        ['d.md'],
      ]);
    },
  );

  test('start doet buiten macOS niets, ook niet registreren', () async {
    final ofc = OpenFileChannel((paths) async => opened.add(paths));
    await ofc.start();
    if (Platform.isMacOS) {
      // Op macOS is start() wél actief; de koude start was leeg.
      expect(opened, isEmpty);
    } else {
      // Geen registratie: een openFiles van de host bereikt niemand.
      await hostCalls('openFiles', ['f.md']);
      expect(opened, isEmpty);
    }
  });

  test('pickUnfilteredMacFile stuurt titel en startmap mee', () async {
    pickResult = '/tmp/gekozen.md';
    final path = await pickUnfilteredMacFile(
      dialogTitle: 'Presentatie openen',
      initialDirectory: '/tmp',
    );
    if (Platform.isMacOS) {
      expect(path, '/tmp/gekozen.md');
      expect(pickCalls, hasLength(1));
      expect(pickCalls.single['dialogTitle'], 'Presentatie openen');
      expect(pickCalls.single['initialDirectory'], '/tmp');
    } else {
      expect(path, isNull);
      expect(pickCalls, isEmpty);
    }
  });

  test('pickUnfilteredMacFile bij annuleren: null', () async {
    pickResult = null;
    final path = await pickUnfilteredMacFile(dialogTitle: 'x');
    expect(path, isNull);
  });

  test('pickUnfilteredMacFile bij MissingPluginException gooit door', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      throw MissingPluginException('geen native handler');
    });
    if (Platform.isMacOS) {
      // Op macOS bereikt de aanroep het kanaal, dus de MissingPluginException
      // komt terug uit invokeMethod en pickUnfilteredMacFile herwerpt hem.
      await expectLater(
        () => pickUnfilteredMacFile(dialogTitle: 'x'),
        throwsA(isA<MissingPluginException>()),
      );
    } else {
      // Buiten macOS short-circuit pickUnfilteredMacFile naar null vóór het
      // kanaal (open_file_channel.dart: `!Platform.isMacOS` → return null), dus
      // de fout kan hem niet bereiken. Zonder deze splitsing verwachtte de test
      // onvoorwaardelijk een throw en viel de Linux-gate om terwijl macOS groen
      // bleef (main-drift: alleen de Linux-gate draait de suite op Linux).
      expect(await pickUnfilteredMacFile(dialogTitle: 'x'), isNull);
    }
  });
}
