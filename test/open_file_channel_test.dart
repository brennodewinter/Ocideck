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

  /// Wat de hostkant teruggeeft. Sinds #1928 altijd een LIJST — ook voor één
  /// bestand — zodat er maar één vorm over het kanaal reist; `null` staat voor
  /// een host die niets stuurde.
  List<String>? pickResults;
  final saveCalls = <Map<Object?, Object?>>[];
  String? saveResult;

  setUp(() {
    launchFiles = null;
    opened.clear();
    pickCalls.clear();
    pickResults = null;
    saveCalls.clear();
    saveResult = null;
    // De inbound-handler is globaal per kanaalnaam; zonder wissen luistert de
    // activate() van een vorig testgeval hier nog mee.
    channel.setMethodCallHandler(null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'getLaunchFiles') return launchFiles;
      if (call.method == 'pickFile') {
        pickCalls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return pickResults;
      }
      if (call.method == 'saveFile') {
        saveCalls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return saveResult;
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
    pickResults = ['/tmp/gekozen.md'];
    final path = await pickUnfilteredMacFile(
      dialogTitle: 'Presentatie openen',
      initialDirectory: '/tmp',
    );
    if (Platform.isMacOS) {
      expect(path, '/tmp/gekozen.md');
      expect(pickCalls, hasLength(1));
      expect(pickCalls.single['dialogTitle'], 'Presentatie openen');
      expect(pickCalls.single['initialDirectory'], '/tmp');
      // De enkelvoudige wikkel vraagt geen meervoudige selectie aan (#1928).
      expect(pickCalls.single['allowsMultiple'], isFalse);
    } else {
      expect(path, isNull);
      expect(pickCalls, isEmpty);
    }
  });

  test('pickUnfilteredMacFile bij annuleren: null', () async {
    pickResults = const [];
    final path = await pickUnfilteredMacFile(dialogTitle: 'x');
    expect(path, isNull);
  });

  test('pickUnfilteredMacFile neemt het eerste van meerdere', () async {
    // De hostkant kán er meerdere teruggeven; de enkelvoudige wikkel mag daar
    // niet op stuklopen (#1928).
    pickResults = ['/tmp/een.md', '/tmp/twee.md'];
    final path = await pickUnfilteredMacFile(dialogTitle: 'x');
    expect(path, Platform.isMacOS ? '/tmp/een.md' : isNull);
  });

  test('pickUnfilteredMacFiles vraagt meervoudig aan en levert alles', () async {
    pickResults = ['/tmp/een.md', '/tmp/twee.md'];
    final paths = await pickUnfilteredMacFiles(
      dialogTitle: 'Presentaties openen',
      allowsMultiple: true,
    );
    if (Platform.isMacOS) {
      expect(paths, ['/tmp/een.md', '/tmp/twee.md']);
      expect(pickCalls.single['allowsMultiple'], isTrue);
    } else {
      // Buiten macOS bestaat dit paneel niet: leeg, en het kanaal blijft stil.
      expect(paths, isEmpty);
      expect(pickCalls, isEmpty);
    }
  });

  test('pickUnfilteredMacFiles bij annuleren: leeg', () async {
    pickResults = const [];
    expect(await pickUnfilteredMacFiles(dialogTitle: 'x'), isEmpty);
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

  // saveMacFile is het opslaan-spiegelbeeld van pickUnfilteredMacFile: dezelfde
  // kanaalroute, dezelfde contracten. Getest op elk platform — op niet-macOS
  // short-circuit de functie naar null vóór het kanaal.
  test('saveMacFile stuurt titel, bestandsnaam en startmap mee', () async {
    saveResult = '/tmp/gekozen.md';
    final path = await saveMacFile(
      dialogTitle: 'Opslaan als',
      fileName: 'Kwartaal_Update.md',
      initialDirectory: '/tmp',
    );
    if (Platform.isMacOS) {
      expect(path, '/tmp/gekozen.md');
      expect(saveCalls, hasLength(1));
      expect(saveCalls.single['dialogTitle'], 'Opslaan als');
      expect(saveCalls.single['fileName'], 'Kwartaal_Update.md');
      expect(saveCalls.single['initialDirectory'], '/tmp');
    } else {
      expect(path, isNull);
      expect(saveCalls, isEmpty);
    }
  });

  test('saveMacFile bij annuleren: null', () async {
    saveResult = null;
    final path = await saveMacFile(dialogTitle: 'x', fileName: 'demo.md');
    expect(path, isNull);
  });

  test('saveMacFile bij MissingPluginException gooit door', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      throw MissingPluginException('geen native handler');
    });
    if (Platform.isMacOS) {
      await expectLater(
        () => saveMacFile(dialogTitle: 'x', fileName: 'demo.md'),
        throwsA(isA<MissingPluginException>()),
      );
    } else {
      // Buiten macOS short-circuit saveMacFile naar null vóór het kanaal, dus
      // de fout kan hem niet bereiken (zelfde splitsing als pickUnfilteredMacFile
      // hierboven — anders valt de Linux-gate om).
      expect(await saveMacFile(dialogTitle: 'x', fileName: 'demo.md'), isNull);
    }
  });
}
