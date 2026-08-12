import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/deck_builder.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/models/source_table.dart';
import 'package:ocideck/services/import/pipeline/slide_classifier.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// De toets die ontbrak: **kan de gebruiker met zijn `.md` verder?**
///
/// Een geïmporteerd deck is pas iets waard als het de rondgang overleeft —
/// serialiseren met [MarkdownService.generateDeck], terugparsen met
/// [MarkdownService.parseDeck], en dan nog steeds hetzelfde zijn. 27
/// testbestanden bewaakten de import zelf, maar geen enkele nam het gebouwde
/// deck mee door het formaat waarin het uiteindelijk leeft. Precies dáár zat
/// een breuk: een zachte regelafbreking uit PowerPoint zette een `\n` ín een
/// bullet, en na opslaan-en-heropenen verhuisde die vervolgregel naar een
/// ander veld of verdween hij.
void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  final md = MarkdownService();

  Deck buildDeck(List<SourceSlide> slides) => DeckBuilder().build(
    SourceDeck(slides: slides),
    [for (final s in slides) classifySlide(s)],
    title: 'Rondgang',
  ).deck;

  Deck roundTrip(Deck deck) {
    final text = md.generateDeck(deck);
    final parsed = md.parseDeck(text);
    expect(parsed, isNotNull, reason: 'het eigen deck moet leesbaar zijn');
    return parsed!;
  }

  BodyBlock bullet(String t, [int order = 0]) =>
      BodyBlock(kind: BodyBlockKind.bullet, text: t, order: order);

  test('bullets overleven serialiseren en terugparsen', () {
    final deck = buildDeck([
      SourceSlide(
        index: 0,
        title: 'Plan',
        bodyBlocks: [bullet('Een', 0), bullet('Twee', 1)],
      ),
    ]);
    final back = roundTrip(deck);
    expect(back.slides.first.type, SlideType.bullets);
    expect(back.slides.first.bullets, ['Een', 'Twee']);
  });

  test('een zachte regelafbreking in een bullet overleeft de rondgang', () {
    // PowerPoint schrijft `<a:br/>`; de importer maakt daar een `\n` van, midden
    // in één bullet. Ongewijzigd weggeschreven brak dat de lijst: bij het
    // terugparsen werd de vervolgregel de paragraaf van de dia — en bij een
    // tweede zulke bullet verdween hij helemaal.
    final deck = buildDeck([
      SourceSlide(
        index: 0,
        title: 'Zacht',
        bodyBlocks: [
          bullet('Eerste regel\nvervolg één', 0),
          bullet('Tweede regel\nvervolg twee', 1),
        ],
      ),
    ]);
    final back = roundTrip(deck);
    final bullets = back.slides.first.bullets;
    expect(bullets.length, 2, reason: 'geen bullet mag verdwijnen');
    expect(bullets[0], contains('vervolg één'));
    expect(bullets[1], contains('vervolg twee'));
  });

  test('een tabel met lastige tekens overleeft de rondgang', () {
    final deck = buildDeck([
      SourceSlide(
        index: 0,
        title: 'Cijfers',
        table: const SourceTable(
          header: ['naam', 'notitie'],
          rows: [
            ['a|b', 'met een pipe'],
            ['c', 'met een\nregeleinde'],
          ],
        ),
      ),
    ]);
    final back = roundTrip(deck);
    final rows = back.slides.first.tableRows;
    expect(rows.first, ['naam', 'notitie']);
    expect(
      rows[1][0],
      'a|b',
      reason: 'een pipe in een cel mag de tabel niet breken',
    );
    expect(rows.length, 3);
  });

  test('de weergavelimiet reist mee en de data blijft compleet', () {
    final deck = buildDeck([
      SourceSlide(
        index: 0,
        title: 'Lang',
        bodyBlocks: [for (var i = 0; i < 30; i++) bullet('punt $i', i)],
      ),
    ]);
    final back = roundTrip(deck);
    final slide = back.slides.first;
    expect(slide.bullets.length, 30, reason: 'niets gesnoeid in het bestand');
    expect(slide.viewLimit?.limit, kImportedBulletLimit);
  });

  test('een notitiedia over niet-overgenomen inhoud overleeft de rondgang', () {
    final deck = buildDeck([
      SourceSlide(
        index: 0,
        bodyBlocks: [
          BodyBlock(kind: BodyBlockKind.paragraph, text: 'Inleiding'),
          bullet('Een', 1),
        ],
      ),
    ]);
    final back = roundTrip(deck);
    // De niet-overgenomen inhoud zit nu in de notities van de dia zelf. De
    // tekst moet in het bestand overleven — dat is wat de belofte waard maakt.
    final all = back.slides
        .map(
          (s) => [s.title, s.customMarkdown, s.notes, ...s.bullets].join(' '),
        )
        .join('\n');
    expect(all, contains('Alinea'));
  });

  test('een titel met tekens die het formaat raken overleeft de rondgang', () {
    final deck = buildDeck([
      const SourceSlide(index: 0, title: '--- niet de scheiding ---'),
    ]);
    final back = roundTrip(deck);
    expect(
      back.slides.length,
      1,
      reason: 'geen dia erbij door een valse scheiding',
    );
    expect(back.slides.first.title, contains('niet de scheiding'));
  });
}
