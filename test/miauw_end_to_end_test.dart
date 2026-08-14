import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/seal_record.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/audit_dossier.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/finding_numbering.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Full MIAUW closeout verify (AGENTIC_BUILD_PLAN P4-V): the whole pentest flow
/// end-to-end at the model/service layer — author from the report template,
/// number the findings, seal, verify integrity, round-trip through Markdown, and
/// export the encrypted audit dossier — so the module hangs together, not just
/// each package in isolation.
void main() {
  // Waarom dit geval meer tijd krijgt dan de standaard dertig seconden: het
  // doet echt werk van begin tot eind — de sjabloon parseren, verzegelen met
  // SHA-512, en het dossier als versleutelde zip bouwen. Lokaal is dat een
  // paar seconden, maar op de Windows-CI, waar de hele suite tegelijk om vier
  // kernen vecht, liep het geval daar met enige regelmaat op af. Dertig
  // seconden is dan geen uitspraak over deze code maar een gok op de snelheid
  // van de machine. Alleen op Windows ruimer, zodat een échte vastloper
  // lokaal en op de andere legs nog steeds snel opvalt — dezelfde afweging als
  // in native_git_mirror_test (#933).
  test('author → renumber → seal → verify → export dossier', () async {
    final md = MarkdownService();

    // 1 · Author a report from the MIAUW template document, the same way
    // deck creation does: parse the bundled markdown, title on the first slide.
    expect(deckTemplateById('miauwReport'), isNotNull);
    final templateSlides = md
        .parseDeck(
          File('assets/templates/miauwReport.nl.md').readAsStringSync(),
        )!
        .slides;
    templateSlides[0] = templateSlides[0].copyWith(title: 'Acme Web Pentest');
    var deck = Deck(
      title: 'Acme Web Pentest',
      author: 'Jip Tester',
      organization: 'Acme BV',
      version: '1.0',
      date: '2026-07-12',
      slides: templateSlides,
    );
    expect(
      deck.slides.map((s) => s.type),
      containsAll(const [
        SlideType.finding,
        SlideType.scopeMatrix,
        SlideType.findingsSummary,
        SlideType.checklist,
        SlideType.signOff,
      ]),
    );

    // 2 · Number the findings (deck order → F-01…).
    deck = renumberFindings(deck);
    expect(deckFindingList(deck), isNotEmpty);

    // 3 · Seal the finalised report.
    final integrity = DocumentIntegrity(md);
    // De hash ontstaat bij het opslaan: hij gaat over de bytes van de `.md`,
    // en die bestaan pas als het bestand geschreven is.
    final afgerond = integrity.seal(deck, at: DateTime.utc(2026, 7, 12, 10));
    final sealed = DocumentIntegrity.recordWrittenBytes(
      afgerond,
      md.generateDeck(afgerond),
    );
    expect(sealed.finalized, isTrue);
    expect(sealed.sealHash, isNotEmpty);
    expect(sealed.sealAlgo, DocumentIntegrity.algorithm);

    // 4 · Verify integrity, including after a Markdown round-trip.
    expect(integrity.verify(sealed), IntegrityStatus.intact);
    final reparsed = SealRecord.of(
      sealed,
    ).applyTo(md.parseDeck(md.generateDeck(sealed))!);
    expect(integrity.verify(reparsed), IntegrityStatus.intact);
    expect(reparsed.slides.any((s) => s.type == SlideType.finding), isTrue);

    // 5 · Een wijziging ná het verzegelen moet zichtbaar zijn. Die wijziging
    // vindt buiten OciDeck plaats — in de app is een verzegeld deck
    // alleen-lezen — dus de toets loopt over het bestand, niet over het
    // deck-object in het geheugen.
    final geknoeid = SealRecord.of(sealed).applyTo(
      md.parseDeck(md.generateDeck(sealed).replaceFirst('# ', '# Sneaky '))!,
    );
    expect(integrity.verify(geknoeid), IntegrityStatus.changed);

    // 6 · Export the encrypted audit dossier; the seal facts travel inside it.
    final file = FileService(md, ImageService(), () => const ThemeProfile());
    final bytes = await file.buildDossierBytes(
      sealed,
      dossierIndex: buildAuditDossier(sealed),
      password: 'wachtwoord123!',
    );
    final archive = ZipDecoder().decodeBytes(bytes, password: 'wachtwoord123!');
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, contains('AUDIT_DOSSIER.md'));
    expect(
      names.any((n) => n.endsWith('.md') && n != 'AUDIT_DOSSIER.md'),
      isTrue,
    );
    final index = utf8.decode(
      archive.files.firstWhere((f) => f.name == 'AUDIT_DOSSIER.md').content
          as List<int>,
    );
    expect(index, contains(sealed.sealHash));
    expect(index, contains('Gefinaliseerd:** ja'));
  }, timeout: Platform.isWindows ? const Timeout(Duration(minutes: 3)) : null);
}
