import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show ByteData, rootBundle;

/// Laadt de gebundelde terugvalsneden voor PDF-tekst met tekens buiten Latin-1.
/// De volgorde blijft Roboto, Inter en Noto Sans Math, gevolgd door het
/// eventuele lokale lettertype dat de gebruiker heeft ingesteld.
Future<List<ByteData>> loadPdfFallbackFonts({
  /// #2753: een lettertypebestand dat de auteur zelf op de eigen machine
  /// aanwees, voor tekens die de gebundelde snedes niet hebben. Alleen een
  /// subset gaat mee in de PDF; de licentie van het bestand moet insluiten
  /// toestaan — dat staat in het exportdialoog, OciDeck controleert het niet.
  String? userFontPath,
}) async {
  const paths = [
    'assets/fonts/Roboto-Variable.ttf',
    'assets/fonts/Inter-Variable.ttf',
    'assets/fonts/NotoSansMath-subset.ttf',
  ];
  final fonts = <ByteData>[];
  for (final path in paths) {
    try {
      fonts.add(await rootBundle.load(path));
    } on Exception {
      // Gebruik de beschikbare sneden als een gebundeld font niet laadt.
      continue;
    }
  }
  if (userFontPath != null && !kIsWeb) {
    try {
      fonts.add(ByteData.sublistView(await File(userFontPath).readAsBytes()));
    } on Exception {
      // Gebruik de gebundelde sneden als het lokale font niet leesbaar is.
    }
  }
  return fonts;
}
