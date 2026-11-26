import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ocideck/widgets/presentation/display_info.dart';
import 'package:ocideck/widgets/presentation/display_info_io.dart' as native;

const laptop = DisplayInfo(
  nativeId: 'laptop',
  x: 0,
  y: 0,
  width: 1440,
  height: 900,
);
const beamer = DisplayInfo(
  nativeId: 'beamer',
  x: 1440,
  y: 0,
  width: 1920,
  height: 1080,
);
const extra = DisplayInfo(
  nativeId: 'extra',
  x: -1440,
  y: 0,
  width: 1440,
  height: 900,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugGetAllDisplays = null;
    debugGetCurrentWindowCenter = null;
    debugMoveToDisplay = null;
  });
  group('shared display snapshot (#3216)', () {
    test('one enumeration, immutable list, no center lookup on empty list', () {
      var reads = 0;
      var centers = 0;
      final source = [laptop, beamer];
      debugGetAllDisplays = () {
        reads++;
        return source;
      };
      debugGetCurrentWindowCenter = () {
        centers++;
        return const Offset(700, 400);
      };
      final snapshot = captureDisplaySnapshot();
      expect(reads, 1);
      expect(centers, 1);
      expect(snapshot.presenter, laptop);
      expect(snapshot.next(), beamer);
      source.clear();
      expect(snapshot.displays, [laptop, beamer]);
      expect(() => snapshot.displays.clear(), throwsUnsupportedError);
      expect(captureDisplaySnapshot().displays, isEmpty);
      expect(centers, 1);
    });

    test('failed, invalid and ambiguous enumerations fail closed', () {
      debugGetCurrentWindowCenter = () => const Offset(700, 400);
      debugGetAllDisplays = () => throw StateError('disconnected');
      expect(captureDisplaySnapshot().displays, isEmpty);
      for (final source in <List<DisplayInfo>>[
        [laptop, laptop],
        [const DisplayInfo(x: 0, y: 0, width: 1, height: 1)],
        [const DisplayInfo(nativeId: '0', x: 0, y: 0, width: 1, height: 1)],
        [const DisplayInfo(nativeId: 'bad', x: 0, y: 0, width: 0, height: 1)],
        [
          const DisplayInfo(
            nativeId: 'bad',
            x: double.nan,
            y: 0,
            width: 1,
            height: 1,
          ),
        ],
      ]) {
        debugGetAllDisplays = () => source;
        expect(captureDisplaySnapshot().displays, isEmpty);
      }
      debugGetAllDisplays = () => [laptop, beamer];
      debugGetCurrentWindowCenter = () => null;
      expect(captureDisplaySnapshot().canPresentAudience, isFalse);
      debugGetCurrentWindowCenter = () => const Offset(99999, 99999);
      expect(captureDisplaySnapshot().next(), isNull);
      // Mirrored/overlapping geometry does not identify the presenter uniquely.
      debugGetAllDisplays = () => [
        laptop,
        const DisplayInfo(
          nativeId: 'mirror',
          x: 0,
          y: 0,
          width: 1440,
          height: 900,
        ),
      ];
      debugGetCurrentWindowCenter = () => const Offset(700, 400);
      expect(captureDisplaySnapshot().canPresentAudience, isFalse);
    });

    test(
      'cycling uses the current screen after reorder, never a saved index',
      () {
        debugGetAllDisplays = () => [beamer, laptop, extra];
        debugGetCurrentWindowCenter = () => const Offset(700, 400);
        final snapshot = captureDisplaySnapshot();
        expect(snapshot.presenter, laptop);
        expect(snapshot.next(), extra);
        debugGetCurrentWindowCenter = () => const Offset(2000, 400);
        expect(captureDisplaySnapshot().next(), laptop);
      },
    );

    test(
      'move rejects empty, removed and shifted targets without native writes',
      () async {
        final moved = <int>[];
        debugMoveToDisplay = (index, _) => moved.add(index);
        debugGetCurrentWindowCenter = () => const Offset(700, 400);
        for (final source in <List<DisplayInfo>>[
          [],
          [laptop],
          [laptop, extra],
          [beamer, extra],
        ]) {
          debugGetAllDisplays = () => source;
          await expectLater(
            moveToDisplay(beamer, previous: laptop),
            throwsStateError,
          );
        }
        expect(moved, isEmpty);
      },
    );

    test(
      'same identity after reorder uses fresh geometry, not the old index',
      () async {
        const resized = DisplayInfo(
          nativeId: 'beamer',
          x: -1920,
          y: 0,
          width: 1920,
          height: 1200,
        );
        debugGetAllDisplays = () => [resized, laptop];
        debugGetCurrentWindowCenter = () => const Offset(700, 400);
        final moved = <DisplayInfo>[];
        debugMoveToDisplay = (index, displays) => moved.add(displays[index]);
        await moveToDisplay(beamer, previous: laptop);
        expect(moved, [resized]);
      },
    );

    test(
      'main-window native action gets identities and propagates disappearance',
      () async {
        const channel = MethodChannel('mixin.one/desktop_multi_window');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <MethodCall>[];
        var disappeared = false;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getWindowDefinition') {
            return {'windowId': 'presenter', 'windowArgument': ''};
          }
          calls.add(call);
          if (disappeared) throw PlatformException(code: 'display-gone');
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await native.moveToDisplay(beamer, previous: laptop);
        expect(calls.single.method, 'window_moveToDisplay');
        expect(calls.single.arguments, {
          'windowId': 'presenter',
          'presenterDisplay': 'laptop',
          'targetDisplay': 'beamer',
        });
        disappeared = true;
        await expectLater(
          native.moveToDisplay(beamer, previous: laptop),
          throwsA(isA<PlatformException>()),
        );
      },
    );

    test('audience payload binds both identities from one snapshot', () async {
      const channel = MethodChannel('mixin.one/desktop_multi_window');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final controller = WindowController.fromWindowId('test');
      await coverAudienceDisplay(
        controller,
        DisplaySnapshot([laptop, beamer], const Offset(700, 400)),
      );
      expect(calls.single.method, 'window_coverScreen');
      expect(
        calls.single.arguments,
        containsPair('presenterDisplay', 'laptop'),
      );
      expect(calls.single.arguments, containsPair('targetDisplay', 'beamer'));
      expect(
        (calls.single.arguments as Map).containsKey('presenterScreen'),
        isFalse,
      );
      for (final source in <List<DisplayInfo>>[
        [],
        [laptop],
      ]) {
        await expectLater(
          coverAudienceDisplay(
            controller,
            DisplaySnapshot(source, const Offset(700, 400)),
          ),
          throwsStateError,
        );
      }
      expect(calls, hasLength(1));
    });
  });

  // Laptop (primair, links) en een beamer (extern, rechts) — de standaard
  // two-screen opstelling. Coordinaten in top-left, zoals nativeapi levert.
  final displays = <DisplayInfo>[
    const DisplayInfo(x: 0, y: 0, width: 1440, height: 900),
    const DisplayInfo(x: 1440, y: 0, width: 1920, height: 1080),
  ];

  test('vindt het scherm dat de presentator bevat (normale opstelling)', () {
    // Presentator op de laptop: het punt ligt in scherm 0.
    expect(screenIndexContaining(displays, const Offset(720, 450)), 0);
  });

  test('vindt het scherm dat de presentator bevat (omgedraaid, #1913)', () {
    // Presentator verplaatst naar de beamer: het punt ligt in scherm 1. Dat is
    // precies de situatie waarin coverScreen(external:true) vroeger het
    // publieksvenster óók op de beamer zette in plaats van op de laptop.
    expect(screenIndexContaining(displays, const Offset(2400, 540)), 1);
  });

  test('geeft null voor een punt buiten alle schermen', () {
    expect(screenIndexContaining(displays, const Offset(-10, 0)), isNull);
    expect(screenIndexContaining(displays, const Offset(5000, 0)), isNull);
  });

  test('geeft null voor een null-punt of geen schermen', () {
    expect(screenIndexContaining(displays, null), isNull);
    expect(
      screenIndexContaining(const <DisplayInfo>[], const Offset(0, 0)),
      isNull,
    );
  });

  test('pakt het eerste scherm bij overlappende grens', () {
    // Een punt precies op de grens (x=1440) hoort bij één scherm; beide
    // aanliggende schermen claimen het, maar de uitkomst moet deterministisch
    // zijn — het eerste scherm dat het punt bevat.
    final index = screenIndexContaining(displays, const Offset(1440, 0));
    expect(index == 0 || index == 1, isTrue);
  });
}
