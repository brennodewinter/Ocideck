import 'package:flutter/scheduler.dart';

/// Wacht begrensd op één frame, ook wanneer er nog geen frame gepland staat.
///
/// Alleen gebruiken als het resultaat echt een getekend frame nodig heeft.
/// Voor voortgang volstaat `Future<void>.delayed(Duration.zero)`:
/// dat mag niet afhangen van een zichtbaar venster of een stilstaande ticker.
Future<void> waitForUiFrame({Duration timeout = const Duration(seconds: 20)}) {
  final binding = SchedulerBinding.instance;
  binding.scheduleFrame();
  return binding.endOfFrame.timeout(timeout);
}
