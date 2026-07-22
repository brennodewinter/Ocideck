// De weigering van het classificatiebeleid, in de taal van de gebruiker.
//
// Waarom dit hier staat en niet in de dienst: de vertaallaag sleutelt op
// letterlijke Nederlandse brontekst. Een zin die een TLP-niveau interpoleert
// heeft geen letterlijke vorm, en kan dus per definitie niet opgezocht worden.
// De dienst gaf tot 2026-07-22 kant-en-klaar proza terug en die zin bereikte de
// gebruiker in het Nederlands, wélke taal hij ook had gekozen (#576).
//
// Dat trof precies de verkeerde categorie. Dit zijn de meldingen die je
// tégenhouden: wie ze niet leest, weet niet waarom zijn export niet doorgaat.
//
// De dienst levert nu een reden plus de twee niveaus; hier wordt daar een zin
// van, met `{…}`-plaatshouders zoals `slide_quality_localization.dart` het al
// deed.

import '../models/deck.dart';
import '../services/classification_policy.dart';
import 'app_localizations.dart';

/// De weigeringstekst voor [decision], of null wanneer er niets te weigeren is.
String? exportBlockMessage(AppLocalizations l10n, ExportDecision? decision) {
  if (decision == null || decision.allowed || decision.reason == null) {
    return null;
  }

  // Het label van een niveau is zelf al vertaald; alleen het frame eromheen
  // hoort hier vandaan te komen.
  String label(TlpLevel? level) => level == null
      ? ''
      : level == TlpLevel.none
      ? l10n.d('niet geclassificeerd')
      : level.label;

  return switch (decision.reason!) {
    ExportBlockReason.classificationMissing => l10n.d(
      'Export geblokkeerd door classificatiebeleid: stel een TLP-niveau in voor deze presentatie.',
    ),
    ExportBlockReason.belowMinimum => _fill(
      l10n.d(
        'Export geblokkeerd door classificatiebeleid: dit deck is {deck}, lager dan het vereiste minimum {limit}.',
      ),
      decision,
      label,
    ),
    ExportBlockReason.aboveCeiling => _fill(
      l10n.d(
        'Export geblokkeerd door classificatiebeleid: dit deck is {deck}, hoger dan het toegestane vrijgaveniveau {limit}.',
      ),
      decision,
      label,
    ),
  };
}

String _fill(
  String template,
  ExportDecision decision,
  String Function(TlpLevel?) label,
) => template
    .replaceAll('{deck}', label(decision.deckLevel))
    .replaceAll('{limit}', label(decision.limit));
