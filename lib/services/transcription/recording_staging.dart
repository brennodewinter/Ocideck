// De staginggrens voor opnames (docs/design/TRANSCRIPTION.md §3.2).
//
// Een opname schrijft vanaf de eerste seconde naar een eigen stagingmap in
// de OS-temp — dezelfde staging die een gekozen afbeelding krijgt vóór de
// eerste save (FILE_FORMAT.md §1) — zodat een crash nooit meer kost dan de
// staart. Deze interface dekt het hele leven: aanmaken, per sessie
// weggooien, verlopen sporen vegen en alles wissen. Desktop krijgt de
// `_io`-versie, web de no-op stub: daar leven opnames in de `mem:`-assetstore
// en sterven ze mee met het tabblad — een weesmap kan er niet bestaan.
export 'recording_staging_stub.dart'
    if (dart.library.io) 'recording_staging_io.dart';
