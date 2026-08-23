import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';
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

/// Sluit de app netjes af — de uitweg voor een gebruiker die niet verder wíl.
///
/// Nodig omdat `configureNativeWindow` `setPreventClose(true)` zet en alleen de
/// shell (`AppShell.onWindowClose`) dat sluiten weer afhandelt. Vóór de shell —
/// bij de toestemmingspoort — luistert er niemand naar de kruis-knop, dus dan
/// zit een gebruiker die niet akkoord gaat klem (#1207). Deze route omzeilt de
/// vensterbewaking: er is op de poort niets opgeslagen om te bewaken.
Future<void> quitApp() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
  await windowManager.destroy();
}
