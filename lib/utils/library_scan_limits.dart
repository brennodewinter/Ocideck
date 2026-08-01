// Gedeelde bovengrenzen voor het recursief doorlopen van een bibliotheek op
// schijf — zowel de deck-bestandenscan (`ImageReferenceService.findDeckFiles`)
// als de afbeeldingskiezer (`ImageLibraryScanner`). Eén plek, zodat een
// gemounte of pathologisch grote map beide paden even hard begrenst (#1049).

/// Diepte-plafond voor een recursieve bibliotheekwandeling: praktisch onbeperkt
/// voor echte mappen, maar een harde bovengrens tegen pathologische bomen.
const int kLibraryScanMaxDepth = 32;

/// Bovengrens op het aantal gevonden bestanden — een vangnet zodat een extreem
/// grote of gemounte map de interface niet laat vastlopen.
const int kLibraryScanMaxFiles = 20000;
