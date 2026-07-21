import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/models/seal_record.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/utils/content_hash.dart';

Deck _deck({String title = 'Rapport', List<Slide>? slides}) => Deck(
  title: title,
  slides:
      slides ??
      [
        Slide.create(SlideType.title).copyWith(title: title),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Bevindingen', bullets: const ['Eén', 'Twee']),
      ],
);

/// Wat de opslagroute doet, zonder schijf: de bytes serialiseren en er dezelfde
/// vastleggingsregel op loslaten die `_writeProject` gebruikt.
Deck _writeAndRecord(MarkdownService md, Deck deck) =>
    DocumentIntegrity.recordWrittenBytes(deck, md.generateDeck(deck));

void main() {
  final md = MarkdownService();
  final integrity = DocumentIntegrity(md);

  group('DocumentIntegrity', () {
    test('an unsealed deck reports notSealed', () {
      expect(integrity.verify(_deck()), IntegrityStatus.notSealed);
    });

    test('seal sets the lock, the algorithm, the form and the moment', () {
      final sealed = integrity.seal(_deck());
      expect(sealed.finalized, isTrue);
      expect(sealed.sealAlgo, DocumentIntegrity.algorithm);
      expect(sealed.sealAlgo, 'sha-512');
      expect(sealed.sealForm, SealForm.fileBytes);
      expect(sealed.sealAt, isNotEmpty);
      expect(DateTime.tryParse(sealed.sealAt), isNotNull);
    });

    test('verzegeld maar nog niet opgeslagen is niet te controleren', () {
      // De hash gaat over bestandsbytes; vóór de eerste opslag bestaan die
      // niet. "Intact" melden zou een controle voorspiegelen die niemand heeft
      // uitgevoerd.
      final sealed = integrity.seal(_deck());
      expect(sealed.sealHash, isEmpty);
      expect(integrity.verify(sealed), IntegrityStatus.notVerifiable);
    });

    test('de eerste opslag legt de hash vast en die verifieert', () {
      final saved = _writeAndRecord(md, integrity.seal(_deck()));
      expect(saved.sealHash.length, 128); // SHA-512 in hex
      expect(saved.sealHash, saved.fileHash);
      expect(integrity.verify(saved), IntegrityStatus.intact);
    });

    test('het zegel overleeft opslaan-en-heropenen', () {
      final saved = _writeAndRecord(md, integrity.seal(_deck()));
      // Heropenen: de parser rekent de bytehash opnieuw uit, de sidecar levert
      // het zegel terug.
      final markdown = md.generateDeck(saved);
      final record = SealRecord.of(saved);
      final reopened = record.applyTo(md.parseDeck(markdown)!);
      expect(reopened.finalized, isTrue);
      expect(reopened.sealHash, saved.sealHash);
      expect(integrity.verify(reopened), IntegrityStatus.intact);
    });

    test('één gewijzigde byte in de .md breekt het zegel', () {
      final saved = _writeAndRecord(md, integrity.seal(_deck()));
      final tampered = md
          .generateDeck(saved)
          .replaceFirst('Bevindingen', 'Gewijzigd');
      final reopened = SealRecord.of(saved).applyTo(md.parseDeck(tampered)!);
      expect(integrity.verify(reopened), IntegrityStatus.changed);
    });

    test('ook een wijziging die niets aan de inhoud verandert breekt het', () {
      // De strengheid is de bedoeling: het zegel gaat over het bestand, niet
      // over een interpretatie ervan. Regeleindes omzetten maakt er een ander
      // bestand van, en het zegel hoort dat te zeggen in plaats van het weg te
      // normaliseren — elke normalisatiestap is een stap die de ontvanger moet
      // naspelen.
      final saved = _writeAndRecord(md, integrity.seal(_deck()));
      final crlf = md.generateDeck(saved).replaceAll('\n', '\r\n');
      final reopened = SealRecord.of(saved).applyTo(md.parseDeck(crlf)!);
      expect(integrity.verify(reopened), IntegrityStatus.changed);
    });

    test('een tweede opslag rekent de zegelhash niet opnieuw uit', () {
      // Zou hij dat wel doen, dan keurde elke wijziging zichzelf goed.
      final saved = _writeAndRecord(md, integrity.seal(_deck()));
      final edited = saved.copyWith(
        slides: [
          saved.slides.first,
          saved.slides[1].copyWith(bullets: const ['Eén', 'Drie']),
        ],
      );
      final resaved = _writeAndRecord(md, edited);
      expect(resaved.sealHash, saved.sealHash);
      expect(integrity.verify(resaved), IntegrityStatus.changed);
    });

    test('de handtekening reist mee met het zegel', () {
      const signature = DocumentSignature(
        name: 'Jan Jansen',
        role: 'Onderzoeker',
        statement: 'Naar waarheid opgesteld.',
        typedSignature: 'J. Jansen',
      );
      final sealed = integrity.seal(_deck(), signature: signature);
      expect(sealed.signature?.name, 'Jan Jansen');
      expect(SealRecord.of(sealed).signature?.name, 'Jan Jansen');
    });

    test('deckIntegrityStatus helper mirrors verify()', () {
      final saved = _writeAndRecord(md, integrity.seal(_deck()));
      expect(deckIntegrityStatus(saved), IntegrityStatus.intact);
      expect(deckIntegrityStatus(_deck()), IntegrityStatus.notSealed);
    });
  });

  group('een zegel van vóór 0.1.0', () {
    // De oude vorm hasht over de uitvoer van de eigen serialisator. Hij blijft
    // bestaan omdat een RFC 3161-token precies díé hash tijdstempelt: hem
    // omrekenen naar een bytehash zou een echte notarisatie ongeldig maken.
    Deck legacySealed({DocumentSignature? signature}) {
      final base = _deck().copyWith(
        signature: signature,
        clearSignature: signature == null,
      );
      return base.copyWith(
        finalized: true,
        sealAlgo: 'sha-512',
        sealForm: SealForm.canonical,
        sealAt: '2026-07-10T12:00:00.000Z',
        sealHash: integrity.computeCanonicalHash(base),
      );
    }

    test('verifieert nog steeds, zonder bestandsbytes', () {
      final deck = legacySealed();
      expect(deck.fileHash, isEmpty);
      expect(integrity.verify(deck), IntegrityStatus.intact);
    });

    test('een wijziging aan de inhoud wordt nog steeds gezien', () {
      final deck = legacySealed();
      final tampered = deck.copyWith(
        slides: [
          deck.slides.first,
          deck.slides[1].copyWith(bullets: const ['Eén', 'Drie']),
        ],
      );
      expect(integrity.verify(tampered), IntegrityStatus.changed);
    });

    test('de handtekening viel eronder, en valt er nog steeds onder', () {
      // De generator schrijft `ocideck_sig_*` niet meer weg, maar de oude
      // canonicalisatie moet ze wél meenemen — anders zou elk bestaand
      // verzegeld deck zich na de verhuizing als gemanipuleerd melden.
      const sig = DocumentSignature(name: 'Jan Jansen', role: 'Onderzoeker');
      final deck = legacySealed(signature: sig);
      expect(integrity.verify(deck), IntegrityStatus.intact);
      final tampered = deck.copyWith(
        signature: sig.copyWith(name: 'Iemand anders'),
      );
      expect(integrity.verify(tampered), IntegrityStatus.changed);
    });
  });

  group('de testvector uit docs/FILE_FORMAT.md §6.6', () {
    // Deze test bestaat om de documentatie eerlijk te houden. Staat hier iets
    // anders dan in de gids, dan klopt de gids niet meer — en een
    // controlerecept dat een ontvanger niet kan naspelen is erger dan geen
    // recept.
    const markdown =
        '---\n'
        'marp: true\n'
        'ocideck_format: 1\n'
        'theme: ocideck\n'
        'paginate: true\n'
        'title: Rapport\n'
        '---\n'
        '\n'
        '<!-- _class: title -->\n'
        '\n'
        '# Rapport\n'
        '\n';
    const digest =
        '76f87f10084f69911d3742e2e64eb9b9f2ac99d90686e1f24e3c6c3d14e34ed7'
        'd637fefa0252f49ece0e3fb9bbccd0803877c9d050ab87a616ae4af9d5c8936f';

    test('OciDeck schrijft precies deze bytes', () {
      final generated = md.generateDeck(
        Deck(
          title: 'Rapport',
          slides: [Slide.create(SlideType.title).copyWith(title: 'Rapport')],
        ),
      );
      expect(generated, markdown);
    });

    test('en de SHA-512 erover is de gedocumenteerde waarde', () {
      expect(sha512HexOfText(markdown), digest);
      expect(DocumentIntegrity.hashMarkdown(markdown), digest);
    });
  });
}
