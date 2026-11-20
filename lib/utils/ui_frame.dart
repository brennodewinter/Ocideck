import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Wacht begrensd op één frame, ook wanneer er nog geen frame gepland staat.
///
/// Alleen gebruiken als het resultaat echt een getekend frame nodig heeft.
/// Voor voortgang volstaat `Future<void>.delayed(Duration.zero)`:
/// dat mag niet afhangen van een zichtbaar venster of een stilstaande ticker.
///
/// [allowWarmUpFrame] is voor captures die alleen de geschilderde lagen nodig
/// hebben. Een opwarmframe kan die ook zonder schermverversingssignaal tekenen.
Future<void> waitForUiFrame({
  Duration timeout = const Duration(seconds: 20),
  bool allowWarmUpFrame = false,
}) async {
  final binding = SchedulerBinding.instance;
  binding.scheduleFrame();
  final frame = binding.endOfFrame;
  final warmUp = allowWarmUpFrame
      ? Timer(
          binding.framesEnabled
              ? const Duration(milliseconds: 500)
              : Duration.zero,
          binding.scheduleWarmUpFrame,
        )
      : null;
  try {
    await frame.timeout(timeout);
  } finally {
    warmUp?.cancel();
  }
}
