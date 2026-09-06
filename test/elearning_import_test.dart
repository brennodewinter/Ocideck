import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/pipeline/format_detector.dart';
import 'package:ocideck/services/import/importers/elearning/elearning_importer.dart';
import 'package:ocideck/services/import/importers/elearning/ims_manifest_reader.dart';
import 'package:ocideck/services/import/importers/elearning/qti_reader.dart';
import 'package:ocideck/services/import/importers/elearning/aicc_reader.dart';
import 'package:ocideck/services/import/importers/elearning/olx_reader.dart';
import 'package:ocideck/services/import/importers/elearning/cmi5_reader.dart';
import 'package:ocideck/services/import/models/source_format.dart';

Archive _zipWith(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    archive.addFile(ArchiveFile(name, content.length, content.codeUnits));
  });
  return archive;
}

void main() {
  group('eLearning format detection', () {
    test('detects SCORM by imsmanifest.xml', () {
      final archive = _zipWith({
        'imsmanifest.xml':
            '<?xml version="1.0"?><manifest><title>Test Course</title></manifest>',
      });
      final result = validateFormatFromArchive(archive);
      expect(result.format, SourceFormat.scorm);
      expect(result.isValid, isTrue);
    });

    test('detects QTI by imsqti.xml', () {
      final archive = _zipWith({
        'imsqti.xml':
            '<?xml version="1.0"?><assessmentTest xmlns="http://www.imsglobal.org/xsd/imsqti_v3p0"></assessmentTest>',
      });
      final result = validateFormatFromArchive(archive);
      expect(result.format, SourceFormat.qti);
    });

    test('detects cmi5 by cmi5.xml', () {
      final archive = _zipWith({
        'cmi5.xml': '<?xml version="1.0"?><courseStructure></courseStructure>',
      });
      final result = validateFormatFromArchive(archive);
      expect(result.format, SourceFormat.xapiCmi5);
    });

    test('detects AICC by .crs file', () {
      final archive = _zipWith({
        'course.crs': '[Course]\ncourse_title=Test Course\n',
      });
      final result = validateFormatFromArchive(archive);
      expect(result.format, SourceFormat.aicc);
    });

    test('detects OLX by course.xml with OLX namespace', () {
      final archive = _zipWith({
        'course.xml':
            '<?xml version="1.0"?><course xmlns="http://open.edx.org/xblock/course"><display_name>My Course</display_name></course>',
      });
      final result = validateFormatFromArchive(archive);
      expect(result.format, SourceFormat.olx);
    });
  });

  group('ImsManifestReader', () {
    test('extracts title and items from imsmanifest.xml', () {
      final archive = _zipWith({
        'imsmanifest.xml': '''
<?xml version="1.0"?>
<manifest>
  <metadata>
    <schema>ADL SCORM</schema>
  </metadata>
  <organizations default="org1">
    <organization identifier="org1">
      <title>Netwerken Basiscursus</title>
      <item identifier="item1">
        <title>Introductie</title>
      </item>
      <item identifier="item2">
        <title>Transportlaag</title>
      </item>
    </organization>
  </organizations>
</manifest>
''',
      });
      final deck = ImsManifestReader().read(archive, basename: 'scorm.zip');
      expect(deck.title, 'Netwerken Basiscursus');
      expect(deck.slides, hasLength(2));
      expect(deck.slides[0].title, 'Introductie');
      expect(deck.slides[1].title, 'Transportlaag');
    });

    test('produces placeholder when imsmanifest.xml is missing', () {
      final archive = _zipWith({});
      final deck = ImsManifestReader().read(archive, basename: 'empty.zip');
      expect(deck.slides, hasLength(1));
      expect(deck.slides[0].title, 'Import-waarschuwing');
    });
  });

  group('QtiReader', () {
    test('extracts assessment items', () {
      final archive = _zipWith({
        'test.xml': '''
<?xml version="1.0"?>
<assessmentTest xmlns="http://www.imsglobal.org/xsd/imsqti_v3p0">
  <title>Netwerken Toets</title>
  <assessmentItem identifier="q1">
    <title>Vraag 1</title>
    <prompt>Wat is TCP?</prompt>
  </assessmentItem>
</assessmentTest>
''',
      });
      final deck = QtiReader().read(archive, basename: 'qti.zip');
      expect(deck.title, 'Netwerken Toets');
      expect(deck.slides, hasLength(1));
      expect(deck.slides[0].title, 'Vraag 1');
    });
  });

  group('AiccReader', () {
    test('extracts title from .crs and units from .au', () {
      final archive = _zipWith({
        'course.crs': '[Course]\ncourse_title=AICC Test Course\n',
        'course.au':
            'unit1,1,Introductie,file1.html,http://example.com\nunit2,2,Vervolg,file2.html,http://example.com\n',
      });
      final deck = AiccReader().read(archive, basename: 'aicc.zip');
      expect(deck.title, 'AICC Test Course');
      expect(deck.slides, hasLength(2));
      expect(deck.slides[0].title, 'Introductie');
      expect(deck.slides[1].title, 'Vervolg');
    });
  });

  group('OlxReader', () {
    test('extracts sequentials from course.xml', () {
      final archive = _zipWith({
        'course.xml': '''
<?xml version="1.0"?>
<course xmlns="http://open.edx.org/xblock/course">
  <display_name>edX Course</display_name>
  <sequential url_name="seq1"/>
  <sequential url_name="seq2"/>
</course>
''',
      });
      final deck = OlxReader().read(archive, basename: 'olx.zip');
      expect(deck.title, 'edX Course');
      expect(deck.slides, hasLength(2));
    });
  });

  group('Cmi5Reader', () {
    test('extracts AU elements from cmi5.xml', () {
      final archive = _zipWith({
        'cmi5.xml': '''
<?xml version="1.0"?>
<courseStructure>
  <au id="au1" title="Module 1" url="http://example.com/mod1"/>
  <au id="au2" title="Module 2" url="http://example.com/mod2"/>
</courseStructure>
''',
      });
      final deck = Cmi5Reader().read(archive, basename: 'cmi5.zip');
      expect(deck.slides, hasLength(2));
      expect(deck.slides[0].title, 'Module 1');
    });

    test('parses xAPI JSON activity', () {
      final archive = _zipWith({
        'activity.json':
            '{"verb":"completed","actor":{"name":"test"},"object":{"definition":{"name":{"en-US":"Test Activity"}}}}',
      });
      final deck = Cmi5Reader().read(archive, basename: 'xapi.json');
      expect(deck.title, 'Test Activity');
      expect(deck.slides, hasLength(1));
    });
  });

  group('ElearningImporter', () {
    test('displayName per format', () {
      expect(
        ElearningImporter(SourceFormat.scorm).displayName,
        'SCORM / IMS Manifest',
      );
      expect(ElearningImporter(SourceFormat.qti).displayName, 'QTI 2.x/3.x');
      expect(ElearningImporter(SourceFormat.aicc).displayName, 'AICC');
      expect(ElearningImporter(SourceFormat.olx).displayName, 'OLX (Open edX)');
    });
  });
}
