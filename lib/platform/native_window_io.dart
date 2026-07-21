import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// De kleinste maat waarop de shell nog werkt.
///
/// OciDeck's hoofdscherm is een drieluik — diastrook, editor, preview — en
/// daaronder vouwen die panelen over elkaar heen. Zonder deze ondergrens kan
/// een gebruiker het venster kleiner slepen dan de app aankan.
const Size minimumWindowSize = Size(1000, 650);

Future<void> configureNativeWindow() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    minimumSize: minimumWindowSize,
    title: 'OciDeck',
  );
  await windowManager.waitUntilReadyToShow(options);

  // Bewust ná `waitUntilReadyToShow` en niet in de callback die die methode
  // aanbiedt: dat is een `VoidCallback`, dus een `async` body erin wordt
  // gestart maar niet afgewacht. `setPreventClose` — de haak waarmee OciDeck
  // bij niet-opgeslagen werk kan vragen wat er moet gebeuren — hing daarmee
  // aan een race met `runApp`. Hier is de volgorde dezelfde en het wachten
  // echt.
  await windowManager.show();
  await windowManager.focus();
  await windowManager.setPreventClose(true);
}
