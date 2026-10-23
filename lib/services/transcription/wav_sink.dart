// Constanten van de duurzame opnamefile (#2516, TRANSCRIPTION.md §3.2).
//
// De sampleklok en de codec staan in de header; er is geen onderhandeling.
// Het schrijven zelf zit in de io-helft: deze laag mag `dart:io` alleen
// daar importeren, anders sleept de web-build een bestandssysteem mee.
const recordingSampleRate = 16000;
const recordingChannels = 1;
const recordingBitsPerSample = 16;

/// Bestandsnaam binnen de sessiemap. Herstel zoekt op deze naam.
const recordingWavName = 'recording.wav';

/// Bovengrens van één opname, gelijk aan de mediacap (§3.2). Een langere
/// opname stopt met een benoemde fout in plaats van de schijf leeg te eten.
const maxRecordingWavBytes = 1024 * 1024 * 1024;
