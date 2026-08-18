import 'package:markdown/markdown.dart' as md;

import '../utils/footnotes.dart';

/// Voetnoten klaarmaken voor de HTML-export.
///
/// De HTML-export rendert de markdown in de browser met `marked`, en die kent
/// geen voetnoten. Daarom worden ze hiervóór al omgezet: de verwijzing wordt een
/// `<sup>` met een sprong naar de noot, de definitieregels verdwijnen uit de
/// tekst, en de noten komen als genummerde lijst achteraan.
///
/// Achteraan, en niet onderaan de bladzijde — ook wanneer het document om dat
/// laatste vraagt. Een HTML-pagina heeft geen bladzijden, en de CSS die dat wel
/// zou kunnen (`float: footnote` uit CSS Paged Media) wordt door geen enkele
/// browser uitgevoerd. Het verschil staat in KNOWN_LIMITATIONS.md; de
/// LaTeX-export en de Pagina's-weergave doen het wél echt onderaan het blad.
///
/// De tekst van een noot gaat door de markdown-omzetting met HTML-escaping aan,
/// dus wat een auteur schrijft komt er als tekst uit en niet als opmaak van
/// buiten. De uitvoer loopt daarna nog langs DOMPurify in de export zelf.
String documentWithHtmlFootnotes(String markdown, {required String title}) {
  final notes = documentFootnotes(markdown);
  if (notes.isEmpty) return markdown;
  var body = stripFootnoteDefinitions(markdown);
  for (final note in notes) {
    body = body.replaceAll(
      '[^${note.label}]',
      '<sup class="ocideck-fnref" id="fnref-${note.number}">'
          '<a href="#fn-${note.number}">${note.number}</a></sup>',
    );
  }
  final list = StringBuffer()
    ..writeln('<section class="ocideck-footnotes">')
    ..writeln('<h2>${_escape(title)}</h2>')
    ..writeln('<ol>');
  for (final note in notes) {
    list
      ..write('<li id="fn-${note.number}">')
      ..write(_inlineHtml(note.text))
      // Terug naar de plek in de tekst: een noot achteraan is alleen bruikbaar
      // als je ook terug kunt.
      ..write(' <a class="ocideck-fnback" href="#fnref-${note.number}">↩</a>')
      ..writeln('</li>');
  }
  list
    ..writeln('</ol>')
    ..write('</section>');
  return '${body.trimRight()}\n\n$list';
}

/// De inline-markdown van een noot als HTML — vet, cursief, code en links, maar
/// geen alinea's: een noot is één regel in een lijstitem.
String _inlineHtml(String text) => md
    .markdownToHtml(
      text,
      inlineOnly: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    )
    .trim();

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
