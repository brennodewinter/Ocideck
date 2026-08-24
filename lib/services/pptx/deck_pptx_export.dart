// PPTX (Office Open XML, ECMA-376) export voor een deck.
//
// Bouwt een PPTX-ZIP uit gerasterde slide-afbeeldingen — één afbeelding per
// slide, niet een poging de opmaak na te bootsen. De ontvanger krijgt een
// presentatie die er exact zo uitziet als in de app.
//
// Headless: geen Flutter, geen IO — de aanroeler (export_service.dart) levert
// de afbeeldingen en schrijft de bytes weg. Hergebruikt de `archive`-package
// (al een directe dependency) voor de ZIP-verpakking. Geen nieuwe dependency.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../export_metadata.dart';

// 16:9 widescreen slide size in EMU (English Metric Units): 13.333" x 7.5".
const int _slideWidthEmu = 12192000;
const int _slideHeightEmu = 6858000;

Uint8List buildDeckExportPptx(
  List<Uint8List> images, {
  required ExportDocumentMetadata metadata,
  required String fallbackTitle,
  List<String>? notes,
}) {
  final archive = Archive();
  void addText(String name, String content) {
    final data = utf8.encode(content);
    archive.add(ArchiveFile(name, data.length, data));
  }

  final slideCount = images.length;
  // Which slides carry speaker notes. When none do, the whole notes machinery
  // (notesMaster + notesSlides) is omitted to keep the file minimal.
  final noteFor = <int, String>{
    for (var i = 0; i < slideCount; i++)
      if (notes != null && i < notes.length && notes[i].trim().isNotEmpty)
        i: notes[i].trim(),
  };
  final hasNotes = noteFor.isNotEmpty;

  addText('[Content_Types].xml', _contentTypes(slideCount, noteFor.keys));
  addText('_rels/.rels', _rootRels());
  addText(
    'docProps/core.xml',
    _coreProps(metadata, fallbackTitle: fallbackTitle),
  );
  addText('docProps/app.xml', _appProps(metadata));
  addText('ppt/presentation.xml', _presentationXml(slideCount, hasNotes));
  addText(
    'ppt/_rels/presentation.xml.rels',
    _presentationRels(slideCount, hasNotes),
  );
  addText('ppt/presProps.xml', _presProps());
  addText('ppt/theme/theme1.xml', _theme1());
  addText('ppt/slideMasters/slideMaster1.xml', _slideMaster());
  addText('ppt/slideMasters/_rels/slideMaster1.xml.rels', _slideMasterRels());
  addText('ppt/slideLayouts/slideLayout1.xml', _slideLayout());
  addText('ppt/slideLayouts/_rels/slideLayout1.xml.rels', _slideLayoutRels());

  if (hasNotes) {
    addText('ppt/notesMasters/notesMaster1.xml', _notesMaster());
    addText('ppt/notesMasters/_rels/notesMaster1.xml.rels', _notesMasterRels());
  }

  for (var i = 0; i < slideCount; i++) {
    final n = i + 1;
    final hasNote = noteFor.containsKey(i);
    addText('ppt/slides/slide$n.xml', _slideXml());
    addText('ppt/slides/_rels/slide$n.xml.rels', _slideRels(n, hasNote));
    if (hasNote) {
      addText('ppt/notesSlides/notesSlide$n.xml', _notesSlideXml(noteFor[i]!));
      addText(
        'ppt/notesSlides/_rels/notesSlide$n.xml.rels',
        _notesSlideRels(n),
      );
    }
    final png = images[i];
    archive.add(ArchiveFile('ppt/media/image$n.png', png.length, png));
  }

  return ZipEncoder().encodeBytes(archive);
}

/// XML-escape free text destined for an `<a:t>` run.
String _xmlEscape(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// A notesSlide whose body placeholder carries the speaker notes. Newlines in
/// [note] become separate paragraphs.
String _notesSlideXml(String note) {
  final paras = StringBuffer();
  for (final line in note.split('\n')) {
    paras.write('<a:p><a:r><a:t>${_xmlEscape(line)}</a:t></a:r></a:p>');
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:cSld><p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '<p:sp>'
      '<p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder"/>'
      '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
      '<p:spPr/>'
      '<p:txBody><a:bodyPr/><a:lstStyle/>$paras</p:txBody>'
      '</p:sp>'
      '</p:spTree></p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:notes>';
}

String _notesSlideRels(int n) {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
      'Target="../slides/slide$n.xml"/>'
      '<Relationship Id="rId2" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" '
      'Target="../notesMasters/notesMaster1.xml"/>'
      '</Relationships>';
}

String _notesMaster() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:cSld><p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '</p:spTree></p:cSld>'
      '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
      'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
      'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
      '</p:notesMaster>';
}

String _notesMasterRels() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" '
      'Target="../theme/theme1.xml"/>'
      '</Relationships>';
}

String _contentTypes(int count, Iterable<int> noteIndices) {
  final overrides = StringBuffer();
  for (var i = 1; i <= count; i++) {
    overrides.write(
      '<Override PartName="/ppt/slides/slide$i.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
    );
  }
  final notes = noteIndices.toList();
  if (notes.isNotEmpty) {
    overrides.write(
      '<Override PartName="/ppt/notesMasters/notesMaster1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"/>',
    );
    for (final i in notes) {
      overrides.write(
        '<Override PartName="/ppt/notesSlides/notesSlide${i + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>',
      );
    }
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
      '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
      '<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>'
      '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
      '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
      '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
      '$overrides'
      '</Types>';
}

String _rootRels() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';
}

String _coreProps(
  ExportDocumentMetadata metadata, {
  required String fallbackTitle,
}) {
  final now = DateTime.now().toUtc();
  String iso(DateTime t) => t.toIso8601String();
  final title = _xmlEscape(metadata.displayTitle(fallbackTitle));
  final subject = _xmlEscape(metadata.subject(fallbackTitle));
  final creator = _xmlEscape(metadata.documentAuthor);
  final keywords = _xmlEscape(metadata.exportKeywords());
  final description = metadata.htmlDescription;
  final descXml = description == null
      ? ''
      : '<dc:description>${_xmlEscape(description)}</dc:description>';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties '
      'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>$title</dc:title>'
      '<dc:subject>$subject</dc:subject>'
      '<dc:creator>$creator</dc:creator>'
      '$descXml'
      '<cp:keywords>$keywords</cp:keywords>'
      '<cp:lastModifiedBy>${_xmlEscape(metadata.producer)}</cp:lastModifiedBy>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">${iso(now)}</dcterms:created>'
      '<dcterms:modified xsi:type="dcterms:W3CDTF">${iso(now)}</dcterms:modified>'
      '</cp:coreProperties>';
}

String _appProps(ExportDocumentMetadata metadata) {
  final company = metadata.organization.trim();
  final companyXml = company.isEmpty
      ? ''
      : '<Company>${_xmlEscape(company)}</Company>';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
      '<Application>${_xmlEscape(metadata.producer)}</Application>'
      '$companyXml'
      '</Properties>';
}

String _presentationXml(int count, bool hasNotes) {
  final sldIds = StringBuffer();
  for (var i = 0; i < count; i++) {
    // Slide relationship ids start at rId2 (rId1 = master).
    sldIds.write('<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>');
  }
  // The notesMaster relationship is appended after the slides/presProps/theme
  // rels (see _presentationRels): rId(count+4).
  final notesMasterIdLst = hasNotes
      ? '<p:notesMasterIdLst><p:notesMasterId r:id="rId${count + 4}"/></p:notesMasterIdLst>'
      : '';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
      // Schema order: notesMasterIdLst must precede sldIdLst.
      '$notesMasterIdLst'
      '<p:sldIdLst>$sldIds</p:sldIdLst>'
      '<p:sldSz cx="$_slideWidthEmu" cy="$_slideHeightEmu" type="screen16x9"/>'
      '<p:notesSz cx="6858000" cy="9144000"/>'
      '</p:presentation>';
}

String _presentationRels(int count, bool hasNotes) {
  final rels = StringBuffer();
  rels.write(
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" '
    'Target="slideMasters/slideMaster1.xml"/>',
  );
  for (var i = 0; i < count; i++) {
    final n = i + 1;
    rels.write(
      '<Relationship Id="rId${i + 2}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
      'Target="slides/slide$n.xml"/>',
    );
  }
  final presPropsId = 'rId${count + 2}';
  final themeId = 'rId${count + 3}';
  rels.write(
    '<Relationship Id="$presPropsId" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" '
    'Target="presProps.xml"/>',
  );
  rels.write(
    '<Relationship Id="$themeId" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" '
    'Target="theme/theme1.xml"/>',
  );
  if (hasNotes) {
    // Must match the r:id used by notesMasterIdLst in _presentationXml.
    rels.write(
      '<Relationship Id="rId${count + 4}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" '
      'Target="notesMasters/notesMaster1.xml"/>',
    );
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '$rels'
      '</Relationships>';
}

String _presProps() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>';
}

String _slideMaster() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:cSld>'
      '<p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>'
      '${_emptySpTree()}'
      '</p:cSld>'
      '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
      'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
      'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
      '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
      '<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>'
      '</p:sldMaster>';
}

String _slideMasterRels() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" '
      'Target="../slideLayouts/slideLayout1.xml"/>'
      '<Relationship Id="rId2" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" '
      'Target="../theme/theme1.xml"/>'
      '</Relationships>';
}

String _slideLayout() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
      'type="blank" preserve="1">'
      '<p:cSld name="Leeg">${_emptySpTree()}</p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sldLayout>';
}

String _slideLayoutRels() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" '
      'Target="../slideMasters/slideMaster1.xml"/>'
      '</Relationships>';
}

String _slideXml() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:cSld><p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '<p:pic>'
      '<p:nvPicPr><p:cNvPr id="2" name="Slide"/>'
      '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
      '<p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
      '<p:spPr><a:xfrm><a:off x="0" y="0"/>'
      '<a:ext cx="$_slideWidthEmu" cy="$_slideHeightEmu"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
      '</p:pic>'
      '</p:spTree></p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sld>';
}

String _slideRels(int n, bool hasNote) {
  final notesRel = hasNote
      ? '<Relationship Id="rId3" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" '
            'Target="../notesSlides/notesSlide$n.xml"/>'
      : '';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" '
      'Target="../slideLayouts/slideLayout1.xml"/>'
      '<Relationship Id="rId2" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="../media/image$n.png"/>'
      '$notesRel'
      '</Relationships>';
}

String _emptySpTree() {
  return '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '</p:spTree>';
}

String _theme1() {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office">'
      '<a:themeElements>'
      '<a:clrScheme name="Office">'
      '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
      '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
      '<a:dk2><a:srgbClr val="44546A"/></a:dk2>'
      '<a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>'
      '<a:accent1><a:srgbClr val="4472C4"/></a:accent1>'
      '<a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
      '<a:accent3><a:srgbClr val="A5A5A5"/></a:accent3>'
      '<a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
      '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5>'
      '<a:accent6><a:srgbClr val="70AD47"/></a:accent6>'
      '<a:hlink><a:srgbClr val="0563C1"/></a:hlink>'
      '<a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
      '</a:clrScheme>'
      '<a:fontScheme name="Office">'
      '<a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
      '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
      '</a:fontScheme>'
      '<a:fmtScheme name="Office">'
      '<a:fillStyleLst>'
      '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      '</a:fillStyleLst>'
      '<a:lnStyleLst>'
      '<a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
      '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
      '<a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
      '</a:lnStyleLst>'
      '<a:effectStyleLst>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '</a:effectStyleLst>'
      '<a:bgFillStyleLst>'
      '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      '</a:bgFillStyleLst>'
      '</a:fmtScheme>'
      '</a:themeElements>'
      '</a:theme>';
}
