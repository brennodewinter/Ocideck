// Wat de PDF-export van een document nodig heeft uit de schil: de gebundelde
// lettersnede voor tekens buiten Latin-1, de vertaalde teksten, en de zin die de
// gebruiker te zien krijgt als er iets níet gezet kon worden.
//
// Staat los van `document_editor_screen.dart` omdat de PDF-lagen bewust
// Flutter-vrij zijn (zie `lib/services/pdf/`): het laden van een asset en het
// opzoeken van een vertaling zijn juist wél schilwerk, en horen dus hier.

import 'package:flutter/services.dart' show ByteData, rootBundle;

import '../../l10n/app_localizations.dart';
import '../../services/pdf/document_pdf_export.dart';

/// Het gebundelde lettertype waar tekens buiten Latin-1 op terugvallen.
///
/// De PDF zelf wordt gezet met de veertien standaardsneden die elke lezer heeft
/// — die dragen een echte vette en cursieve snede en kosten geen bytes, maar ze
/// reiken niet verder dan Latin-1. Roboto vangt de rest op: Latijns uitgebreid,
/// Grieks, Cyrillisch. Zie de kop van `document_pdf_fonts.dart`.
///
/// Lukt het laden niet, dan gaat de export gewoon door: [DocumentPdfResult]
/// meldt dan welke tekens ontbreken, en de schil zegt dat tegen de gebruiker.
Future<ByteData?> loadPdfFallbackFont() async {
  try {
    return await rootBundle.load('assets/fonts/Roboto-Variable.ttf');
  } on Exception {
    return null;
  }
}

/// De teksten die de PDF-lagen zelf niet kennen, in de taal van de interface.
DocumentPdfLabels documentPdfLabels(AppLocalizations l10n) => DocumentPdfLabels(
  tocTitle: l10n.d('Inhoud'),
  footnotesTitle: l10n.d('Noten'),
  // Eerlijk benoemen wat er staat: niet het diagram maar de bron ervan. Een
  // PDF kent geen JavaScript, dus wat de HTML-export tekent kan hier alleen
  // leesbaar mee — zie [PdfVerbatimBlock].
  mathLabel: l10n.d('Formule (bron)'),
  mermaidLabel: l10n.d('Diagram (bron)'),
  chartLabel: l10n.d('Grafiek (bron)'),
);

/// De melding bij tekens waarvoor geen enkele beschikbare snede een vorm had.
///
/// Noemt de tekens zelf, want "sommige tekens" laat de gebruiker zoeken in zijn
/// eigen document. Bij veel verschillende tekens wordt de lijst afgekapt — de
/// boodschap is dán al aangekomen.
String unsupportedCharactersMessage(AppLocalizations l10n, Set<int> runes) {
  const maxShown = 12;
  final shown = runes.take(maxShown).map(String.fromCharCode).join(' ');
  final suffix = runes.length > maxShown ? ' …' : '';
  return '${l10n.d('Deze tekens konden niet in de PDF worden gezet en ontbreken erin:')} '
      '$shown$suffix. '
      '${l10n.d('Exporteer naar HTML of LaTeX als ze in het document horen.')}';
}
