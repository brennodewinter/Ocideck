// Het transcriptdocument: aanmaak, body-grens en de definitieve-pass
// (docs/design/TRANSCRIPTION.md §3.1–3.3).
//
// Drie uitspraken uit het contract sturen dit bestand:
//  * het provenanceblok is gewone tekst — eenmaal geschreven is het inhoud
//    van de auteur, en OciDeck herschrijft het nooit stil;
//  * de vervangbare tekst is alleen wat onder de `---`-scheiding staat:
//    daar mag een definitieve of nieuwe pass schrijven, nergens anders;
//  * een latere modelrun overschrijft nooit stil wat de gebruiker al
//    aanraakte — twijfel is een vraag, geen overwrite.
import 'dart:convert';

import '../../utils/document_front_matter.dart';
import 'transcript_marker.dart';
import 'transcription_engine.dart' show TranscriptSegment;

/// Bovengrens voor de binnenkomende transcripttekst bij een toepassing
/// (§-acceptatie "Begrens invoer-/uitvoergrootte"). 8 MiB platte tekst is
/// zowat honderd uur spraak — ver boven elk reëel resultaat, ver onder wat
/// een pathologische uitslag aan geheugen zou kosten.
const maxTranscriptBodyBytes = 8 * 1024 * 1024;

/// De gegenereerde koppen van het provenanceblok — het contract laat de
/// vertaalkeuze aan de schrijver (§8: "Localising them is a l10n decision
/// like every other generated line"), dus staan ze hier als parameters met
/// de Nederlandse vorm als standaard.
class TranscriptLabels {
  const TranscriptLabels({
    this.heading = 'Transcript —',
    this.source = 'Bron:',
    this.recorded = 'Opgenomen:',
    this.duration = 'Duur:',
    this.engine = 'Engine:',
    this.language = 'Taal:',
    this.missing = 'Ontbrekend:',
  });

  final String heading;
  final String source;
  final String recorded;
  final String duration;
  final String engine;
  final String language;

  /// Voorlabel van de gatenregel — alleen geschreven als de bron die
  /// eerlijk meldde (#2530, callopname met stilte-ticks).
  final String missing;
}

/// Wat het provenanceblok zegt. Alles is al opgemaakte tekst: de aanroeper
/// (de transcriptie-flow, #2515+) kent de taal en de bronnen, dit object
/// alleen de vorm. [audioRelPath] bepaalt óók de marker — zonder pad komt
/// er geen `audio`-attribuut en geen link, alleen de leesbare bronregel.
class TranscriptProvenance {
  const TranscriptProvenance({
    required this.title,
    required this.sourceLabel,
    required this.recordedAt,
    required this.sourceKindLabel,
    this.audioRelPath,
    this.durationLabel,
    this.engineLabel,
    this.languageCode,
    this.gapsLabel,
  });

  /// De naam achter de kop ("Transcript — vergadering 22 oktober").
  final String title;

  /// Leesbare naam van de bron — bij bewaarde audio de bestandsnaam die ook
  /// in de linktekst staat.
  final String sourceLabel;

  /// Opgemaakt opnamemoment, bijv. `2026-10-22 14:03`.
  final String recordedAt;

  /// Leesbare bronsoort ("microfoon", "bestand", …).
  final String sourceKindLabel;

  /// Het `media/`-pad dat in de marker én in de link staat, of null.
  final String? audioRelPath;

  /// Opgemaakte duur ("0:41:12"), null als die onbekend is.
  final String? durationLabel;

  /// Leesbare engine-aanduiding ("whisper.cpp `base` (lokaal)"), of null.
  final String? engineLabel;

  /// Taalcode ("nl"), of null als de engine geen taal rapporteerde.
  final String? languageCode;

  /// Eerlijk gemelde gaten in de bronaudio ("~4 s over 1 bron"), of null.
  /// Staat los van de segmenten: een gat is herkomst, geen spraak.
  final String? gapsLabel;
}

/// Schrijft een transcriptdocument in de vorm van §3.1: marker, kop,
/// provenance als gewone tekst, `---`, en daarna de transcripttekst.
String buildTranscriptMarkdown(
  TranscriptProvenance provenance,
  String body, {
  TranscriptLabels labels = const TranscriptLabels(),
}) {
  final buf = StringBuffer()
    ..writeln(formatTranscriptMarker(audioRelPath: provenance.audioRelPath))
    ..writeln('# ${labels.heading} ${provenance.title}')
    ..writeln();
  if (provenance.audioRelPath != null) {
    buf.writeln(
      '${labels.source} '
      '[${provenance.sourceLabel}](${provenance.audioRelPath})',
    );
  } else {
    buf.writeln('${labels.source} ${provenance.sourceLabel}');
  }
  buf.writeln(
    [
      '${labels.recorded} ${provenance.recordedAt}',
      '${labels.source} ${provenance.sourceKindLabel}',
      if (provenance.durationLabel != null)
        '${labels.duration} ${provenance.durationLabel}',
    ].join(' · '),
  );
  final engineLine = [
    if (provenance.engineLabel != null)
      '${labels.engine} ${provenance.engineLabel}',
    if (provenance.languageCode != null)
      '${labels.language} ${provenance.languageCode}',
  ];
  if (engineLine.isNotEmpty) buf.writeln(engineLine.join(' · '));
  if (provenance.gapsLabel != null) {
    buf.writeln('${labels.missing} ${provenance.gapsLabel}');
  }
  return '$buf\n---\n\n${body.trimRight()}\n';
}

/// Zet enginesegmenten om in de contractvorm: `[h:mm:ss] **Spreker n:**
/// tekst`, één regel per segment — en alleen de delen die de engine echt
/// leverde (§2.4). Zonder tijdstempel geen `[…]`; zonder spreker geen
/// `**…:**`. [speakerLabel] dekt `Spreker`, `microfoon` e.d. — de engine
/// levert de naam, deze functie de plaats.
String formatTranscriptBody(List<TranscriptSegment> segments) => segments
    .map((segment) {
      final prefix = StringBuffer();
      if (segment.start != null) {
        prefix.write('[${_formatTimecode(segment.start!)}] ');
      }
      if (segment.speaker != null) {
        prefix.write('**${segment.speaker}:** ');
      }
      return '$prefix${segment.text}';
    })
    .join('\n');

String _formatTimecode(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Het tekstbereik dat een latere pass mag vervangen: alles onder de eerste
/// `---`-regel na de marker. Null als [source] geen geldig transcript is of
/// de scheiding ontbreekt — dan is er geen veilige plek om te schrijven en
/// hoort elke toepassing een vraag te zijn.
(int start, int end)? transcriptBodySpan(String source) {
  if (detectTranscript(source) is! ValidTranscript) return null;
  final body = splitDocumentFrontMatter(source).body;
  final bodyStart = source.length - body.length;
  var cursor = body.indexOf('\n');
  if (cursor < 0) return null; // alleen de markerregel, geen scheiding
  cursor++;
  while (cursor < body.length) {
    final lineEnd = body.indexOf('\n', cursor);
    final line = lineEnd < 0
        ? body.substring(cursor)
        : body.substring(cursor, lineEnd);
    if (line == '---') {
      final start = lineEnd < 0 ? body.length : lineEnd + 1;
      return (bodyStart + start, source.length);
    }
    if (lineEnd < 0) return null;
    cursor = lineEnd + 1;
  }
  return null;
}

/// De huidige transcripttekst onder de scheiding, of null — zie
/// [transcriptBodySpan] voor de grens.
String? transcriptBodyText(String source) {
  final span = transcriptBodySpan(source);
  return span == null ? null : source.substring(span.$1, span.$2);
}

/// Vervangt de transcripttekst onder de scheiding door [incoming] en laat
/// alles erboven — marker, kop, provenance — byte-getrouw staan.
String applyTranscriptBody(String source, String incoming) {
  final span = transcriptBodySpan(source);
  if (span == null) return source;
  return '${source.substring(0, span.$1)}\n${incoming.trimRight()}\n';
}

/// Wat [planTranscriptUpdate] met een binnenkomende pass besluit.
sealed class TranscriptUpdate {
  const TranscriptUpdate();
}

/// De tekst staat er al — niets te doen.
final class TranscriptUnchanged extends TranscriptUpdate {
  const TranscriptUnchanged();
}

/// Stilletjes toepassen: de gebruiker heeft de vorige tekst niet aangeraakt.
final class TranscriptApply extends TranscriptUpdate {
  const TranscriptApply(this.markdown);

  /// De volledige nieuwe documentsource.
  final String markdown;
}

/// De tekst wijkt af van wat er stond — dat kan een handmatige correctie
/// zijn. De aanroeper toont de vergelijking; stil overschrijven is hier
/// nooit het antwoord.
final class TranscriptConflict extends TranscriptUpdate {
  const TranscriptConflict(this.incoming);

  /// De binnenkomende tekst die met de huidige body botst.
  final String incoming;
}

/// De binnenkomende tekst overschrijdt [maxTranscriptBodyBytes].
final class TranscriptTooLarge extends TranscriptUpdate {
  const TranscriptTooLarge();
}

/// Beslist wat een binnenkomende definitieve of nieuwe pass met het
/// huidige document doet.
///
/// [baseline] is de tekst die de sessie er zelf neerzette — de provisionele
/// livetekst bij een definitieve pass, of de uitslag van de vorige run bij
/// opnieuw transcriberen. Staat de huidige tekst er nog ongemoeid bij, mag
/// de nieuwe hem stil vervangen; wijkt hij af, dan heeft iemand hem
/// aangeraakt en is de enige eerlijke stap de zichtbare vergelijking.
/// Zonder baseline vraagt elke afwijking om bevestiging — te vaak vragen is
/// veilig, stil overschrijven nooit.
TranscriptUpdate planTranscriptUpdate(
  String source,
  String incoming, {
  String? baseline,
}) {
  if (utf8.encode(incoming).length > maxTranscriptBodyBytes) {
    return const TranscriptTooLarge();
  }
  final current = transcriptBodyText(source);
  if (current == null) return TranscriptConflict(incoming);
  if (current.trim() == incoming.trim()) {
    return const TranscriptUnchanged();
  }
  if (baseline != null && current.trim() == baseline.trim()) {
    return TranscriptApply(applyTranscriptBody(source, incoming));
  }
  return TranscriptConflict(incoming);
}
