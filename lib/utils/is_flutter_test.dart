import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'log.dart';

/// Draait dit proces onder `flutter test`?
///
/// `flutter test` zet de omgevingsvariabele `FLUTTER_TEST`. Op web bestaat
/// `Platform` niet; `dart:io` compileert daar wel maar gooit bij gebruik —
/// de `kIsWeb`-vraag gaat vóór, de catch dekt de rest.
///
/// Gebruik dit om paden af te vlakken die onder de nep-async-klok nooit
/// landen (echte isolates, scheduler-taken, netwerkwaakhonden): synchroon
/// uitvoeren geeft dezelfde eindstaat zonder deadlock.
bool get isFlutterTest {
  if (kIsWeb) return false;
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (e) {
    logWarning('isFlutterTest: Platform.environment unavailable', e);
    return false;
  }
}
