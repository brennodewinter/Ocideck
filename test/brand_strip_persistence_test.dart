import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:path/path.dart' as p;

final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  1,
  2,
  3,
  4,
]);
final _stripPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  5,
  6,
  7,
  8,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FileService file;

  setUp(() {
    WebAssetStore.clear();
    tmp = Directory.systemTemp.createTempSync('ocideck_brand_strip_test');
    file = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
  });

  tearDown(() {
    WebAssetStore.clear();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'ThemeProfile bewaart merkstrookvelden en oude profielen blijven klassiek',
    () {
      const profile = ThemeProfile(
        brandStripPath: 'logos/merkstrook.png',
        brandStripHeight: 0.13,
        titleSubtitleInBrandStrip: true,
      );

      final restored = ThemeProfile.fromJson(profile.toJson());
      expect(restored.brandStripPath, 'logos/merkstrook.png');
      expect(restored.brandStripHeight, 0.13);
      expect(restored.titleSubtitleInBrandStrip, isTrue);

      final legacy = ThemeProfile.fromJson(const {'name': 'Oud'});
      expect(legacy.brandStripPath, isNull);
      expect(legacy.brandStripHeight, 0);
      expect(legacy.titleSubtitleInBrandStrip, isFalse);
    },
  );

  test('.ocideckstyle v2 sluit de merkstrook in en zet haar terug', () async {
    final strip = File(p.join(tmp.path, 'merkstrook.png'))
      ..writeAsBytesSync(_png);
    final profile = ThemeProfile(
      name: 'Met merkstrook',
      brandStripPath: strip.path,
      brandStripHeight: 0.13,
      titleSubtitleInBrandStrip: true,
    );

    final built = await file.buildStyleProfileBytes(profile);
    final envelope =
        jsonDecode(utf8.decode(built.bytes)) as Map<String, Object?>;
    expect(envelope['version'], 2);
    expect((envelope['profile']! as Map)['brandStripPath'], isNull);
    expect((envelope['brandStrip']! as Map)['mime'], 'image/png');

    final imported = await file.importStyleProfileBytes(
      built.bytes,
      logoBaseDir: tmp,
    );
    expect(imported.failure, isNull);
    expect(imported.profile!.brandStripHeight, 0.13);
    expect(imported.profile!.titleSubtitleInBrandStrip, isTrue);
    expect(File(imported.profile!.brandStripPath!).readAsBytesSync(), _png);
  });

  test('.ocideckstyle zonder merkstrook blijft het v1-formaat', () async {
    final built = await file.buildStyleProfileBytes(
      const ThemeProfile(name: 'Klassiek'),
    );
    final envelope =
        jsonDecode(utf8.decode(built.bytes)) as Map<String, Object?>;
    expect(envelope['version'], 1);
    expect(envelope.containsKey('brandStrip'), isFalse);

    final imported = await file.importStyleProfileBytes(built.bytes);
    expect(imported.failure, isNull);
    expect(imported.profile!.brandStripPath, isNull);
  });

  test(
    'project bewaart een mem:-merkstrook en positioneert hem in CSS',
    () async {
      final logo = WebAssetStore.put(_png, name: 'logo.png');
      final strip = WebAssetStore.put(_stripPng, name: 'merkstrook.png');
      final profile = ThemeProfile(
        logoPath: logo,
        brandStripPath: strip,
        brandStripHeight: 0.12,
        titleSubtitleInBrandStrip: true,
      );
      final deck = Deck(
        title: 'Huisstijl',
        themeProfile: profile,
        slides: [
          Slide.create(
            SlideType.title,
          ).copyWith(title: 'Opening', subtitle: 'Door het team'),
        ],
      );

      final saved = await file.saveDeck(deck, p.join(tmp.path, 'deck.md'));
      expect(saved.themeProfile.brandStripPath, 'logos/merkstrook.png');
      expect(
        File(p.join(tmp.path, 'logos', 'merkstrook.png')).readAsBytesSync(),
        _stripPng,
      );

      final css = File(
        p.join(tmp.path, 'themes', 'ocideck.css'),
      ).readAsStringSync();
      expect(css, contains('url("../logos/merkstrook.png")'));
      expect(css, contains('height: 86px'));
      expect(css, contains('section.title.logo-safe h2'));
      expect(css, contains('bottom: 26px'));
    },
  );

  test('pakket neemt mem:-merkstrook, profiel en merk-CSS mee', () async {
    final logo = WebAssetStore.put(_png, name: 'logo.png');
    final strip = WebAssetStore.put(_stripPng, name: 'merkstrook.png');
    final deck = Deck(
      title: 'Pakketstijl',
      themeProfile: ThemeProfile(
        logoPath: logo,
        brandStripPath: strip,
        brandStripHeight: 0.12,
        titleSubtitleInBrandStrip: true,
      ),
      slides: [Slide.create(SlideType.title).copyWith(title: 'Opening')],
    );

    final members = await file.buildPackageMembers(deck);
    expect(members['logos/merkstrook.png'], _stripPng);
    final css = utf8.decode(members['themes/ocideck.css']!);
    expect(css, contains('url("../logos/merkstrook.png")'));
    expect(css, contains('height: 86px'));
    expect(css, contains('section.title.logo-safe h2'));

    final markdown = utf8.decode(members['Pakketstijl.md']!);
    expect(markdown, contains('<!-- _class: title logo-safe -->'));
  });

  test('titeldia bewaart een extra H2 in de aanvullende Markdown', () {
    final markdown = MarkdownService().generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.title).copyWith(
            title: 'Workshop',
            subtitle: 'Door het team',
            customMarkdown: '16 mei 2025\n\n## Programma\n\nKennismaking',
          ),
        ],
      ),
    );

    final restored = MarkdownService().parseDeck(markdown)!.slides.single;
    expect(
      restored.customMarkdown,
      '16 mei 2025\n\n## Programma\n\nKennismaking',
    );
  });

  test('titeldichtheid telt aanvullende informatie mee', () {
    final slide = Slide.create(SlideType.title).copyWith(
      title: 'Kort',
      subtitle: 'Ook kort',
      customMarkdown: 'Aanvullende informatie ' * 8,
    );

    final issue = const SlideQualityAnalyzer()
        .analyzeSlides(
          slides: [slide],
          theme: const ThemeProfile(),
          font: 'Arial',
        )
        .issues
        .singleWhere(
          (issue) => issue.kind == SlideQualityIssueKind.titleDensityHigh,
        );
    expect(issue.severity, MarkdownValidationSeverity.warning);
    expect(
      issue.args['chars'],
      '${5 + 8 + ('Aanvullende informatie ' * 8).trim().length}',
    );
  });
}
