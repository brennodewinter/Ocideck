import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/mic_monitor.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

/// Test-double achter de [MicMonitor]-naad (#2158): de echte binding is
/// libwebrtc en kan niet headless draaien, dus deze registreert wat de
/// presenter deed in plaats van wat het OS deed.
class _FakeMicMonitor implements MicMonitor {
  int startCalls = 0;
  int stopCalls = 0;
  bool failOnStart = false;

  /// Houdt [start] open tot [finishStart] hem sluit — voor de race waarin de
  /// machtigingsprompt langer duurt dan de presentatie.
  Completer<void>? _pendingStart;
  bool _running = false;

  @override
  bool get running => _running;

  void hangOnStart() => _pendingStart = Completer<void>();
  void finishStart() => _pendingStart?.complete();

  @override
  Future<void> start() async {
    startCalls++;
    await _pendingStart?.future;
    if (failOnStart) throw MicMonitorException('geen mic in test');
    _running = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _running = false;
  }
}

Widget _host(MicMonitor micMonitor) {
  return MaterialApp(
    localizationsDelegates: const [
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FullscreenPresenter(
                slides: [
                  Slide.create(
                    SlideType.bullets,
                  ).copyWith(title: 'Eerste', bullets: ['a']),
                ],
                projectPath: null,
                themeProfile: const ThemeProfile(),
                initialIndex: 0,
                showRehearsalSummary: false,
                micMonitor: micMonitor,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> _openPresenter(WidgetTester tester, MicMonitor monitor) async {
  // De cockpit met zijbalk past niet op het standaard 800×600-testscherm —
  // zelfde maat als de overige presenter-tests.
  tester.view.physicalSize = const Size(1400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(monitor));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // De cockpit is zichtbaar zodra de presenter-view aan staat; P schakelt hem
  // aan in enkel-scherm-modus.
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.pumpAndSettle();
}

Future<void> _tapMicButton(WidgetTester tester) async {
  final button = find.byIcon(Icons.mic_none_outlined);
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  test('MicMonitorException noemt de oorzaak', () {
    expect(
      MicMonitorException('perm denied').toString(),
      'MicMonitorException(perm denied)',
    );
  });

  testWidgets('mic-knop start en stopt de doorvoer', (tester) async {
    final monitor = _FakeMicMonitor();
    await _openPresenter(tester, monitor);

    await _tapMicButton(tester);
    expect(monitor.startCalls, 1);
    expect(monitor.running, isTrue);
    // De actieve staat is zichtbaar: het icoon wisselt naar de gevulde mic.
    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    expect(monitor.stopCalls, 1);
    expect(monitor.running, isFalse);
  });

  testWidgets('toets V schakelt de doorvoer', (tester) async {
    final monitor = _FakeMicMonitor();
    await _openPresenter(tester, monitor);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(monitor.startCalls, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(monitor.stopCalls, 1);
  });

  testWidgets('een mislukte start meldt fout én uitweg, staat blijft uit', (
    tester,
  ) async {
    final monitor = _FakeMicMonitor()..failOnStart = true;
    await _openPresenter(tester, monitor);

    await _tapMicButton(tester);
    expect(monitor.running, isFalse);
    expect(find.textContaining('microfoon kon niet'), findsOneWidget);
  });

  testWidgets('dubbele tik tijdens een hangende start blijft één start', (
    tester,
  ) async {
    final monitor = _FakeMicMonitor()..hangOnStart();
    await _openPresenter(tester, monitor);

    await tester.tap(find.byIcon(Icons.mic_none_outlined));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.mic_none_outlined));
    monitor.finishStart();
    await tester.pumpAndSettle();

    expect(monitor.startCalls, 1);
  });

  testWidgets('afsluiten tijdens een lopende start laat geen mic achter', (
    tester,
  ) async {
    final monitor = _FakeMicMonitor()..hangOnStart();
    await _openPresenter(tester, monitor);

    await tester.tap(find.byIcon(Icons.mic_none_outlined));
    await tester.pump();
    // De presentatie sluit vóór de start klaar is — het equivalent van Escape
    // tijdens een macOS-machtigingsprompt.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    monitor.finishStart();
    await tester.pumpAndSettle();

    expect(monitor.stopCalls, greaterThan(0));
    expect(monitor.running, isFalse);
    // Terug op het launcher-scherm: de presentatie is echt weg.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('afsluiten met lopende doorvoer stopt hem', (tester) async {
    final monitor = _FakeMicMonitor();
    await _openPresenter(tester, monitor);
    await _tapMicButton(tester);
    expect(monitor.running, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(monitor.stopCalls, greaterThan(0));
    expect(monitor.running, isFalse);
  });
}
