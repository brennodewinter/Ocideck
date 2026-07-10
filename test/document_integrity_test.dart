import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/markdown_service.dart';

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

void main() {
  final md = MarkdownService();
  final integrity = DocumentIntegrity(md);

  group('DocumentIntegrity', () {
    test('an unsealed deck reports notSealed', () {
      expect(integrity.verify(_deck()), IntegrityStatus.notSealed);
    });

    test('seal sets the finalise flag, hash, algorithm and timestamp', () {
      final sealed = integrity.seal(_deck());
      expect(sealed.finalized, isTrue);
      expect(sealed.sealAlgo, DocumentIntegrity.algorithm);
      expect(sealed.sealAlgo, 'sha-512');
      expect(sealed.sealHash, isNotEmpty);
      // A SHA-512 hex digest is 128 hex chars.
      expect(sealed.sealHash.length, 128);
      expect(sealed.sealAt, isNotEmpty);
      expect(DateTime.tryParse(sealed.sealAt), isNotNull);
    });

    test('a freshly sealed deck verifies as intact', () {
      final sealed = integrity.seal(_deck());
      expect(integrity.verify(sealed), IntegrityStatus.intact);
    });

    test('the seal survives a save/parse round-trip and stays intact', () {
      final sealed = integrity.seal(_deck());
      final reparsed = md.parseDeck(md.generateDeck(sealed))!;
      expect(reparsed.finalized, isTrue);
      expect(reparsed.sealHash, sealed.sealHash);
      expect(integrity.verify(reparsed), IntegrityStatus.intact);
    });

    test('editing the content after sealing is detected as changed', () {
      final sealed = integrity.seal(_deck());
      // Tamper: change a bullet on the second slide, keep the seal fields.
      final tamperedSlides = [
        sealed.slides.first,
        sealed.slides[1].copyWith(bullets: const ['Eén', 'Drie']),
      ];
      final tampered = sealed.copyWith(slides: tamperedSlides);
      expect(integrity.verify(tampered), IntegrityStatus.changed);
    });

    test('tampering detected across a save/parse round-trip', () {
      final sealed = integrity.seal(_deck());
      var markdown = md.generateDeck(sealed);
      // Edit the body text directly in the on-disk markdown.
      markdown = markdown.replaceFirst('Bevindingen', 'Gewijzigd');
      final reparsed = md.parseDeck(markdown)!;
      expect(reparsed.finalized, isTrue);
      expect(integrity.verify(reparsed), IntegrityStatus.changed);
    });

    test('the hash excludes the seal fields (not circular)', () {
      final deck = _deck();
      final hashBefore = integrity.computeHash(deck);
      final sealed = integrity.seal(deck);
      // Recomputing over the sealed deck (which now carries the seal fields)
      // yields the same hash: the seal metadata is stripped before hashing.
      expect(integrity.computeHash(sealed), hashBefore);
      expect(sealed.sealHash, hashBefore);
    });

    test('the signature is covered by the seal', () {
      const signature = DocumentSignature(
        name: 'Jan Jansen',
        role: 'Onderzoeker',
        statement: 'Naar waarheid opgesteld.',
        typedSignature: 'J. Jansen',
      );
      final sealed = integrity.seal(_deck(), signature: signature);
      expect(sealed.signature?.name, 'Jan Jansen');
      // The date is filled by the caller (the dialog); the model keeps it as-is.
      expect(integrity.verify(sealed), IntegrityStatus.intact);

      // Tampering with the signature after sealing is detected.
      final tampered = sealed.copyWith(
        signature: sealed.signature!.copyWith(name: 'Iemand anders'),
      );
      expect(integrity.verify(tampered), IntegrityStatus.changed);
    });

    test('deckIntegrityStatus helper mirrors verify()', () {
      final sealed = integrity.seal(_deck());
      expect(deckIntegrityStatus(sealed), IntegrityStatus.intact);
      expect(deckIntegrityStatus(_deck()), IntegrityStatus.notSealed);
    });
  });
}
