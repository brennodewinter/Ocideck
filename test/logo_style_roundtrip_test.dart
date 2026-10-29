// Logo's, pakketstijl en documentlettermaat die een ronde opslaan/openen
// moeten overleven. De dekking loopt ook door
// lib/services/file/file_service_carried_style.dart: een pakket draagt zijn
// stijl naast de markdown, niet erin.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asset_origin.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/docx/document_docx_export.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/odt/document_odt_export.dart';
import 'package:ocideck/services/style_logo_bytes.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:path/path.dart' as p;

Uint8List _png(int mark) => Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  mark,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    WebAssetStore.clear();
    tmp = Directory.systemTemp.createTempSync('ocideck_logo_style');
  });

  tearDown(() {
    WebAssetStore.clear();
    forgetStyleEditorMemoryPins();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  FileService service(ThemeProfile Function() theme) =>
      FileService(MarkdownService(), ImageService(), theme);

  Deck deckWith(ThemeProfile profile) => Deck(
    title: 'Huisstijl',
    themeProfile: profile,
    slides: [Slide.create(SlideType.title).copyWith(title: 'Opening')],
  );

  test('project bewaart donker logo, documentlogo en botsende namen', () async {
    final src = Directory(p.join(tmp.path, 'bron'))..createSync();
    final project = Directory(p.join(tmp.path, 'project'))..createSync();
    final logo = File(p.join(src.path, 'logo.png'))..writeAsBytesSync(_png(1));
    final darkDir = Directory(p.join(src.path, 'donker'))..createSync();
    final dark = File(p.join(darkDir.path, 'logo.png'))
      ..writeAsBytesSync(_png(2));
    final document = File(p.join(src.path, 'document.png'))
      ..writeAsBytesSync(_png(3));
    final stripDir = Directory(p.join(src.path, 'strook'))..createSync();
    final strip = File(p.join(stripDir.path, 'logo.png'))
      ..writeAsBytesSync(_png(4));

    final saved = await service(() => const ThemeProfile()).saveDeck(
      deckWith(
        ThemeProfile(
          logoPath: logo.path,
          logoDarkPath: dark.path,
          documentLogoPath: document.path,
          brandStripPath: strip.path,
          brandStripHeight: 0.1,
        ),
      ),
      p.join(project.path, 'deck.md'),
    );

    final paths = [
      saved.themeProfile.logoPath,
      saved.themeProfile.logoDarkPath,
      saved.themeProfile.documentLogoPath,
      saved.themeProfile.brandStripPath,
    ];
    expect(paths.toSet(), hasLength(4));
    expect(paths.every((path) => path!.startsWith('logos/')), isTrue);
    expect(
      File(
        p.join(project.path, saved.themeProfile.logoPath!),
      ).readAsBytesSync(),
      _png(1),
    );
    expect(
      File(
        p.join(project.path, saved.themeProfile.logoDarkPath!),
      ).readAsBytesSync(),
      _png(2),
    );
    expect(
      File(
        p.join(project.path, saved.themeProfile.documentLogoPath!),
      ).readAsBytesSync(),
      _png(3),
    );
    expect(
      File(
        p.join(project.path, saved.themeProfile.brandStripPath!),
      ).readAsBytesSync(),
      _png(4),
    );

    src.deleteSync(recursive: true);
    final moved = p.join(tmp.path, 'verhuisd');
    project.renameSync(moved);
    final opened = await service(
      () => saved.themeProfile,
    ).openDeck(p.join(moved, 'deck.md'));
    expect(File(opened!.themeProfile.logoDarkPath!).readAsBytesSync(), _png(2));
    expect(
      File(opened.themeProfile.documentLogoPath!).readAsBytesSync(),
      _png(3),
    );
    expect(opened.themeProfile.logoDarkPath, isNot(contains(src.path)));
  });

  test(
    'pakket draagt de stijl mee zonder het lokale profiel te vervangen',
    () async {
      final document = File(p.join(tmp.path, 'document.png'))
        ..writeAsBytesSync(_png(9));
      final missing = p.join(tmp.path, 'weg', 'logo.png');
      const carried = ThemeProfile(name: 'Afzender', accentColor: '#ABCDEF');
      final deck = deckWith(
        carried.copyWith(documentLogoPath: document.path, logoPath: missing),
      );
      final members = await service(
        () => const ThemeProfile(),
      ).buildPackageMembers(deck);
      expect(members['logos/document.png'], _png(9));
      final sidecar = utf8.decode(members[carriedStyleFileName]!);
      expect(sidecar, isNot(contains(tmp.path)));
      expect(sidecar, contains('Afzender'));
      expect(sidecar, contains('#ABCDEF'));

      final out = Directory(p.join(tmp.path, 'uit'))..createSync();
      final bytes = await service(
        () => const ThemeProfile(),
      ).buildPackageBytes(deck);
      final md = await service(
        () => const ThemeProfile(),
      ).importPackageBytes(bytes, out.path);
      const local = ThemeProfile(name: 'Lokaal', accentColor: '#111111');
      final opened = await service(() => local).openDeck(md!);
      expect(opened!.themeProfile.name, 'Afzender');
      expect(opened.themeProfile.accentColor, '#ABCDEF');
      expect(opened.themeProfile.documentLogoPath, startsWith(out.path));
      expect(
        File(opened.themeProfile.documentLogoPath!).readAsBytesSync(),
        _png(9),
      );

      File(p.join(p.dirname(md), carriedStyleFileName)).deleteSync();
      final without = await service(() => local).openDeck(md);
      expect(without!.themeProfile.name, 'Lokaal');
      expect(without.themeProfile.accentColor, '#111111');
    },
  );

  test(
    'web opent de sidecar als geheugenpaden en laat een onveilig pad vallen',
    () {
      final logo = _png(3);
      final entries = [
        (
          name: carriedStyleFileName,
          bytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode(
                const ThemeProfile(
                  name: 'Web',
                  accentColor: '#445566',
                  logoPath: 'logos/logo.png',
                  documentLogoPath: '/etc/passwd',
                ).toJson(),
              ),
            ),
          ),
        ),
        (name: 'logos/logo.png', bytes: logo),
      ];
      final deck = applyCarriedStyleMembers(
        deckWith(const ThemeProfile(name: 'Lokaal')),
        entries,
      );
      expect(deck.themeProfile.name, 'Web');
      expect(deck.themeProfile.accentColor, '#445566');
      expect(WebAssetStore.isMemPath(deck.themeProfile.logoPath!), isTrue);
      expect(deck.themeProfile.documentLogoPath, isEmpty);
    },
  );

  test('Marp-CSS neemt letter en tabelvelden van het profiel over', () async {
    final saved = await service(() => const ThemeProfile()).saveDeck(
      deckWith(
        const ThemeProfile(
          fontFamily: 'Georgia',
          tableBorderStyle: TableBorderStyle.none,
          tableZebraStriped: true,
          tableZebraColor: '#EEEEEE',
          tableCellPaddingPx: 14,
          tableAccentHeaderBorder: true,
          accentColor: '#123456',
        ),
      ),
      p.join(tmp.path, 'deck.md'),
    );
    final css = File(
      p.join(tmp.path, 'themes', 'ocideck.css'),
    ).readAsStringSync();
    expect(css, contains('font-family: "Georgia", sans-serif'));
    expect(css, contains('border: none;'));
    expect(css, contains('background: #EEEEEE'));
    expect(css, contains('padding: 14px'));
    expect(css, contains('border-bottom: 2px solid #123456'));
    expect(saved.themeProfile.fontFamily, 'Georgia');

    final plainDir = Directory(p.join(tmp.path, 'standaard'))..createSync();
    await service(() => const ThemeProfile()).saveDeck(
      deckWith(const ThemeProfile()),
      p.join(plainDir.path, 'deck.md'),
    );
    final plain = File(
      p.join(plainDir.path, 'themes', 'ocideck.css'),
    ).readAsStringSync();
    expect(plain, contains('font-family: "Arial", sans-serif'));
    expect(plain, contains('#CBD5E1'));
  });

  test(
    'DOCX en ODT schrijven de documentlettermaat en laten koppen relatief',
    () async {
      Future<Archive> docx(double pt) async {
        final bundle = await buildDocumentExportBundle(
          '# Kop\n\nEen alinea.\n',
          projectPath: null,
          profile: PrivacyExportProfile.full,
          ownIdentity: OwnIdentity.empty,
          regions: defaultPrivacyRegions,
          disabledRules: const {},
          markdownService: MarkdownService(),
          theme: ThemeProfile(documentBodyFontSize: pt),
        );
        final bytes = await buildDocumentExportDocxForTesting(bundle);
        return ZipDecoder().decodeBytes(bytes);
      }

      Future<String> odt(double pt) async {
        final bundle = await buildDocumentExportBundle(
          '# Kop\n\nEen alinea.\n',
          projectPath: null,
          profile: PrivacyExportProfile.full,
          ownIdentity: OwnIdentity.empty,
          regions: defaultPrivacyRegions,
          disabledRules: const {},
          markdownService: MarkdownService(),
          theme: ThemeProfile(documentBodyFontSize: pt),
        );
        final bytes = await buildDocumentExportOdtForTesting(bundle);
        final archive = ZipDecoder().decodeBytes(bytes);
        final content = archive.findFile('content.xml');
        return utf8.decode(content!.content as List<int>);
      }

      final standard = utf8.decode(
        (await docx(11)).findFile('word/styles.xml')!.content as List<int>,
      );
      expect(standard, contains('<w:sz w:val="22"/>'));
      final larger = utf8.decode(
        (await docx(18)).findFile('word/styles.xml')!.content as List<int>,
      );
      expect(larger, contains('<w:sz w:val="36"/>'));
      expect(larger, contains('<w:sz w:val="32"/>'));

      expect(await odt(11), contains('fo:font-size="11pt"'));
      final scaled = await odt(18);
      expect(scaled, contains('fo:font-size="18pt"'));
      expect(scaled, contains('fo:font-size="170%"'));
    },
  );

  test('een stijllogo wijst een leeg of te groot bestand af', () {
    expect(styleLogoFromBytes(Uint8List(0)), isNull);
    expect(styleLogoFromBytes(_png(1)), isNotNull);
    expect(
      styleLogoFromBytes(Uint8List(FileService.maxStyleProfileLogoBytes + 1)),
      isNull,
    );
  });

  test('de sweep houdt donker logo, documentlogo en de open editor vast', () {
    final dark = WebAssetStore.put(_png(1), name: 'donker.png');
    final document = WebAssetStore.put(_png(2), name: 'document.png');
    final strip = WebAssetStore.put(_png(3), name: 'strook.png');
    final paths = deckMemoryAssetPaths(
      deckWith(
        ThemeProfile(
          logoDarkPath: dark,
          documentLogoPath: document,
          brandStripPath: strip,
        ),
      ),
    );
    expect(paths, containsAll([dark, document, strip]));

    final unsaved = WebAssetStore.put(_png(4), name: 'concept.png');
    rememberStyleEditorMemoryPins(ThemeProfile(logoPath: unsaved));
    final live = <String>{};
    addOpenStyleMemoryPaths(const [], live);
    expect(live, contains(unsaved));
  });
}
