import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

/// Genoeg PNG-magic-bytes om de signature-check te halen; de inhoud erna doet
/// er voor het in- en uitpakken niet toe.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  1, 2, 3, 4, 5, 6, 7, 8,
]);

void main() {
  late Directory tmp;
  late FileService file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocideck_style_profile_test');
    file = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> envelopeOf(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

  Uint8List envelopeBytes(Map<String, Object?> envelope) =>
      Uint8List.fromList(utf8.encode(jsonEncode(envelope)));

  test(
    'een profiel zonder logo overleeft een export/import round-trip',
    () async {
      const profile = ThemeProfile(
        name: 'Mijn stijl',
        slideBackgroundColor: '#101010',
        textColor: '#FAFAFA',
        accentColor: '#FF8800',
        bulletMarker: BulletMarker.paw,
        footerText: 'Vertrouwelijk',
        footerShowPageNumbers: true,
        closingSlideEnabled: true,
        animationDurationMs: 1200,
        severityCriticalColor: '#AA0000',
      );

      final built = await file.buildStyleProfileBytes(profile);
      expect(built.logoOmitted, isFalse);

      final out = await file.importStyleProfileBytes(built.bytes);
      expect(out.failure, isNull);
      expect(out.profile!.toJson(), profile.toJson());
    },
  );

  test('het bestand draagt de marker en de formaatversie', () async {
    final built = await file.buildStyleProfileBytes(const ThemeProfile());
    final envelope = envelopeOf(built.bytes);
    expect(envelope['ocideck'], 'style-profile');
    expect(envelope['version'], 1);
    expect(envelope['profile'], isA<Map<String, Object?>>());
    expect(envelope.containsKey('logo'), isFalse);
  });

  test(
    'een eigen logo reist ingesloten mee en wordt bij import teruggezet',
    () async {
      final src = File(p.join(tmp.path, 'logo.png'))..writeAsBytesSync(_png);
      final profile = const ThemeProfile(
        name: 'Met logo',
      ).copyWith(logoPath: src.path);

      final built = await file.buildStyleProfileBytes(profile);
      expect(built.logoOmitted, isFalse);

      // Het lokale pad lekt niet mee; de bytes wél.
      final envelope = envelopeOf(built.bytes);
      expect((envelope['profile']! as Map)['logoPath'], isNull);
      expect((envelope['logo']! as Map)['mime'], 'image/png');

      final out = await file.importStyleProfileBytes(
        built.bytes,
        logoBaseDir: tmp,
      );
      expect(out.failure, isNull);
      expect(out.logoOmitted, isFalse);

      final landed = out.profile!.logoPath!;
      expect(p.dirname(landed), p.join(tmp.path, 'style_logos'));
      expect(File(landed).readAsBytesSync(), _png);
      // Een verse kopie, niet het bronbestand.
      expect(landed, isNot(src.path));
    },
  );

  test('een ingebouwd asset:-logo blijft een verwijzing', () async {
    const profile = ThemeProfile(
      name: 'Ingebouwd',
      logoPath: 'asset:assets/images/librekat-logo.png',
    );

    final built = await file.buildStyleProfileBytes(profile);
    final envelope = envelopeOf(built.bytes);
    expect(
      (envelope['profile']! as Map)['logoPath'],
      'asset:assets/images/librekat-logo.png',
    );
    expect(envelope.containsKey('logo'), isFalse);

    final out = await file.importStyleProfileBytes(built.bytes);
    expect(out.profile!.logoPath, 'asset:assets/images/librekat-logo.png');
  });

  test(
    'een verdwenen logobestand levert een profiel zonder logo plus een melding',
    () async {
      final profile = const ThemeProfile(
        name: 'Kapot logo',
      ).copyWith(logoPath: p.join(tmp.path, 'bestaat-niet.png'));

      final built = await file.buildStyleProfileBytes(profile);
      expect(built.logoOmitted, isTrue);

      final out = await file.importStyleProfileBytes(built.bytes);
      expect(out.failure, isNull);
      expect(out.profile!.logoPath, isNull);
    },
  );

  test(
    'een los logopad zonder ingesloten afbeelding wordt weggegooid',
    () async {
      // Een handgemaakt bestand dat naar de schijf van de afzender wijst.
      final bytes = envelopeBytes({
        'ocideck': 'style-profile',
        'version': 1,
        'profile': {
          'name': 'Vreemd',
          'logoPath': '/Users/iemand/geheim/logo.png',
        },
      });

      final out = await file.importStyleProfileBytes(bytes);
      expect(out.profile!.logoPath, isNull);
    },
  );

  test(
    'een logo-blok dat geen afbeelding is levert een profiel zonder logo',
    () async {
      final bytes = envelopeBytes({
        'ocideck': 'style-profile',
        'version': 1,
        'profile': {'name': 'Nep'},
        'logo': {
          'mime': 'image/png',
          'data': base64.encode([1, 2, 3, 4, 5, 6]),
        },
      });

      final out = await file.importStyleProfileBytes(bytes);
      expect(out.failure, isNull);
      expect(out.logoOmitted, isTrue);
      expect(out.profile!.logoPath, isNull);
    },
  );

  test('fromJson blijft de gehardende poort voor een vreemd bestand', () async {
    final bytes = envelopeBytes({
      'ocideck': 'style-profile',
      'version': 1,
      'profile': {
        'name': 'Kwaadaardig',
        'textColor': 'red}</style><style>body{display:none}',
        'fontFamily': 'ArialX; behavior:url(evil.htc)',
      },
    });

    final out = await file.importStyleProfileBytes(bytes);
    expect(out.profile!.textColor, '#222222');
    expect(out.profile!.fontFamily, 'Arial');
  });

  group('weigeringen', () {
    test('geen JSON', () async {
      final out = await file.importStyleProfileBytes(
        utf8.encode('geen json {{'),
      );
      expect(out.failure, StyleProfileImportFailure.invalid);
    });

    test('JSON zonder marker (bv. een willekeurig .json-bestand)', () async {
      final out = await file.importStyleProfileBytes(
        envelopeBytes({'name': 'Mijn stijl', 'textColor': '#FFFFFF'}),
      );
      expect(out.failure, StyleProfileImportFailure.invalid);
    });

    test('een nieuwere formaatversie', () async {
      final out = await file.importStyleProfileBytes(
        envelopeBytes({
          'ocideck': 'style-profile',
          'version': 2,
          'profile': {'name': 'Toekomst'},
        }),
      );
      expect(out.failure, StyleProfileImportFailure.unsupportedVersion);
    });

    test('een profiel dat geen object is', () async {
      final out = await file.importStyleProfileBytes(
        envelopeBytes({
          'ocideck': 'style-profile',
          'version': 1,
          'profile': 'nope',
        }),
      );
      expect(out.failure, StyleProfileImportFailure.invalid);
    });

    test('een leeg bestand', () async {
      final out = await file.importStyleProfileBytes(<int>[]);
      expect(out.failure, StyleProfileImportFailure.tooLarge);
    });

    test('een bestand boven de cap', () async {
      final out = await file.importStyleProfileBytes(
        Uint8List(FileService.maxStyleProfileBytes + 1),
      );
      expect(out.failure, StyleProfileImportFailure.tooLarge);
    });
  });
}
