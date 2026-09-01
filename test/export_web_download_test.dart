// De webtak van de exportpaden (#1902): wat er als download vertrekt, en wat de
// app erover meldt.
//
// Deze tak lag buiten bereik van de suite — `kIsWeb` is op de VM altijd false —
// en dat is precies waarom hij drie jaar lang kon melden dat een export gelukt
// was zonder dat iemand kon nagaan of er iets vertrok. De twee haken uit
// download_delivery.dart maken hem meetbaar.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/download_delivery.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:path/path.dart' as p;

typedef _Call = ({String name, Uint8List bytes, String mime});

Uint8List _png() {
  final image = img.Image(width: 320, height: 180);
  img.fill(image, color: img.ColorRgb8(30, 40, 60));
  return Uint8List.fromList(img.encodePng(image));
}

Future<String> _diskLoader(String asset) => File(asset).readAsString();

const _manifest = RedactionManifest(
  derivedFrom: 'seal-abc',
  entries: [
    RedactionEntry(
      id: 'a3f1',
      commitment: 'deadbeef',
      rule: 'nl.bsn',
      slideIndex: 0,
      field: 'body',
      salt: 'peper',
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ExportService service;
  final calls = <_Call>[];
  var accept = true;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ocideck_web_export');
    service = ExportService();
    calls.clear();
    accept = true;
    debugDeliversByDownload = true;
    debugDownloadSink = (name, bytes, mime) {
      calls.add((name: name, bytes: bytes, mime: mime));
      return accept;
    };
  });

  tearDown(() async {
    debugDeliversByDownload = null;
    debugDownloadSink = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  String deckPath() => p.join(tmp.path, 'deck.md');

  test('een geredigeerde export op web vertrekt als één download', () async {
    final r = await service.export(deckPath(), ExportFormat.pdf, [
      _png(),
    ], redactionManifest: _manifest);

    expect(r.success, isTrue, reason: r.error);
    // Eén download. Drie losse (rapport, commitments, sleutels) waren er twee
    // te veel: de browser houdt de tweede tegen en de auteur hield een
    // geredigeerd rapport over zonder iets om de redacties mee na te trekken.
    expect(calls, hasLength(1));
    expect(calls.single.name, endsWith('.pdf.zip'));
    expect(r.outputPath, calls.single.name);

    final zip = ZipDecoder().decodeBytes(calls.single.bytes);
    final names = zip.files.map((f) => f.name).toList();
    expect(names, hasLength(3));
    expect(names.where((n) => n.endsWith('.pdf')), hasLength(1));
    expect(
      names.where((n) => n.endsWith(kRedactionManifestSuffix)),
      hasLength(1),
    );
    expect(names.where((n) => n.endsWith(kRedactionKeysSuffix)), hasLength(1));

    // De commitments reizen zonder salt mee; de sleutels dragen hem wel. Dat
    // onderscheid moet de zip overleven.
    String memberFor(String suffix) => utf8.decode(
      zip.files.firstWhere((f) => f.name.endsWith(suffix)).content as List<int>,
    );
    expect(memberFor(kRedactionManifestSuffix), isNot(contains('peper')));
    expect(memberFor(kRedactionKeysSuffix), contains('peper'));

    // En er is niets naar schijf geschreven: op web bestaat die map niet.
    expect(tmp.listSync(), isEmpty);
  });

  test('een export zonder manifest blijft één los bestand', () async {
    final r = await service.export(deckPath(), ExportFormat.pdf, [_png()]);

    expect(r.success, isTrue, reason: r.error);
    expect(calls, hasLength(1));
    expect(calls.single.name, endsWith('.pdf'));
    expect(calls.single.name, isNot(endsWith('.zip')));
  });

  test('een geweigerde download meldt geen geslaagde export', () async {
    accept = false;
    final r = await service.export(deckPath(), ExportFormat.pdf, [
      _png(),
    ], redactionManifest: _manifest);

    expect(r.success, isFalse);
    expect(r.failure, ExportFailure.downloadNotStarted);
    expect(r.outputPath, isNull);
  });

  test('de documentexport levert op web één download op', () async {
    final bundle = await buildDocumentExportBundle(
      '# Rapport\n\nEen alinea.\n',
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: 'Rapport',
    );

    final written = await writeDocumentExport(
      bundle,
      DocumentExportFormat.md,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      webFileName: 'rapport.md',
    );

    expect(written, 'rapport.md');
    expect(calls, hasLength(1));
    expect(utf8.decode(calls.single.bytes), contains('Rapport'));

    // En een browser die hem niet aanneemt, levert geen bestandsnaam op.
    accept = false;
    expect(
      await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        enforcementPolicy: const ClassificationEnforcementPolicy(),
        webFileName: 'rapport.md',
      ),
      isNull,
    );
  });

  test('een geweigerd stijlprofiel meldt niet dat het is opgeslagen', () async {
    final service = FileService(
      MarkdownService(),
      ImageService(),
      ThemeProfile.new,
    );
    const profile = ThemeProfile(name: 'Huisstijl');

    final ok = await service.exportStyleProfile(profile);
    expect(ok.saved, isTrue);
    expect(ok.downloadRefused, isFalse);
    expect(calls, hasLength(1));
    expect(
      calls.single.name,
      endsWith('.${FileService.styleProfileExtension}'),
    );

    // Afbreken is stil, een weigering niet: de schil moet het verschil zien.
    accept = false;
    final refused = await service.exportStyleProfile(profile);
    expect(refused.saved, isFalse);
    expect(refused.downloadRefused, isTrue);
  });
}
