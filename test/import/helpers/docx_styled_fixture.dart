// Een `.docx` in de vorm waarin Word er een schrijft: thema met major/minor-
// letter en accentkleur, stijlen die via `basedOn` en `asciiTheme` naar dat
// thema verwijzen, een titelblad (`w:titlePg`) met een eigen koptekst, een
// standaardvoettekst met een verankerd beeldmerk, een tekstkader en een
// `PAGE`-veld. Dit is de vorm van het echte beleidsdocument waarop #2119 is
// ontworpen; het echte bestand is vertrouwelijk en staat niet in de repo.
//
// Elk onderdeel is uit te zetten of te variëren, zodat één bouwer alle
// gevallen dekt: geen thema, geen voettekst, gecentreerd logo, herhaald beeld
// in de body.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _wp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';
const _mc = 'http://schemas.openxmlformats.org/markup-compatibility/2006';

/// Een klein, echt PNG-beeld (groen vierkant), zodat de hash en de
/// rastercontrole op echte bytes werken.
Uint8List fixtureLogoPng({int width = 40, int height = 32, int seed = 1}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(20 * seed, 120, 90));
  return Uint8List.fromList(img.encodePng(image));
}

/// Waar een verankerd beeld staat, in EMU ten opzichte van de bladzijde.
class FixtureAnchor {
  const FixtureAnchor({
    required this.xEmu,
    required this.yEmu,
    required this.cxEmu,
    required this.cyEmu,
    this.alignH,
  });

  final int xEmu;
  final int yEmu;
  final int cxEmu;
  final int cyEmu;

  /// `left`/`right`/`center`: dan geldt de uitlijning in plaats van [xEmu].
  final String? alignH;
}

/// Bouwt de `.docx`.
///
/// [defaultFooterLogo] is het beeldmerk in de standaardvoettekst (op elke
/// bladzijde na het titelblad); [firstHeaderLogo] het woordmerk op het
/// titelblad. [bodyRepeatedLogo] plakt hetzelfde beeld [bodyRepeatCount] keer
/// verankerd in de body, gescheiden door harde pagina-einden.
Uint8List docxStyledFixture({
  bool withTheme = true,
  String majorFont = 'Aptos',
  String minorFont = 'Aptos Light',
  String accent1 = '00464F',
  String? heading1Color = '00464F',
  String? heading2Color = '1E78B5',
  String? bodyColor = '000000',
  String? heading1Font,
  bool titlePage = true,
  Uint8List? firstHeaderLogo,
  Uint8List? defaultFooterLogo,
  FixtureAnchor? defaultFooterAnchor,
  Uint8List? defaultHeaderInlineLogo,
  String? defaultHeaderJc,
  String? footerText = 'Information security policy',
  bool footerPageField = true,
  String? headerText,
  Uint8List? bodyRepeatedLogo,
  int bodyRepeatCount = 0,
  FixtureAnchor? bodyAnchor,
  bool svgOnlyFooterLogo = false,
  String? packageTitle,
}) {
  final parts = <String, List<int>>{};
  if (packageTitle != null) {
    parts['docProps/core.xml'] = _utf8(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties '
      'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>$packageTitle</dc:title><dc:creator>Fixture</dc:creator>'
      '</cp:coreProperties>',
    );
  }
  final docRels = StringBuffer();
  var nextRid = 20;
  String addDocRel(String type, String target) {
    final rid = 'rId${nextRid++}';
    docRels.write(
      '<Relationship Id="$rid" Type="$_r/$type" Target="$target"/>',
    );
    return rid;
  }

  // --- Thema ---
  if (withTheme) {
    parts['word/theme/theme1.xml'] = _utf8(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<a:theme xmlns:a="$_a" name="Fixture"><a:themeElements>'
      '<a:clrScheme name="Fixture">'
      '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
      '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
      '<a:dk2><a:srgbClr val="312F2D"/></a:dk2>'
      '<a:lt2><a:srgbClr val="FFFFFF"/></a:lt2>'
      '<a:accent1><a:srgbClr val="$accent1"/></a:accent1>'
      '<a:accent2><a:srgbClr val="66B7E7"/></a:accent2>'
      '</a:clrScheme>'
      '<a:fontScheme name="Fixture">'
      '<a:majorFont><a:latin typeface="$majorFont"/><a:ea typeface=""/>'
      '<a:cs typeface=""/></a:majorFont>'
      '<a:minorFont><a:latin typeface="$minorFont"/><a:ea typeface=""/>'
      '<a:cs typeface=""/></a:minorFont>'
      '</a:fontScheme></a:themeElements></a:theme>',
    );
    addDocRel('theme', 'theme/theme1.xml');
  }

  // --- Stijlen: Nederlandse styleId's (Kop1) met de OOXML-naam (heading 1),
  // zoals een gelokaliseerd Word ze schrijft. ---
  String rFonts(String? named) => named != null
      ? '<w:rFonts w:ascii="$named" w:hAnsi="$named"/>'
      : '<w:rFonts w:asciiTheme="majorHAnsi" w:hAnsiTheme="majorHAnsi"/>';
  String color(String? hex) =>
      hex == null ? '' : '<w:color w:val="$hex" w:themeColor="accent1"/>';
  parts['word/styles.xml'] = _utf8(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="$_w">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:asciiTheme="minorHAnsi" w:hAnsiTheme="minorHAnsi"/>'
    '${color(bodyColor)}'
    '</w:rPr></w:rPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Standaard">'
    '<w:name w:val="Normal"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Kop1"><w:name w:val="heading 1"/>'
    '<w:basedOn w:val="Standaard"/>'
    '<w:rPr>${rFonts(heading1Font)}${color(heading1Color)}<w:b/>'
    '<w:sz w:val="40"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Kop2"><w:name w:val="heading 2"/>'
    '<w:basedOn w:val="Standaard"/>'
    '<w:rPr>${rFonts(null)}${color(heading2Color)}<w:b/></w:rPr></w:style>'
    // Kop 3 erft alles van Kop 2 via basedOn: geen eigen rPr.
    '<w:style w:type="paragraph" w:styleId="Kop3"><w:name w:val="heading 3"/>'
    '<w:basedOn w:val="Kop2"/></w:style>'
    '</w:styles>',
  );
  addDocRel('styles', 'styles.xml');

  // --- Media + kop-/voettekstdelen ---
  var mediaIndex = 1;
  final drawingParts = <String, StringBuffer>{};
  final ridsPerPart = <String, int>{};
  String addMedia(String part, Uint8List bytes, {String ext = 'png'}) {
    final name = 'media/image${mediaIndex++}.$ext';
    parts['word/$name'] = bytes;
    final rels = drawingParts.putIfAbsent(part, StringBuffer.new);
    final n = (ridsPerPart[part] ?? 0) + 1;
    ridsPerPart[part] = n;
    // Het document zelf deelt zijn nummering met de hoofdrelaties (rId20+).
    final rid = part == 'document.xml' ? 'rId${100 + n}' : 'rId$n';
    rels.write('<Relationship Id="$rid" Type="$_r/image" Target="$name"/>');
    return rid;
  }

  String inlinePicture(String rid, int cx, int cy, {String? jc}) =>
      '<w:p>${jc == null ? '' : '<w:pPr><w:jc w:val="$jc"/></w:pPr>'}'
      '<w:r><w:drawing><wp:inline xmlns:wp="$_wp">'
      '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="1" name="Graphic 1"/>'
      '${_graphic(rid)}</wp:inline></w:drawing></w:r></w:p>';

  String anchoredPicture(String rid, FixtureAnchor at) =>
      '<w:r><w:drawing><wp:anchor xmlns:wp="$_wp" behindDoc="0">'
      '<wp:simplePos x="0" y="0"/>'
      '<wp:positionH relativeFrom="page">'
      '${at.alignH != null ? '<wp:align>${at.alignH}</wp:align>' : '<wp:posOffset>${at.xEmu}</wp:posOffset>'}'
      '</wp:positionH>'
      '<wp:positionV relativeFrom="page"><wp:posOffset>${at.yEmu}</wp:posOffset>'
      '</wp:positionV>'
      '<wp:extent cx="${at.cxEmu}" cy="${at.cyEmu}"/><wp:wrapNone/>'
      '<wp:docPr id="2" name="Graphic 2"/>'
      '${_graphic(rid)}</wp:anchor></w:drawing></w:r>';

  String svgOnlyPicture(String rid, FixtureAnchor at) =>
      '<w:r><w:drawing><wp:anchor xmlns:wp="$_wp" behindDoc="0">'
      '<wp:simplePos x="0" y="0"/>'
      '<wp:positionH relativeFrom="page"><wp:posOffset>${at.xEmu}</wp:posOffset>'
      '</wp:positionH>'
      '<wp:positionV relativeFrom="page"><wp:posOffset>${at.yEmu}</wp:posOffset>'
      '</wp:positionV>'
      '<wp:extent cx="${at.cxEmu}" cy="${at.cyEmu}"/><wp:wrapNone/>'
      '<wp:docPr id="3" name="Graphic 3"/>'
      '<a:graphic xmlns:a="$_a"><a:graphicData uri="$_pic">'
      '<pic:pic xmlns:pic="$_pic"><pic:blipFill>'
      '<asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" '
      'xmlns:r="$_r" r:embed="$rid"/>'
      '</pic:blipFill></pic:pic></a:graphicData></a:graphic>'
      '</wp:anchor></w:drawing></w:r>';

  // Het tekstkader met het classificatielabel, in beide uitvoeringen
  // (Choice + Fallback) zoals Word het schrijft — telt niet als voettekst.
  const classificationBox =
      '<w:r><mc:AlternateContent xmlns:mc="$_mc"><mc:Choice Requires="wps">'
      '<w:drawing><wp:anchor xmlns:wp="$_wp"><wp:extent cx="1009015" cy="361315"/>'
      '<wp:docPr id="9" name="Tekstvak 1"/>'
      '<a:graphic xmlns:a="$_a"><a:graphicData uri="x"><wps:wsp xmlns:wps="x">'
      '<wps:txbx><w:txbxContent><w:p><w:r><w:t>Intern gebruik</w:t></w:r></w:p>'
      '</w:txbxContent></wps:txbx></wps:wsp></a:graphicData></a:graphic>'
      '</wp:anchor></w:drawing></mc:Choice>'
      '<mc:Fallback><w:pict><v:shape xmlns:v="urn:schemas-microsoft-com:vml">'
      '<v:textbox><w:txbxContent><w:p><w:r><w:t>Intern gebruik</w:t></w:r>'
      '</w:p></w:txbxContent></v:textbox></v:shape></w:pict></mc:Fallback>'
      '</mc:AlternateContent></w:r>';

  String hdrFtr(String tag, String inner) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:$tag xmlns:w="$_w" xmlns:r="$_r">$inner</w:$tag>';

  // Titelblad-koptekst: het woordmerk, inline.
  final sectRefs = StringBuffer();
  if (titlePage && firstHeaderLogo != null) {
    final rid = addMedia('header2.xml', firstHeaderLogo);
    parts['word/header2.xml'] = _utf8(
      hdrFtr('hdr', inlinePicture(rid, 2196000, 675533)),
    );
    sectRefs.write(
      '<w:headerReference w:type="first" r:id="${addDocRel('header', 'header2.xml')}"/>',
    );
  }
  // Standaardkoptekst: tekst en/of een inline beeld.
  final headerInner = StringBuffer();
  if (headerText != null) {
    headerInner.write('<w:p><w:r><w:t>$headerText</w:t></w:r></w:p>');
  }
  if (defaultHeaderInlineLogo != null) {
    final rid = addMedia('header1.xml', defaultHeaderInlineLogo);
    headerInner.write(inlinePicture(rid, 1200000, 400000, jc: defaultHeaderJc));
  }
  if (headerInner.isNotEmpty) {
    parts['word/header1.xml'] = _utf8(hdrFtr('hdr', headerInner.toString()));
    sectRefs.write(
      '<w:headerReference w:type="default" r:id="${addDocRel('header', 'header1.xml')}"/>',
    );
  }
  // Standaardvoettekst: tekstkader, beeldmerk, tekst, paginanummer.
  final footerInner = StringBuffer('<w:p>$classificationBox');
  if (defaultFooterLogo != null) {
    final at =
        defaultFooterAnchor ??
        const FixtureAnchor(
          xEmu: 6867871,
          yEmu: 10135235,
          cxEmu: 323850,
          cyEmu: 295275,
        );
    if (svgOnlyFooterLogo) {
      final rid = addMedia('footer2.xml', defaultFooterLogo, ext: 'svg');
      footerInner.write(svgOnlyPicture(rid, at));
    } else {
      final rid = addMedia('footer2.xml', defaultFooterLogo);
      footerInner.write(anchoredPicture(rid, at));
    }
  }
  if (footerText != null) {
    footerInner.write('<w:r><w:t>$footerText</w:t></w:r><w:r><w:tab/></w:r>');
  }
  if (footerPageField) {
    footerInner.write(
      '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
      '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
      '<w:r><w:t>2</w:t></w:r>'
      '<w:r><w:fldChar w:fldCharType="end"/></w:r>',
    );
  }
  footerInner.write('</w:p>');
  parts['word/footer2.xml'] = _utf8(hdrFtr('ftr', footerInner.toString()));
  sectRefs.write(
    '<w:footerReference w:type="default" r:id="${addDocRel('footer', 'footer2.xml')}"/>',
  );

  // --- Body: een kop, tekst, en eventueel het herhaalde beeld per bladzijde.
  final body = StringBuffer(
    '<w:p><w:pPr><w:pStyle w:val="Kop1"/></w:pPr>'
    '<w:r><w:t>Beleid</w:t></w:r></w:p>'
    '<w:p><w:r><w:t>Een alinea.</w:t></w:r></w:p>',
  );
  if (bodyRepeatedLogo != null && bodyRepeatCount > 0) {
    final rid = addMedia('document.xml', bodyRepeatedLogo);
    final at =
        bodyAnchor ??
        const FixtureAnchor(
          xEmu: 600000,
          yEmu: 400000,
          cxEmu: 900000,
          cyEmu: 300000,
        );
    for (var i = 0; i < bodyRepeatCount; i++) {
      if (i > 0) {
        body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
      body.write('<w:p>${anchoredPicture(rid, at)}</w:p>');
      body.write('<w:p><w:r><w:t>Bladzijde ${i + 1}</w:t></w:r></w:p>');
    }
  }
  body.write(
    '<w:sectPr>$sectRefs'
    '<w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1899" w:right="1418" w:bottom="1701" w:left="1701" '
    'w:header="709" w:footer="510" w:gutter="0"/>'
    '${titlePage ? '<w:titlePg/>' : ''}'
    '</w:sectPr>',
  );
  parts['word/document.xml'] = _utf8(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="$_w" xmlns:r="$_r" xmlns:mc="$_mc">'
    '<w:body>$body</w:body></w:document>',
  );

  // Relaties per deel: het document zelf krijgt zijn beelden bij de
  // hoofdrelaties, de kop- en voettekstdelen elk hun eigen bestand.
  final bodyMedia = drawingParts.remove('document.xml');
  parts['word/_rels/document.xml.rels'] = _utf8(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="$_pkg">$docRels${bodyMedia ?? ''}</Relationships>',
  );
  drawingParts.forEach((part, rels) {
    parts['word/_rels/$part.rels'] = _utf8(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="$_pkg">$rels</Relationships>',
    );
  });

  final archive = Archive();
  parts.forEach((name, content) {
    archive.addFile(ArchiveFile.bytes(name, Uint8List.fromList(content)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _graphic(String rid) =>
    '<a:graphic xmlns:a="$_a"><a:graphicData uri="$_pic">'
    '<pic:pic xmlns:pic="$_pic"><pic:nvPicPr><pic:cNvPr id="0" name=""/>'
    '<pic:cNvPicPr/></pic:nvPicPr><pic:blipFill>'
    '<a:blip xmlns:r="$_r" r:embed="$rid"><a:extLst><a:ext uri="{x}">'
    '<asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" '
    'r:embed="rIdSvg"/></a:ext></a:extLst></a:blip>'
    '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1" cy="1"/></a:xfrm>'
    '</pic:spPr></pic:pic></a:graphicData></a:graphic>';

List<int> _utf8(String s) => utf8.encode(s);
