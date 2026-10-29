// De stallmelder (#2618): een UI-isolate die vastzat, levert één logregel met
// de duur en het werk dat in dat venster begon — en een verborgen venster, dat
// van het OS minder timertijd krijgt, levert er geen.

import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/diagnostics/ui_stall_watch.dart';
import 'package:ocideck/utils/log.dart';

class _Lines implements LogSink {
  final lines = <String>[];

  @override
  void write(String line) => lines.add(line);

  @override
  Future<void> close() async {}
}

void main() {
  late _Lines sink;

  setUp(() {
    sink = _Lines();
    installLogSink(sink);
  });

  tearDown(() => installLogSink(null));

  group('met een eigen klok', () {
    var now = 0;
    AppLifecycleState? state = AppLifecycleState.resumed;
    late UiStallWatch watch;

    setUp(() {
      now = 1000000;
      state = AppLifecycleState.resumed;
      watch = UiStallWatch(clockMs: () => now, lifecycle: () => state)..start();
    });

    tearDown(() => watch.stop());

    test('een tik op tijd meldt niets', () {
      now += 250;
      watch.check();
      now += 700;
      watch.check();
      expect(sink.lines, isEmpty);
    });

    test('een vastloper noemt de duur en het werk dat erin begon', () async {
      // De werklabels staan op [logClockMs]; laat de nepklok daarop meelopen.
      var skip = 0;
      final real = UiStallWatch(
        clockMs: () => logClockMs + skip,
        lifecycle: () => state,
      );
      addTearDown(real.stop);
      noteWork('vóór de vastloper');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      real.start();
      skip = 2000;
      noteWork('gezichtsscan');
      noteWork('documentsync');
      real.check();
      expect(sink.lines, hasLength(1));
      expect(
        sink.lines.single,
        matches(
          RegExp(
            r'UI-isolate \d+ ms onbereikbaar — werk: '
            r'gezichtsscan, documentsync\n$',
          ),
        ),
      );
    });

    test('een verborgen venster is geen vastloper', () {
      state = AppLifecycleState.hidden;
      watch.check();
      now += 5000;
      watch.check();
      expect(sink.lines, isEmpty);
    });

    test('een toestandswissel in het venster telt niet', () {
      now += 5000;
      state = AppLifecycleState.inactive;
      watch.check();
      expect(sink.lines, isEmpty);
      now += 5000;
      watch.check();
      expect(sink.lines, hasLength(1));
    });

    test('heel lang stil zegt dat de computer misschien sliep', () {
      now += 120000;
      watch.check();
      expect(sink.lines.single, contains('(of de computer sliep)'));
    });
  });

  test('een echte blokkade van 800 ms levert precies één regel', () async {
    final watch = UiStallWatch(lifecycle: () => AppLifecycleState.resumed)
      ..start();
    addTearDown(watch.stop);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    noteWork('kunstmatige blokkade');
    final started = DateTime.now();
    while (DateTime.now().difference(started).inMilliseconds < 800) {}
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final stalls = sink.lines.where((l) => l.contains('onbereikbaar')).toList();
    expect(stalls, hasLength(1));
    expect(stalls.single, contains('werk: kunstmatige blokkade'));
  });
}
