import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:path/path.dart' as p;

import '../../test/support/native_roundtrip_fixture.dart';
import '../../test/support/pump_until.dart';
import '../../test_driver/desktop_roundtrip_plan.dart';

FileService roundtripFileService(String root, String phase) => FileService(
  MarkdownService(),
  ImageService(),
  () => const ThemeProfile(),
  homeDirectory: () => root,
  saveDestination: ({dialogTitle, fileName, initialDirectory}) async =>
      roundtripPath(root, phase == 'write' ? 'write' : 'save-as'),
);

Future<Map<String, Object?>> runNativeRoundtripScenario(
  WidgetTester tester,
  ProviderContainer container,
  String root,
  String phase, {
  int Function()? sendMacosQuit,
}) async {
  final tabs = container.read(tabsProvider.notifier);
  final files = container.read(fileServiceProvider);
  final manifest = File(p.join(root, 'expected.json'));
  var comparisons = 0;
  if (phase == 'write') {
    tabs.newDeckInNewTab(
      'Native all-type roundtrip',
      slides: [],
      projectPath: p.join(root, 'project'),
    );
    final notifier = container.read(tabsProvider).current!.deckNotifier;
    expect(notifier.currentState.deck!.slides, isEmpty);
    final fixture = nativeRoundtripFixture(p.join(root, 'project'));
    expect(fixture.slides.map((slide) => slide.type), SlideType.values);
    for (final slide in fixture.slides) {
      notifier.addSlide(slide.type);
      notifier.updateSlide(
        notifier.currentState.deck!.slides.length - 1,
        slide,
      );
    }
    expect(
      notifier.currentState.deck!.slides.map((slide) => slide.type),
      SlideType.values,
    );
    // Capture authored app state before saving/exporting, never from a reopened file.
    await manifest.writeAsString(
      jsonEncode(nativeDeckSnapshot(notifier.currentState.deck!)),
    );
    await pumpUntil(
      tester,
      () => find.text('Native title').evaluate().isNotEmpty,
      reason: 'all-type deck is visible',
    );
    expect(find.text('Native title'), findsWidgets);
    if (sendMacosQuit != null) {
      expect(sendMacosQuit(), 1);
      await pumpUntil(
        tester,
        () => find.text('Niet-opgeslagen wijzigingen').evaluate().isNotEmpty,
        reason: 'native quit warning is visible',
      );
      expect(find.text('Niet-opgeslagen wijzigingen'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await pumpUntil(
        tester,
        () => find.text('Niet-opgeslagen wijzigingen').evaluate().isEmpty,
        reason: 'cancel retained the deck',
      );
      expect(notifier.currentState.isDirty, isTrue);
      expect(
        notifier.currentState.deck!.slides.length,
        SlideType.values.length,
      );
    }
    expect(
      await _saveAs(
        notifier,
        roundtripPath(root, phase == 'write' ? 'write' : 'save-as'),
      ),
      isTrue,
    );
    expect(notifier.currentState.filePath, roundtripPath(root, 'write'));
    expect(notifier.currentState.isDirty, isFalse);
    await files.exportPackage(
      notifier.currentState.deck!,
      roundtripPath(root, 'package'),
    );
  } else {
    final path = roundtripPath(root, phase);
    if (phase == 'package') {
      for (final name in ['project', 'verplaatst project', 'kopie']) {
        expect(
          Directory(p.join(root, name)).existsSync(),
          isFalse,
          reason: 'package cannot fall back to source assets',
        );
      }
    }
    if (phase != 'package') {
      final found = await files.scanMarkdownFiles(p.dirname(path));
      expect(
        found.map((entry) => p.normalize(entry.path)),
        contains(p.normalize(path)),
        reason: 'renamed/moved files remain discoverable',
      );
    }
    expect(await tabs.openFileByPath(path), OpenResult.opened);
    await pumpUntil(
      tester,
      () => find.text('Native title').evaluate().isNotEmpty,
      reason: 'reopened all-type deck is visible',
    );
    final notifier = container.read(tabsProvider).current!.deckNotifier;
    expect(notifier.currentState.isDirty, isFalse);
    expect(notifier.currentState.deck!.title, 'Native all-type roundtrip');
    expect(find.text('Native title'), findsWidgets);
    final members = phase == 'package'
        ? {
            for (final entry in files.decodePackageEntries(
              File(path).readAsBytesSync(),
            )!)
              entry.name: entry.bytes,
          }
        : <String, List<int>>{};
    comparisons = _compareWithAuthored(
      manifest,
      notifier.currentState.deck!,
      members,
    );
    if (phase == 'md') {
      final originalBytes = File(path).readAsBytesSync();
      expect(
        await _saveAs(
          notifier,
          roundtripPath(root, phase == 'write' ? 'write' : 'save-as'),
        ),
        isTrue,
      );
      expect(
        File(path).readAsBytesSync(),
        originalBytes,
        reason: 'Save as preserves the original file',
      );
      expect(notifier.currentState.filePath, roundtripPath(root, 'save-as'));
      _compareWithAuthored(manifest, notifier.currentState.deck!, const {});
    }
  }
  final current = container
      .read(tabsProvider)
      .current!
      .deckNotifier
      .currentState;
  return {
    'slides': current.deck!.slides.length,
    'dirty': current.isDirty,
    'cmd_q_guard': sendMacosQuit != null && phase == 'write',
    'fields_compared': comparisons,
    'formats': ['md', 'ocideck'],
  };
}

int _compareWithAuthored(
  File manifest,
  Deck deck,
  Map<String, List<int>> members,
) {
  final expected = (jsonDecode(manifest.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final actual = nativeDeckSnapshot(deck, members: members);
  expect(actual.length, expected.length);
  var count = 0;
  for (var index = 0; index < expected.length; index++) {
    expect(
      expected[index].keys.toSet(),
      nativePersistentFields,
      reason: 'every persistent field must be compared',
    );
    for (final field in expected[index].entries) {
      expect(
        actual[index][field.key],
        field.value,
        reason: 'slide[$index] ${expected[index]['type']}.${field.key}',
      );
      count++;
    }
  }
  return count;
}

Future<bool> _saveAs(DeckNotifier notifier, String destination) async {
  Directory(p.dirname(destination)).createSync(recursive: true);
  return notifier.saveAs();
}
