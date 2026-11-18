import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/ui_frame.dart';

void main() {
  testWidgets('vraagt zelf een frame en rondt af na dat frame', (tester) async {
    var complete = false;
    final future = waitForUiFrame().then((_) => complete = true);
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(complete, isFalse);
    await tester.pump();
    await future;
    expect(complete, isTrue);
  });

  testWidgets(
    'zonder frame verloopt de eigen deadline, een later frame herstelt',
    (tester) async {
      const deadline = Duration(milliseconds: 30);
      Object? failure;
      await tester.runAsync(() async {
        try {
          await waitForUiFrame(
            timeout: deadline,
          ).timeout(const Duration(seconds: 2));
        } catch (error) {
          failure = error;
        }
      });
      expect(failure, isA<TimeoutException>());
      expect((failure as TimeoutException).duration, deadline);
      // De verlopen aanroep mag de gedeelde endOfFrame-future niet vergiftigen.
      await tester.pump();
      final next = waitForUiFrame();
      await tester.pump();
      await next;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('een actieve animatie blokkeert de framewacht niet', (
    tester,
  ) async {
    await tester.pumpWidget(const _Ticking());
    final frame = waitForUiFrame();
    await tester.pump(const Duration(milliseconds: 16));
    await frame;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Ticking extends StatefulWidget {
  const _Ticking();

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
