import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/models/seal_record.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/seal_codec.dart';
import 'package:ocideck/services/trash_service.dart';
import 'package:path/path.dart' as p;

/// Het zegel en de handtekening gaan over het document in plaats van erin, en
/// stonden in de front matter — twee van hun waarden zelfs als base64. Ze horen
/// naast de markdown, in `<naam>.seal.json`. Daardoor kan de hash over de bytes
/// van de `.md` gaan, en die is met `sha512sum` na te rekenen.

const _handtekening = DocumentSignature(
  name: 'Jan Jansen',
  role: 'Onderzoeker',
  certification: 'OSCP',
  date: '2026-07-10',
  statement: 'Naar waarheid opgesteld.',
  typedSignature: 'J. Jansen',
);

Future<Directory> _tijdelijkeMap() async {
  final dir = await Directory.systemTemp.createTemp('ocideck_zegel_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

FileService _dienst() =>
    FileService(MarkdownService(), ImageService(), () => const ThemeProfile());

Deck _deck() => Deck(
  title: 'Pentest',
  slides: [
    Slide.create(SlideType.title).copyWith(title: 'Pentest'),
    Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Bevindingen', bullets: const ['Eén', 'Twee']),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('de codec', () {
    test('schrijft niets als er niets vast te leggen is', () {
      expect(SealCodec.encode(const SealRecord()), isNull);
    });

    test('rondgang: zegel én handtekening komen heel terug', () {
      const record = SealRecord(
        finalized: true,
        hash: 'abc',
        algo: 'sha-512',
        at: '2026-07-10T12:00:00.000Z',
        timestampToken: 'MIAFAKEtoken',
        signature: _handtekening,
      );
      final terug = SealCodec.decode(SealCodec.encode(record)!)!;
      expect(terug.finalized, isTrue);
      expect(terug.hash, 'abc');
      expect(terug.algo, 'sha-512');
      expect(terug.at, '2026-07-10T12:00:00.000Z');
      expect(terug.form, SealForm.fileBytes);
      expect(terug.timestampToken, 'MIAFAKEtoken');
      expect(terug.signature?.certification, 'OSCP');
    });

    test('de vorm van het zegel reist mee', () {
      const record = SealRecord(
        finalized: true,
        hash: 'abc',
        algo: 'sha-512',
        form: SealForm.canonical,
      );
      final json = SealCodec.encode(record)!;
      expect(json, contains('canonical-v1'));
      expect(SealCodec.decode(json)!.form, SealForm.canonical);
    });

    test('een nieuwere versie wordt niet half gelezen', () {
      final json = SealCodec.encode(
        const SealRecord(finalized: true, hash: 'abc', algo: 'sha-512'),
      )!.replaceAll('"version":${SealCodec.version}', '"version":99');
      expect(SealCodec.decode(json), isNull);
    });

    test('kapotte JSON blokkeert het openen niet', () {
      expect(SealCodec.decode('{niet eens JSON'), isNull);
    });
  });

  group('naast de markdown', () {
    test('opslaan zet het zegel ernaast en niet erin', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      final dienst = _dienst();
      final verzegeld = DocumentIntegrity(
        MarkdownService(),
      ).seal(_deck(), signature: _handtekening);
      final opgeslagen = await dienst.saveDeck(verzegeld, pad);

      final markdown = await File(pad).readAsString();
      expect(markdown, isNot(contains('ocideck_finalized')));
      expect(markdown, isNot(contains('ocideck_seal_')));
      expect(markdown, isNot(contains('ocideck_sig_')));

      final sidecar = File(p.join(map.path, 'deck.seal.json'));
      expect(sidecar.existsSync(), isTrue);
      final data = jsonDecode(await sidecar.readAsString()) as Map;
      expect(data['finalized'], isTrue);
      expect(data['form'], 'file-bytes-v1');
      expect((data['signature'] as Map)['certification'], 'OSCP');
      expect(opgeslagen.sealHash, data['hash']);
    });

    test('de vastgelegde hash is die van het bestand zelf', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      final dienst = _dienst();
      final opgeslagen = await dienst.saveDeck(
        DocumentIntegrity(MarkdownService()).seal(_deck()),
        pad,
      );
      // Precies wat een ontvanger doet met `sha512sum deck.md`.
      final bytes = await File(pad).readAsBytes();
      expect(opgeslagen.sealHash, DocumentIntegrity.hashBytes(bytes));
    });

    test('heropenen levert een intact zegel op', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      final dienst = _dienst();
      await dienst.saveDeck(
        DocumentIntegrity(
          MarkdownService(),
        ).seal(_deck(), signature: _handtekening),
        pad,
      );
      final terug = (await dienst.openDeck(pad))!;
      expect(terug.finalized, isTrue);
      expect(terug.signature?.name, 'Jan Jansen');
      expect(deckIntegrityStatus(terug), IntegrityStatus.intact);
    });

    test('een gewijzigde .md meldt zich als gewijzigd', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      final dienst = _dienst();
      await dienst.saveDeck(
        DocumentIntegrity(MarkdownService()).seal(_deck()),
        pad,
      );
      final bestand = File(pad);
      await bestand.writeAsString(
        (await bestand.readAsString()).replaceFirst('Bevindingen', 'Gewijzigd'),
      );
      final terug = (await dienst.openDeck(pad))!;
      expect(deckIntegrityStatus(terug), IntegrityStatus.changed);
    });

    test('een onverzegeld deck laat geen zegelbestand achter', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      await _dienst().saveDeck(_deck(), pad);
      expect(File(p.join(map.path, 'deck.seal.json')).existsSync(), isFalse);
    });
  });

  group('het zegel reist mee waar de markdown alleen gaat', () {
    test('een pakket draagt het als eigen lid', () async {
      final verzegeld = DocumentIntegrity(
        MarkdownService(),
      ).seal(_deck(), signature: _handtekening);
      final leden = await _dienst().buildPackageMembers(
        // Zoals het deck na een opslag is: mét vastgelegde hash.
        DocumentIntegrity.recordWrittenBytes(
          verzegeld,
          MarkdownService().generateDeck(verzegeld),
        ),
      );
      expect(leden.keys, contains('Pentest.seal.json'));
      expect(utf8.decode(leden['Pentest.seal.json']!), contains('OSCP'));
      expect(
        utf8.decode(leden['Pentest.md']!),
        isNot(contains('ocideck_seal')),
      );
      expect(
        utf8.decode(leden['Pentest.md']!),
        isNot(contains('ocideck_sig_')),
      );
    });

    test('een deck zonder zegel draagt geen leeg lid mee', () async {
      final leden = await _dienst().buildPackageMembers(_deck());
      expect(leden.keys, isNot(contains('Pentest.seal.json')));
    });

    test('de prullenbak neemt het zegelbestand mee', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'los-deck.md');
      await File(pad).writeAsString('---\nmarp: true\n---\n\n# T\n');
      final zegel = File(p.join(map.path, 'los-deck.seal.json'))
        ..writeAsStringSync('{"version":1,"finalized":true}');
      expect(TrashService.trashTargetsFor(pad), contains(zegel.path));
    });
  });

  group('migratie van een deck van vóór 0.1.0', () {
    /// Een `.md` zoals OciDeck hem tot 0.1.0 schreef: het zegel- en het
    /// handtekeningblok in de front matter.
    String oudeMarkdown(String hash) =>
        '---\n'
        'marp: true\n'
        'theme: ocideck\n'
        'paginate: true\n'
        'title: Pentest\n'
        'ocideck_sig_name: Jan Jansen\n'
        'ocideck_sig_role: Onderzoeker\n'
        'ocideck_finalized: true\n'
        'ocideck_seal_hash: $hash\n'
        'ocideck_seal_algo: sha-512\n'
        'ocideck_seal_at: 2026-07-10T12:00:00.000Z\n'
        'ocideck_seal_tsr: MIAFAKEtoken\n'
        '---\n'
        '\n'
        '<!-- _class: title -->\n'
        '\n'
        '# Pentest\n';

    /// De hash die zo'n bestand destijds droeg: over de gecanonicaliseerde
    /// inhoud, niet over de bytes.
    String oudeHash(MarkdownService md) {
      final ontleed = md.parseDeck(oudeMarkdown('nog-niet'))!;
      return DocumentIntegrity(md).computeCanonicalHash(ontleed);
    }

    test('blijft leesbaar, met het zegel dat erin stond', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      final md = MarkdownService();
      await File(pad).writeAsString(oudeMarkdown(oudeHash(md)));

      final terug = (await _dienst().openDeck(pad))!;
      expect(terug.finalized, isTrue);
      expect(terug.sealForm, SealForm.canonical);
      expect(terug.sealTimestampToken, 'MIAFAKEtoken');
      expect(terug.signature?.name, 'Jan Jansen');
      expect(deckIntegrityStatus(terug), IntegrityStatus.intact);
    });

    test(
      'gaat bij opslaan naar de nieuwe vorm, zonder de hash te herrekenen',
      () async {
        final map = await _tijdelijkeMap();
        final pad = p.join(map.path, 'deck.md');
        final md = MarkdownService();
        final hash = oudeHash(md);
        await File(pad).writeAsString(oudeMarkdown(hash));

        final dienst = _dienst();
        final geopend = (await dienst.openDeck(pad))!;
        final opgeslagen = await dienst.saveDeck(geopend, pad);

        // De regels zijn uit het bestand verdwenen…
        final markdown = await File(pad).readAsString();
        expect(markdown, isNot(contains('ocideck_seal_')));
        expect(markdown, isNot(contains('ocideck_sig_')));
        expect(markdown, isNot(contains('ocideck_finalized')));
        // …en staan nu ernaast, mét de vorm waarin ze zijn ontstaan. De hash zelf
        // blijft ongemoeid: het RFC 3161-token tijdstempelt precies déze waarde,
        // en hem omrekenen zou die notarisatie ongeldig maken.
        final data =
            jsonDecode(
                  await File(p.join(map.path, 'deck.seal.json')).readAsString(),
                )
                as Map;
        expect(data['hash'], hash);
        expect(data['form'], 'canonical-v1');
        expect(data['timestamp_token'], 'MIAFAKEtoken');
        expect(opgeslagen.sealHash, hash);

        // En na de verhuizing verifieert het zegel nog steeds.
        final terug = (await dienst.openDeck(pad))!;
        expect(deckIntegrityStatus(terug), IntegrityStatus.intact);
      },
    );

    test('de sidecar wint van wat er nog in de front matter staat', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      final md = MarkdownService();
      await File(pad).writeAsString(oudeMarkdown(oudeHash(md)));
      await File(p.join(map.path, 'deck.seal.json')).writeAsString(
        SealCodec.encode(
          const SealRecord(
            finalized: true,
            hash: 'uit-de-sidecar',
            algo: 'sha-512',
            at: '2026-07-11T00:00:00.000Z',
          ),
        )!,
      );
      final terug = (await _dienst().openDeck(pad))!;
      expect(terug.sealHash, 'uit-de-sidecar');
      expect(terug.sealForm, SealForm.fileBytes);
      expect(terug.sealTimestampToken, isEmpty);
    });
  });
}
