// Wat OciDeck als bewerkbaar tekstbestand ziet, en hoe je zo'n bestand een
// naam geeft zonder het te openen.
//
// Beide vragen komen op meerdere plekken terug — de mapscan, de brede
// schijfscan en het openscherm — en ze moeten daar hetzelfde antwoord geven.
// Stond de extensielijst op drie plekken, dan verscheen een `.txt` in de ene
// zoeklijst wel en in de andere niet, en dat is precies het soort verschil dat
// een gebruiker als "de zoekfunctie werkt niet" ervaart.
library;

import 'package:path/path.dart' as p;

/// De bestandsextensies die OciDeck als bewerkbare Markdown/platte tekst opent.
///
/// `.md` en `.markdown` zijn Markdown; `.txt` staat erbij omdat de documentkant
/// platte tekst byte-getrouw opent en opslaat — een `.txt` blijft daarmee een
/// `.txt` (zie `docs/design/DOCUMENT_MODE.md`). Alles met kleine letters; de
/// vergelijking gebeurt op een genormaliseerde extensie.
const Set<String> kEditableMarkdownExtensions = {'.md', '.markdown', '.txt'};

/// True wanneer [path] op een extensie uit [kEditableMarkdownExtensions] eindigt.
bool isEditableMarkdownFile(String path) =>
    kEditableMarkdownExtensions.contains(p.extension(path).toLowerCase());

/// De eerste kop uit [source], of null wanneer er binnen [scanChars] tekens geen
/// staat.
///
/// Bedoeld als weergavenaam voor een plat document: dat draagt geen `title:` in
/// zijn front matter, maar begint bijna altijd met een kop — en "Kwartaalverslag
/// Q3" zegt in een zoeklijst meer dan `verslag-def-2.md`.
///
/// Alleen het begin van het bestand wordt bekeken: staat er in de eerste
/// [scanChars] tekens geen kop, dan is er geen titel die de gebruiker als titel
/// zou herkennen. Een kop binnen een ```-blok telt niet mee — dat is code, geen
/// titel.
String? firstMarkdownHeading(String source, {int scanChars = 4096}) {
  if (source.isEmpty) return null;
  final head = source.length <= scanChars
      ? source
      : source.substring(0, scanChars);
  final lines = head
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  var inFrontMatter = lines.isNotEmpty && lines.first.trim() == '---';
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (inFrontMatter) {
      // De sluitende `---` van de front matter; de openende is regel 0 zelf.
      if (i > 0 && (trimmed == '---' || trimmed == '...')) {
        inFrontMatter = false;
      }
      continue;
    }
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final match = RegExp(r'^ {0,3}(#{1,6})\s+(.*)$').firstMatch(line);
    if (match == null) continue;
    // Een sluitende hekjes-reeks ("## Titel ##") hoort niet in de naam.
    final text = match.group(2)!.replaceFirst(RegExp(r'\s*#+\s*$'), '').trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}
