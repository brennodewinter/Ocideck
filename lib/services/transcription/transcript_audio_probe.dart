// Of het audiobestand uit de `audio="…"`-verwijzing er nog ligt —
// (docs/design/TRANSCRIPTION.md §3.4). Desktop kijkt via de containment-
// guard op schijf; de stub meldt `null` (niet te verifiëren) zodat web een
// transcript met media-verwijzing niet ten onrechte "audio vermist" toont —
// de `mem:`-route is #2513/#2515's bewijs, niet dit ticket's gok.
export 'transcript_audio_probe_stub.dart'
    if (dart.library.io) 'transcript_audio_probe_io.dart';
