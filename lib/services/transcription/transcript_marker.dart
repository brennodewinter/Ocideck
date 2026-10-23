// De `<!-- transcript -->`-marker: grammatica, herkenning en melding
// (docs/design/TRANSCRIPTION.md §3.1, FILE_FORMAT.md §14.x).
//
// Een transcript is een gewoon document; de marker op de eerste regel van
// de body (direct onder de front matter, als die er is) is het enige wat
// OciDeck ervan bezit. Dezelfde regel als bij `<!-- form -->`: een marker die
// er bijna uitziet als een marker wordt gemeld, niet stilletjes genegeerd —
// een typefout die een regel gewoon commentaar maakt zou het transcript
// onzichtbaar verzwakken.
import '../../utils/document_front_matter.dart';

/// De enige markerversie die deze code leest en schrijft. Hogere versies zijn
//  door een nieuwer OciDeck geschreven: rapporteren en als gewoon document
//  behandelen, nooit stil interpreteren.
const transcriptMarkerVersion = 1;

/// Schrijft de canonieke markerregel. [audioRelPath] is het
//  project-relatieve `media/`-pad of null als de bron niet bewaard bleef.
String formatTranscriptMarker({String? audioRelPath}) => audioRelPath == null
    ? '<!-- transcript version=$transcriptMarkerVersion -->'
    : '<!-- transcript version=$transcriptMarkerVersion '
          'audio="$audioRelPath" -->';

/// Een regel die precies één geldige transcript-marker is. Maximaal drie
/// inspringende blanks en restwit aan het einde — dezelfde tolerantie als de
/// form-grammatica. Alles dat hier niet aan voldoet maar toch op een marker
/// lijkt is [_almostMarkerLine]: die wordt gemeld.
final transcriptMarkerLinePattern = RegExp(
  r'^[ \t]{0,3}<!-- transcript version=(\d+)(?: audio="([^"]*)")? -->[ \t]*$',
);

/// "Bijna een marker": een HTML-commentaarregel waarin `transcript` voorkomt
/// maar die de grammatica niet haalt — gemist `version`, een schrijffout in
/// het sleutelwoord, een verkeerd geplaatste marker. De §14.14-regel:
/// rapporteren, niet negeren.
final _almostMarkerLine = RegExp(r'<!--[^\n]*?transcript[^\n]*?-->');

/// Waarom een marker niet als transcript geldt. De UI zet er een
/// menslezende zin bij; hier woont alleen het feit.
enum TranscriptMarkerIssueKind {
  /// De marker staat niet op de eerste regel van de body — het contract
  /// eist die plek, zodat geen enkele andere regel hem kan overnemen.
  misplaced,

  /// Meer dan één geldige marker — "at most once" uit het contract.
  duplicate,

  /// Een commentaarregel die op de marker lijkt maar de grammatica mist.
  malformed,

  /// Het `audio`-attribuut wijst buiten `media/` of probeert te ontsnappen —
  /// dezelfde containment-regel als elke andere assetverwijzing.
  unsafeAudioPath,

  /// Een versie die deze OciDeck niet kent — geschreven door een nieuwere.
  unsupportedVersion,
}

class TranscriptMarkerIssue {
  const TranscriptMarkerIssue(this.kind, this.lineIndex);

  final TranscriptMarkerIssueKind kind;

  /// Regelnummer in de body (0-gebaseerd) waar de melding over gaat.
  final int lineIndex;
}

/// Een gelezen, geldige marker. [line] is de verbatim regel zoals hij in het
/// bestand staat — hij gaat byte-getrouw terug, ook al was de inspringing
/// niet canoniek.
class TranscriptMarker {
  const TranscriptMarker({
    required this.version,
    required this.audioPath,
    required this.line,
  });

  final int version;

  /// Het `media/`-pad uit `audio="…"`, of null als de bron niet bewaard is.
  final String? audioPath;

  final String line;
}

/// De uitslag van [detectTranscript].
sealed class TranscriptDetection {
  const TranscriptDetection();
}

/// Geen marker, geen transcript — een gewoon document.
final class NoTranscript extends TranscriptDetection {
  const NoTranscript();
}

/// Eén geldige marker op de vereiste plek.
final class ValidTranscript extends TranscriptDetection {
  const ValidTranscript(this.marker);

  final TranscriptMarker marker;
}

/// Minstens één transcript-commentaar gevonden, maar geen toegestane marker:
/// gemeld én als gewoon document behandeld — de rauwe regels blijven zichtbaar.
final class MalformedTranscript extends TranscriptDetection {
  const MalformedTranscript(this.issues);

  final List<TranscriptMarkerIssue> issues;
}

/// Herkent het transcript aan zijn marker, volgens §3.1: hooguit één
/// `<!-- transcript version=1 … -->`, als eerste regel van de body.
///
/// [source] is de hele documenttekst — een eventueel front-matterblok wordt
/// via [splitDocumentFrontMatter] overgeslagen, dezelfde grens als de
/// documenteditor zelf hanteert.
TranscriptDetection detectTranscript(String source) {
  final lines = splitDocumentFrontMatter(source).body.split('\n');
  TranscriptMarker? marker;
  final issues = <TranscriptMarkerIssue>[];

  for (var i = 0; i < lines.length; i++) {
    final match = transcriptMarkerLinePattern.firstMatch(lines[i]);
    if (match != null) {
      if (i != 0) {
        issues.add(
          TranscriptMarkerIssue(
            marker == null
                ? TranscriptMarkerIssueKind.misplaced
                : TranscriptMarkerIssueKind.duplicate,
            i,
          ),
        );
        continue;
      }
      final version = int.parse(match.group(1)!);
      if (version != transcriptMarkerVersion) {
        issues.add(
          const TranscriptMarkerIssue(
            TranscriptMarkerIssueKind.unsupportedVersion,
            0,
          ),
        );
        continue;
      }
      final audio = match.group(2);
      if (audio != null && !_isContainedMediaPath(audio)) {
        issues.add(
          const TranscriptMarkerIssue(
            TranscriptMarkerIssueKind.unsafeAudioPath,
            0,
          ),
        );
        continue;
      }
      marker = TranscriptMarker(
        version: version,
        audioPath: audio,
        line: lines[i],
      );
    } else if (_almostMarkerLine.hasMatch(lines[i])) {
      issues.add(TranscriptMarkerIssue(TranscriptMarkerIssueKind.malformed, i));
    }
  }

  if (issues.isNotEmpty) return MalformedTranscript(issues);
  if (marker != null) return ValidTranscript(marker);
  return const NoTranscript();
}

/// Zet `audio="<rel>"` op de marker van [source] — de bewaarkeuze die bij
/// Opslaan landt (#2515, §3.2). Alleen op een geldige marker die nog géén
/// audio droeg én een pad dat de containment-regel haalt; al het andere
/// levert null, de aanroeper schrijft dan ongewijzigd door.
String? withTranscriptAudioLink(String source, String audioRelPath) {
  if (!_isContainedMediaPath(audioRelPath)) return null;
  final detection = detectTranscript(source);
  if (detection is! ValidTranscript || detection.marker.audioPath != null) {
    return null;
  }
  // De markerregel is verbatim bekend — één vervanging, de rest van het
  // document blijft byte-getrouw.
  return source.replaceFirst(
    detection.marker.line,
    formatTranscriptMarker(audioRelPath: audioRelPath),
  );
}

/// De containment-regel voor `audio="…"`: een relatief pad in `media/`,
/// zonder absolute vorm, schema, schijfletter of `..`-segment. Lexicaal —
/// de echte bestandscheck gebeurt bij het lezen (zie `transcript_audio_probe`).
bool _isContainedMediaPath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.contains(':') ||
      !path.startsWith('media/') ||
      path.endsWith('/')) {
    return false;
  }
  return !path.split('/').contains('..');
}
