// Kleine tekstfuncties voor de invulweergave van een formulier.

import 'package:flutter/widgets.dart'
    show TextEditingController, TextEditingValue, TextSelection;

/// De korte naam van een veld, voor de samenvatting en de schermlezer: de eerste
/// niet-lege regel van zijn label zonder Markdown-opmaak. Een label dat geen
/// leesbare tekst heeft (alleen opmaak) geeft [fallback], de id van het veld —
/// liever iets wat de auteur kan terugvinden dan een lege knop.
String formFieldTitle(String labelMarkdown, String fallback) {
  for (final raw in labelMarkdown.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    line = line.replaceFirst(
      RegExp(r'^(?:#{1,6}[ \t]+|>[ \t]*|[-*+][ \t]+)'),
      '',
    );
    line = line.replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
      (m) => m.group(1)!,
    );
    line = line.replaceAll(RegExp(r'[*_`]'), '').trim();
    if (line.isNotEmpty) return line;
  }
  return fallback;
}

/// Een datum als `jjjj-mm-dd` — de enige schrijfwijze die een `date`-veld kent.
String formatFormDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
}

/// Houdt een tekstveld en zijn controller gelijk aan de waarde van buitenaf, zonder
/// de cursor te verplaatsen tijdens het typen.
void syncController(TextEditingController controller, String text) {
  if (controller.text == text) return;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}
