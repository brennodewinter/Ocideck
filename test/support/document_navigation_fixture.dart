/// Deelbaar rapport voor hoofdstuksprongen; bevat geen privéverslaginhoud.
String documentNavigationFixture({bool diagrams = true}) {
  final source = StringBuffer();
  for (var chapter = 0; chapter < 40; chapter++) {
    source.writeln('# Hoofdstuk ${chapter.toString().padLeft(2, '0')}\n');
    for (var paragraph = 0; paragraph < 8; paragraph++) {
      source.writeln(
        'Paragraaf $chapter.$paragraph: ${List.filled(4, 'Een **onderbouwde** bevinding met `code`, een [bron](https://example.com) en een toelichting voor het rapport.').join(' ')}\n',
      );
    }
    if (chapter % 5 == 0) {
      source.writeln(
        '| Onderdeel | Waarde |\n| --- | --- |\n| Proef | $chapter |\n',
      );
    }
    if (diagrams && chapter % 10 == 0) {
      source.writeln('```mermaid\ngraph TD; A-->B;\n```\n');
    }
  }
  return source.toString();
}
