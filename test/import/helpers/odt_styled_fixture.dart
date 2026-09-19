// Een `.odt` in de vorm waarin LibreOffice Writer er een schrijft:
// `font-face-decls`, een `default-style`, `Standard`, `Heading` en
// `Heading_20_1..3` met `parent-style-name`, en master pages met een
// koptekst/voettekst (`Standard`, voor elke bladzijde) en een titelblad
// (`First_20_Page`, met `next-style-name`). Het spiegelbeeld van
// `docx_styled_fixture.dart`, zodat de ODT-route dezelfde toetsen doorstaat.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';

/// Waar een kader staat.
class OdtFrame {
  const OdtFrame({
    required this.widthCm,
    required this.heightCm,
    this.anchor = 'paragraph',
    this.xCm,
    this.yCm,
    this.horizontalPos,
  });

  final double widthCm;
  final double heightCm;

  /// `paragraph`, `char`, `as-char` of `page`.
  final String anchor;
  final double? xCm;
  final double? yCm;

  /// `left`/`right`/`center` via de grafische stijl.
  final String? horizontalPos;
}

Uint8List odtStyledFixture({
  String bodyFont = 'Liberation Serif',
  String headingFont = 'Liberation Sans',
  String? bodyColor = '#000000',
  String? heading1Color = '#00464f',
  String? heading2Color = '#1e78b5',
  String? footerText = 'Information security policy',
  bool footerPageNumber = true,
  String? footerAlign,
  Uint8List? footerLogo,
  OdtFrame? footerFrame,
  bool footerLogoSvgOnly = false,
  Uint8List? headerLogo,
  OdtFrame? headerFrame,
  String? headerText,
  Uint8List? firstPageLogo,
  Uint8List? bodyRepeatedLogo,
  int bodyRepeatCount = 0,
}) {
  final parts = <String, List<int>>{};
  var pictureIndex = 1;
  String addPicture(Uint8List bytes, {String ext = 'png'}) {
    final path = 'Pictures/logo${pictureIndex++}.$ext';
    parts[path] = bytes;
    return path;
  }

  String frame(
    String href,
    OdtFrame at, {
    String styleName = 'fr1',
    String name = 'Image1',
  }) {
    final pos = at.anchor == 'page'
        ? 'svg:x="${at.xCm ?? 0}cm" svg:y="${at.yCm ?? 0}cm" '
        : '';
    return '<draw:frame draw:style-name="$styleName" draw:name="$name" '
        'text:anchor-type="${at.anchor}" $pos'
        'svg:width="${at.widthCm}cm" svg:height="${at.heightCm}cm">'
        '<draw:image xlink:href="$href" xlink:type="simple" '
        'xlink:show="embed" xlink:actuate="onLoad"/>'
        '</draw:frame>';
  }

  String color(String? hex) => hex == null ? '' : ' fo:color="$hex"';

  // Grafische stijlen voor de kaders (horizontale positie).
  final graphicStyles = StringBuffer();
  void graphicStyle(String name, String? horizontalPos) {
    graphicStyles.write(
      '<style:style style:name="$name" style:family="graphic">'
      '<style:graphic-properties '
      '${horizontalPos == null ? '' : 'style:horizontal-pos="$horizontalPos" '}'
      'style:vertical-pos="top"/></style:style>',
    );
  }

  // Koptekst van de standaardmaster.
  final header = StringBuffer();
  if (headerText != null) {
    header.write('<text:p text:style-name="Header">$headerText</text:p>');
  }
  if (headerLogo != null) {
    final at = headerFrame ?? const OdtFrame(widthCm: 3, heightCm: 1);
    graphicStyle('frH', at.horizontalPos);
    header.write(
      '<text:p text:style-name="Header">'
      '${frame(addPicture(headerLogo), at, styleName: 'frH', name: 'Logo')}'
      '</text:p>',
    );
  }
  // Voettekst van de standaardmaster: beeldmerk, tekst, paginanummer.
  final footer = StringBuffer('<text:p text:style-name="Footer">');
  if (footerLogo != null) {
    final at =
        footerFrame ??
        const OdtFrame(
          widthCm: 0.9,
          heightCm: 0.82,
          anchor: 'page',
          xCm: 19.0,
          yCm: 28.2,
        );
    graphicStyle('frF', at.horizontalPos);
    // Alleen-SVG: echte vectorbytes, want de lezer kijkt naar de inhoud en
    // niet naar de extensie.
    final href = footerLogoSvgOnly
        ? addPicture(
            Uint8List.fromList(
              utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'),
            ),
            ext: 'svg',
          )
        : addPicture(footerLogo);
    footer.write(frame(href, at, styleName: 'frF', name: 'Mark'));
  }
  if (footerText != null) footer.write(footerText);
  if (footerPageNumber) {
    footer.write(
      '<text:tab/><text:page-number text:select-page="current">2'
      '</text:page-number>',
    );
  }
  footer.write('</text:p>');
  // Titelbladmaster met het woordmerk.
  final firstHeader = StringBuffer();
  if (firstPageLogo != null) {
    firstHeader.write(
      '<text:p text:style-name="Header">'
      '${frame(addPicture(firstPageLogo), const OdtFrame(widthCm: 6.1, heightCm: 1.9), name: 'Wordmark')}'
      '</text:p>',
    );
  }

  parts['styles.xml'] = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-styles xmlns:office="$_office" xmlns:text="$_text" '
    'xmlns:style="$_style" xmlns:fo="$_fo" xmlns:draw="$_draw" '
    'xmlns:svg="$_svg" xmlns:xlink="$_xlink">'
    '<office:font-face-decls>'
    '<style:font-face style:name="$bodyFont" svg:font-family="&apos;$bodyFont&apos;"/>'
    '<style:font-face style:name="$headingFont" svg:font-family="&apos;$headingFont&apos;"/>'
    '</office:font-face-decls>'
    '<office:styles>'
    '<style:default-style style:family="paragraph">'
    '<style:text-properties style:font-name="$bodyFont" fo:font-size="12pt"/>'
    '</style:default-style>'
    '<style:style style:name="Standard" style:family="paragraph" style:class="text">'
    '<style:text-properties${color(bodyColor)}/></style:style>'
    '<style:style style:name="Heading" style:family="paragraph" '
    'style:parent-style-name="Standard" style:class="text">'
    '<style:text-properties style:font-name="$headingFont" fo:font-size="14pt"/>'
    '</style:style>'
    '<style:style style:name="Heading_20_1" style:display-name="Heading 1" '
    'style:family="paragraph" style:parent-style-name="Heading" '
    'style:default-outline-level="1" style:class="text">'
    '<style:text-properties fo:font-size="130%" fo:font-weight="bold"${color(heading1Color)}/>'
    '</style:style>'
    '<style:style style:name="Heading_20_2" style:display-name="Heading 2" '
    'style:family="paragraph" style:parent-style-name="Heading" '
    'style:default-outline-level="2" style:class="text">'
    '<style:text-properties fo:font-size="115%" fo:font-weight="bold"${color(heading2Color)}/>'
    '</style:style>'
    // Kop 3 erft de kleur van Kop 2.
    '<style:style style:name="Heading_20_3" style:display-name="Heading 3" '
    'style:family="paragraph" style:parent-style-name="Heading_20_2" '
    'style:default-outline-level="3" style:class="text"/>'
    '<style:style style:name="Footer" style:family="paragraph" '
    'style:parent-style-name="Standard" style:class="extra">'
    '<style:paragraph-properties'
    '${footerAlign == null ? '' : ' fo:text-align="$footerAlign"'}/>'
    '</style:style>'
    '<style:style style:name="Header" style:family="paragraph" '
    'style:parent-style-name="Standard" style:class="extra"/>'
    '</office:styles>'
    '<office:automatic-styles>'
    '<style:page-layout style:name="Mpm1"><style:page-layout-properties '
    'fo:page-width="21.001cm" fo:page-height="29.7cm" '
    'fo:margin-top="2cm" fo:margin-bottom="2cm" fo:margin-left="2cm" '
    'fo:margin-right="2cm"/></style:page-layout>'
    '$graphicStyles'
    '</office:automatic-styles>'
    '<office:master-styles>'
    '<style:master-page style:name="Standard" style:page-layout-name="Mpm1">'
    '${header.isEmpty ? '' : '<style:header>$header</style:header>'}'
    '<style:footer>$footer</style:footer>'
    '</style:master-page>'
    '<style:master-page style:name="First_20_Page" style:display-name="First Page" '
    'style:page-layout-name="Mpm1" style:next-style-name="Standard">'
    '${firstHeader.isEmpty ? '' : '<style:header>$firstHeader</style:header>'}'
    '</style:master-page>'
    '</office:master-styles>'
    '</office:document-styles>',
  );

  // Body: kop, alinea, en eventueel het herhaalde beeld per bladzijde.
  final body = StringBuffer(
    '<text:h text:style-name="Heading_20_1" text:outline-level="1">Beleid</text:h>'
    '<text:p text:style-name="Standard">Een alinea.</text:p>',
  );
  final autoStyles = StringBuffer();
  if (bodyRepeatedLogo != null && bodyRepeatCount > 0) {
    final href = addPicture(bodyRepeatedLogo);
    autoStyles.write(
      '<style:style style:name="Pbreak" style:family="paragraph" '
      'style:parent-style-name="Standard">'
      '<style:paragraph-properties fo:break-before="page"/></style:style>'
      '<style:style style:name="frB" style:family="graphic">'
      '<style:graphic-properties style:vertical-pos="top"/></style:style>',
    );
    for (var i = 0; i < bodyRepeatCount; i++) {
      final styleName = i == 0 ? 'Standard' : 'Pbreak';
      body.write(
        '<text:p text:style-name="$styleName">'
        '${frame(
          href,
          const OdtFrame(widthCm: 2.5, heightCm: 0.8, anchor: 'page', xCm: 1.5, yCm: 1.0),
          styleName: 'frB',
          name: 'Mark$i',
        )}'
        'Bladzijde ${i + 1}</text:p>',
      );
    }
  }
  parts['content.xml'] = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-content xmlns:office="$_office" xmlns:text="$_text" '
    'xmlns:table="$_table" xmlns:xlink="$_xlink" xmlns:fo="$_fo" '
    'xmlns:style="$_style" xmlns:draw="$_draw" xmlns:svg="$_svg">'
    '<office:automatic-styles>$autoStyles</office:automatic-styles>'
    '<office:body><office:text>$body</office:text></office:body>'
    '</office:document-content>',
  );
  parts['META-INF/manifest.xml'] = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">'
    '<manifest:file-entry manifest:full-path="/" '
    'manifest:media-type="application/vnd.oasis.opendocument.text"/>'
    '</manifest:manifest>',
  );

  final archive = Archive();
  parts.forEach((name, content) {
    archive.addFile(ArchiveFile.bytes(name, Uint8List.fromList(content)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
