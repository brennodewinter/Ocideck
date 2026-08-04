import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/menu_blocks.dart';

// Fase 3 van #1162: het keuze-menu-diatype. De blokken leven als link-bullets;
// dit toetst dat parse↔format en de volledige markdown-round-trip niets verliezen.
void main() {
  group('parseMenuBlock', () {
    test('leest label + doelanker uit een link', () {
      final b = parseMenuBlock('[Prijzen](#prijzen)');
      expect(b.label, 'Prijzen');
      expect(b.targetAnchor, 'prijzen');
      expect(b.hasImage, isFalse);
    });

    test('leest een optionele afbeelding erbij', () {
      final b = parseMenuBlock('[Demo](#demo) ![](mem:9f2a1c)');
      expect(b.label, 'Demo');
      expect(b.targetAnchor, 'demo');
      expect(b.imagePath, 'mem:9f2a1c');
    });

    test('een blok zonder link is een gewoon tekstblok', () {
      final b = parseMenuBlock('Gewoon een kop');
      expect(b.label, 'Gewoon een kop');
      expect(b.hasTarget, isFalse);
      expect(b.hasImage, isFalse);
    });
  });

  group('menuBlockToBullet', () {
    test('is de inverse van parseMenuBlock', () {
      for (final block in const [
        MenuBlock(label: 'Prijzen', targetAnchor: 'prijzen'),
        MenuBlock(label: 'Demo', targetAnchor: 'demo', imagePath: 'mem:x'),
        MenuBlock(label: 'Platte tekst'),
      ]) {
        expect(parseMenuBlock(menuBlockToBullet(block)), block);
      }
    });
  });

  test('een menudia round-trippt verliesvrij door de markdown', () {
    final md = MarkdownService();
    final deck = Deck(
      title: 'Demo',
      slides: [
        Slide.create(SlideType.menu).copyWith(
          title: 'Kies een onderwerp',
          anchor: 'hoofdmenu',
          bullets: [
            '[Prijzen](#prijzen)',
            '[Demo](#demo) ![](mem:9f2a1c)',
            'Platte tekst',
          ],
        ),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Prijzen', anchor: 'prijzen', bullets: ['x']),
      ],
    );

    final back = md.parseDeck(md.generateDeck(deck))!;

    expect(
      back.slides[0].type,
      SlideType.menu,
      reason: 'type overleeft herladen',
    );
    expect(back.slides[0].bullets, deck.slides[0].bullets);
    final blocks = menuBlocksFor(back.slides[0].bullets);
    expect(blocks[0].targetAnchor, 'prijzen');
    expect(blocks[1].imagePath, 'mem:9f2a1c');
    expect(blocks[2].hasTarget, isFalse);
  });
}
