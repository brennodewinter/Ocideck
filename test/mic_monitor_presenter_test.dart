import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/gestures.dart';
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

/// Opent de presenter. [presenterView] bepaalt of met P de cockpit wordt
/// aangezet — laat hem uit en de test ziet wat een enkel scherm toont (#2167).
Future<void> _openPresenter(
  WidgetTester tester,
  MicMonitor monitor, {
  bool presenterView = true,
}) async {
  // De cockpit met zijbalk past niet op het standaard 800×600-testscherm —
  // zelfde maat als de overige presenter-tests.
  tester.view.physicalSize = const Size(1400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(monitor));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (presenterView) {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
  }
}

/// Laat de muis over de publieksweergave zweven zodat de bedieningsbalk
/// verschijnt — de enige manier waarop de mic-knop op één scherm tevoorschijn
/// komt.
Future<void> _hoverAudienceView(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(find.byType(Scaffold).last));
  await tester.pump();
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
    // De dialoog noemt de fout én de route eruit (#2167): een snackbar zonder
    // vervolgstap liet de presentator bij een geweigerde machtiging vastzitten.
    expect(find.textContaining('microfoon kon niet'), findsOneWidget);
    expect(find.textContaining('systeeminstellingen'), findsWidgets);
    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.textContaining('microfoon kon niet'), findsNothing);
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

  // ── Enkel scherm (#2167): de cockpit is uit, de knop moet toch bereikbaar ──

  testWidgets('enkel scherm: mic-knop in de hover-balk, badge als hij loopt', (
    tester,
  ) async {
    final monitor = _FakeMicMonitor();
    await _openPresenter(tester, monitor, presenterView: false);

    // Zonder hover staat er geen bediening op het projectiebeeld.
    await _hoverAudienceView(tester);
    await tester.tap(find.byIcon(Icons.mic_none_outlined));
    await tester.pumpAndSettle();
    expect(monitor.startCalls, 1);
    expect(monitor.running, isTrue);

    // De doorvoer blijft zichtbaar als rood live-badge (icoon size 22), ook
    // als de balk weer weg is — een open microfoon mag nooit onzichtbaar zijn.
    final badge = find.byWidgetPredicate(
      (w) => w is Icon && w.icon == Icons.mic && w.size == 22,
    );
    expect(badge, findsOneWidget);

    // Het badge is tevens de uit-knop.
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(monitor.stopCalls, 1);
    expect(monitor.running, isFalse);
  });

  testWidgets('enkel scherm: V werkt en meldt de wissel met een toast', (
    tester,
  ) async {
    final monitor = _FakeMicMonitor();
    await _openPresenter(tester, monitor, presenterView: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(monitor.running, isTrue);
    expect(find.text('Microfoon-doorvoer aan'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(monitor.running, isFalse);
    expect(find.text('Microfoon-doorvoer uit'), findsOneWidget);
  });
}
