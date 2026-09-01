import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:ocideck/widgets/slides/previews/callout_overlay.dart'
    show calloutImageProvider;

/// Legt het beeld op [imagePath] in de imagecache, zodat een widget die het
/// daarna opvraagt zijn maat **synchroon** terugkrijgt.
///
/// ── Waarom dit bestaat ──
///
/// `CalloutOverlay` tekent niets vóór de intrinsieke beeldmaat bekend is, en
/// die komt uit een echte decode. Een test die de overlay pompt en dan een
/// vaste tijd wacht, gokt hoe lang die decode duurt. Op de linux-runner — vier
/// kernen, `--concurrency=14` — was 300 ms te krap: `callout_accessibility_test`
/// en `callout_reveal_test` vielen er op 31-08 en 01-09-2026 om (taken 5001 en
/// 5200), met een semantics-boom van drie lege labels als bewijs dat er nog
/// niets getekend was.
///
/// Beter wachten is hier niet het antwoord — de wachttijd wegnemen wel.
/// `resolveIntrinsicSize` roept zijn listener meteen aan wanneer het beeld al
/// in de cache staat, en zet de maat dan nog vóór de eerste `build`. Dat pad
/// bestaat al voor de rasterexports, die hun beelden om exact dezelfde reden
/// voorladen: zonder dat komt de markering pas in het frame dáárna, en die
/// exports vangen er maar één. De test doet nu hetzelfde als de productiecode.
///
/// Er is een tweede reden om het zo te doen in plaats van te pollen. Bij een
/// lege `revealedReferences` tekent de overlay *met opzet* niets — en dat is in
/// de widgetboom niet te onderscheiden van "nog niet gedecodeerd". Er valt daar
/// dus niets aan te wijzen om op te wachten. Voorladen haalt die vraag weg.
///
/// De cachesleutel is het bestandspad ([cappedFileImage]), dus de provider die
/// de overlay zelf aanmaakt raakt dezelfde ingang. Gaat het beeld niet open,
/// dan keert deze functie gewoon terug: de test faalt dan verderop op wat ze
/// werkelijk beweert, niet hier op een time-out.
///
/// Roep dit aan binnen `tester.runAsync` — de decode heeft de echte
/// gebeurtenislus nodig — en vóór de `pumpWidget`.
Future<void> warmImageCache(String imagePath, {String? projectPath}) async {
  final provider = calloutImageProvider(imagePath, projectPath);
  if (provider == null) return;
  final done = Completer<void>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  void finish() {
    stream.removeListener(listener);
    if (!done.isCompleted) done.complete();
  }

  listener = ImageStreamListener((info, _) {
    info.dispose();
    finish();
  }, onError: (_, _) => finish());
  stream.addListener(listener);
  await done.future;
}
