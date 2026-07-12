import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';

/// The audit dossier (PENTEST_MIAUW §10.11) is the ordinary `.ocideck` package
/// plus an `AUDIT_DOSSIER.md` index and an optional `report.pdf`, sealed into
/// the same AES-256 zip.
void main() {
  late FileService file;

  setUp(() {
    file = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
  });

  Deck deck() => Deck(
    title: 'Acme Pentest',
    slides: [
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Intro', bullets: const ['een']),
    ],
  );

  test(
    'members carry the index, the report markdown and an optional pdf',
    () async {
      final members = await file.buildDossierMembers(
        deck(),
        dossierIndex: '# Index\ninhoud',
        reportPdf: const [37, 80, 68, 70], // %PDF
      );
      expect(members.containsKey('AUDIT_DOSSIER.md'), isTrue);
      expect(utf8.decode(members['AUDIT_DOSSIER.md']!), contains('# Index'));
      // The report source travels as the package's own `.md`.
      expect(
        members.keys.any((k) => k.endsWith('.md') && k != 'AUDIT_DOSSIER.md'),
        isTrue,
      );
      expect(members['report.pdf'], const [37, 80, 68, 70]);
    },
  );

  test('omits the report member when no pdf is supplied', () async {
    final members = await file.buildDossierMembers(deck(), dossierIndex: 'x');
    expect(members.containsKey('report.pdf'), isFalse);
    expect(members.containsKey('AUDIT_DOSSIER.md'), isTrue);
  });

  test('an unencrypted dossier zip decodes and contains the index', () async {
    final bytes = await file.buildDossierBytes(
      deck(),
      dossierIndex: '# Auditindex',
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final idx = archive.files.firstWhere((f) => f.name == 'AUDIT_DOSSIER.md');
    expect(utf8.decode(idx.content as List<int>), contains('# Auditindex'));
  });

  test('a password AES-encrypts the dossier (round-trips with it)', () async {
    final bytes = await file.buildDossierBytes(
      deck(),
      dossierIndex: '# Geheim',
      password: 'wachtwoord123!',
    );
    final decoded = ZipDecoder().decodeBytes(bytes, password: 'wachtwoord123!');
    final idx = decoded.files.firstWhere((f) => f.name == 'AUDIT_DOSSIER.md');
    expect(utf8.decode(idx.content as List<int>), contains('# Geheim'));
  });
}
