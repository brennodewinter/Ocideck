import 'package:flutter/foundation.dart';

/// Hoe lang de visuele editor wacht met de Markdown-omzetting van het hele
/// document. Kort genoeg dat opslaan en de bronstand de laatste aanslagen
/// nog meenemen zodra je pauzeert, lang genoeg dat een reeks aanslagen één
/// omzetting deelt (#2621).
const kVisualMarkdownFlushDelay = Duration(milliseconds: 300);

/// Haak waarmee de documentlaag een open visuele editor dwingt zijn
/// bron bij te werken vóór iemand die bron leest.
///
/// De editor vult [bind] zolang hij leeft. Autosave, opslaan, export en
/// presenteren zien de notifier, niet de Quill-boom; zonder deze haak
/// zou een aanslag binnen het venster ontbreken in wat er weggeschreven
/// wordt.
class VisualMarkdownFlush {
  VoidCallback? _flush;

  void bind(VoidCallback? flush) => _flush = flush;

  void flush() => _flush?.call();
}
