// `podcast:transcript`-verwijzingen uitlezen (#2931): een kant-en-klaar
// transcript van de maker heeft voorrang op eigen ASR — goedkoper én
// de bedoelde tekst. Hier wordt opgehaalde VTT/SRT/tekst naar
// segmenten en vervolgens de bestaande transcriptdocument-vorm
// gebracht, zodat provenance en tijdstempels er net zo uitzien als bij
// eigen ASR.
import 'dart:convert';

import '../transcription/transcript_document.dart';
import '../transcription/transcription_engine.dart';
import 'feed_models.dart';

/// Ondersteunde `podcast:transcript`-types voor directe overname.
/// Andere types (JSON-varianten, HTML) zijn niet bewezen omgezet en
/// blijven een ASR-route.
bool transcriptLinkUsable(FeedTranscriptLink link) {
  final type = link.type.toLowerCase();
  return type == 'text/vtt' ||
      type == 'application/vtt' ||
      type == 'text/srt' ||
      type == 'application/x-subrip' ||
      type == 'text/plain';
}

/// Maak van opgehaalde transcripttekst een bewerkbaar transcriptdocument.
/// VTT en SRT leveren echte tijdstempels; platte tekst komt als één blok
/// zonder verzonnen tijden. Geeft `null` bij een leeg resultaat — de
/// aanroeper meldt dan dat er niets bruikbaars stond.
String? episodeTranscriptMarkdown({
  required String text,
  required FeedTranscriptLink link,
  required String feedTitle,
  required String episodeTitle,
  required String fetchedAtLabel,
}) {
  final type = link.type.toLowerCase();
  final String body;
  if (type == 'text/plain') {
    body = text.trim();
  } else {
    final segments = type.contains('srt') || type.contains('subrip')
        ? parseSrt(text)
        : parseVtt(text);
    if (segments.isEmpty) return null;
    body = formatTranscriptBody(segments);
  }
  if (body.isEmpty) return null;
  return buildTranscriptMarkdown(
    TranscriptProvenance(
      title: episodeTitle.isEmpty ? feedTitle : episodeTitle,
      sourceLabel: link.url.toString(),
      recordedAt: fetchedAtLabel,
      sourceKindLabel: feedTitle,
      engineLabel: 'podcast:transcript (${link.type})',
      languageCode: link.language,
    ),
    body,
  );
}

/// WebVTT-cues → transcriptsegmenten. Cues met overlappende herhaling
/// (rolling captions) worden op identieke buurttext gededupliceerd;
/// sprekeraanduidingen `<v Naam>` gaan als losse tekstregel verloren —
/// de tijdstempels en woorden zijn de waarheid hier.
List<TranscriptSegment> parseVtt(String text) => _parseCues(text);

/// SRT gebruikt een komma als decimaalscheiding in de cue-timing; de
/// parser accepteert beide tekens, dus dit is dezelfde cue-vorm.
List<TranscriptSegment> parseSrt(String text) => _parseCues(text);

List<TranscriptSegment> _parseCues(String text) {
  final segments = <TranscriptSegment>[];
  String? lastText;
  Duration? pendingStart;
  Duration? pendingEnd;
  final buffer = StringBuffer();

  void flush() {
    final cueText = buffer.toString().trim();
    buffer.clear();
    if (cueText.isEmpty) {
      pendingStart = pendingEnd = null;
      return;
    }
    if (cueText != lastText) {
      segments.add(
        TranscriptSegment(text: cueText, start: pendingStart, end: pendingEnd),
      );
      lastText = cueText;
    }
    pendingStart = pendingEnd = null;
  }

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    final times = _cueTimes(line);
    if (times != null) {
      flush();
      pendingStart = times.$1;
      pendingEnd = times.$2;
      continue;
    }
    if (line.isEmpty ||
        line == 'WEBVTT' ||
        line.startsWith('NOTE') ||
        RegExp(r'^\d+$').hasMatch(line)) {
      continue;
    }
    // Strip cue-tags (<v Speaker>, <b>, <c.klasse>) maar behoud tekst.
    buffer.write(line.replaceAll(RegExp(r'<[^>]+>'), ''));
    buffer.write(' ');
  }
  flush();
  return segments;
}

/// `mm:ss.mmm` of `hh:mm:ss.mmm` aan weerszijden van `-->`; geeft
/// (start, eind) of null als de regel geen cue-timing is.
(Duration, Duration?)? _cueTimes(String line) {
  final match = RegExp(
    r'(\d{1,2}:)?\d{1,2}:\d{2}[.,]\d{1,3}\s*-->\s*(\d{1,2}:)?\d{1,2}:\d{2}[.,]\d{1,3}',
  ).firstMatch(line);
  if (match == null) return null;
  final parts = match.group(0)!.split(RegExp(r'\s*-->\s*'));
  final start = _cueTime(parts[0]);
  final end = _cueTime(parts[1]);
  if (start == null) return null;
  return (start, end);
}

Duration? _cueTime(String token) {
  final match = RegExp(
    r'^(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[.,](\d{1,3})$',
  ).firstMatch(token.trim());
  if (match == null) return null;
  final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
  final minutes = int.parse(match.group(2)!);
  final seconds = int.parse(match.group(3)!);
  var millis = int.parse(match.group(4)!);
  for (var i = match.group(4)!.length; i < 3; i++) {
    millis *= 10;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}
