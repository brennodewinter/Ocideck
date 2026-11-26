// Shared real-window smoke scenario. The host runs this in two app processes.
import 'dart:async';
import 'dart:ffi';

// ignore: depend_on_referenced_packages
import 'package:ffi/ffi.dart';
import 'package:nativeapi/nativeapi.dart';
import 'dart:io';

import 'package:flutter/widgets.dart' show runApp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/platform/native_window.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/desktop_smoke_paths.dart';
import 'support/desktop_roundtrip_scenario.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late String rootPath;
  late String phaseName;
  int Function()? sendQuit;
  testWidgets('open, add, save, close and reopen in native app processes', (
    tester,
  ) async {
    final root = Platform.environment['DESKTOP_SMOKE_ROOT'] ?? '';
    expect(
      p.isAbsolute(root),
      isTrue,
      reason: 'Use tool/run_desktop_smoke.dart',
    );
    final phase = File(p.join(root, 'phase.txt')).readAsStringSync().trim();
    rootPath = root;
    phaseName = phase;
    PathProviderPlatform.instance = DesktopSmokePaths(root);
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'languageCode': 'nl',
    });

    if (Platform.isMacOS) {
      final library = DynamicLibrary.open(p.join(root, 'quit-probe.dylib'));
      sendQuit = library.lookupFunction<Int32 Function(), int Function()>(
        'ocideck_smoke_cmd_q',
      );
      final registerExit = library
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('ocideck_smoke_record_clean_exit');
      final marker = p.join(root, 'clean-exit-$phase.txt').toNativeUtf8();
      try {
        registerExit(marker);
      } finally {
        calloc.free(marker);
      }
    }
    await configureNativeWindow();
    final roundtrip =
        Platform.environment['DESKTOP_SMOKE_SCENARIO'] == 'roundtrip';
    container = ProviderContainer(
      overrides: [
        if (roundtrip)
          fileServiceProvider.overrideWithValue(
            roundtripFileService(root, phase),
          ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    await binding.waitUntilFirstFrameRasterized.timeout(
      const Duration(seconds: 30),
    );
    expect(find.byType(AppShell), findsOneWidget);
    final Map<String, Object?> result;
    if (roundtrip) {
      result = await runNativeRoundtripScenario(
        tester,
        container,
        root,
        phase,
        sendMacosQuit: sendQuit,
      );
    } else {
      result = await _basicScenario(tester, container, root, phase, sendQuit);
    }
    binding.reportData = {
      'phase': phase,
      'pid': pid,
      'platform': Platform.operatingSystem,
      ...result,
      'ready_to_close': true,
    };
  }, timeout: const Timeout(Duration(minutes: 3)));

  tearDownAll(() async {
    if (binding.reportData?['ready_to_close'] != true) return;
    // Widget tests unmount their tree before reporting success. Restore the
    // real shell around the SAME live state so the driver's later native quit
    // still traverses production cleanup. The driver has not requested it yet.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const OciDeckApp(),
      ),
    );
    await binding.endOfFrame.timeout(const Duration(seconds: 5));
    Zone.root.run(() {
      final request = File(p.join(rootPath, 'close-$phaseName.request'));
      Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!request.existsSync()) return;
        timer.cancel();
        if (Platform.isMacOS) {
          sendQuit!();
        } else {
          final manager = WindowManager.instance;
          final window = manager.getCurrent();
          if (window != null) manager.handleWillClose(window.id);
        }
      });
    });
  });
}

Future<Map<String, Object?>> _basicScenario(
  WidgetTester tester,
  ProviderContainer container,
  String root,
  String phase,
  int Function()? sendQuit,
) async {
  final tabs = container.read(tabsProvider.notifier);
  final file = File(p.join(root, 'journey.md'));
  expect(await tabs.openFileByPath(file.path), OpenResult.opened);
  await tester.pumpAndSettle();
  final deck = container.read(tabsProvider).current!.deckNotifier;
  expect(deck.currentState.isDirty, isFalse);
  if (phase == 'write') {
    expect(deck.currentState.deck!.slides, hasLength(1));
    deck.addSlide(SlideType.bullets);
    deck.updateSlide(
      1,
      deck.currentState.deck!.slides[1].copyWith(
        title: 'Native lifecycle probe',
        bullets: ['Saved across app processes'],
      ),
    );
    await tester.pumpAndSettle();
    expect(deck.currentState.isDirty, isTrue);
    expect(find.text('Native lifecycle probe'), findsWidgets);
    if (Platform.isMacOS) {
      expect(
        sendQuit!(),
        1,
        reason: 'AppKit must handle the actual Cmd+Q menu equivalent',
      );
      await tester.pumpAndSettle();
      expect(find.text('Niet-opgeslagen wijzigingen'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(find.text('Niet-opgeslagen wijzigingen'), findsNothing);
      expect(deck.currentState.isDirty, isTrue);
      expect(deck.currentState.deck!.slides, hasLength(2));
    }
    expect(await deck.save(), isTrue);
    await tester.pumpAndSettle();
    expect(deck.currentState.isDirty, isFalse);
    expect(file.readAsStringSync(), contains('Saved across app processes'));
  } else {
    expect(phase, 'reopen');
    expect(deck.currentState.deck!.slides, hasLength(2));
    expect(deck.currentState.deck!.slides[1].title, 'Native lifecycle probe');
    expect(find.text('Native lifecycle probe'), findsWidgets);
    expect(deck.currentState.deck!.slides[1].bullets, [
      'Saved across app processes',
    ]);
    expect(deck.currentState.isDirty, isFalse);
  }
  return {
    'slides': deck.currentState.deck!.slides.length,
    'dirty': deck.currentState.isDirty,
    'cmd_q_guard': Platform.isMacOS && phase == 'write',
  };
}
