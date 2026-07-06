import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart'
    show kSingleColumnBulletWarningCount;
import 'package:ocideck/state/deck_provider.dart';

DeckNotifier _notifier() {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  return DeckNotifier(md, file);
}

void main() {
  test('newDeck creates one title slide and is dirty', () {
    final n = _notifier();
    n.newDeck('Mijn deck');
    expect(n.state.isOpen, isTrue);
    expect(n.state.deck!.slides, hasLength(1));
    expect(n.state.deck!.slides.single.type, SlideType.title);
    expect(n.state.deck!.slides.single.title, 'Mijn deck');
    expect(n.state.isDirty, isTrue);
  });

  test('newDeck with a template opens with its example slides', () {
    final n = _notifier();
    n.newDeck('Mijn briefing', template: deckTemplateById('briefing'));
    final slides = n.state.deck!.slides;
    expect(slides, hasLength(6));
    expect(slides.first.type, SlideType.title);
    expect(slides.first.title, 'Mijn briefing');
    expect(slides.skip(1).map((s) => s.type), everyElement(SlideType.bullets));
    expect(n.state.isDirty, isTrue);
  });

  test('loadDeck applies the active profile and resolves its relative logo', () {
    final temp = Directory.systemTemp.createTempSync(
      'ocideck_recovered_logo_test_',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final logo = File('${temp.path}/logos/client.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    final md = MarkdownService();
    // Styling comes from the active style profile, not from the deck/markdown.
    final file = FileService(
      md,
      ImageService(),
      () => const ThemeProfile(logoPath: 'logos/client.png'),
      homeDirectory: () => temp.path,
    );
    final notifier = DeckNotifier(md, file);
    notifier.loadDeck(
      Deck(
        title: 'Hersteld',
        // The deck's own profile is ignored on load.
        themeProfile: const ThemeProfile(logoPath: 'should-be-ignored.png'),
        slides: [Slide.create(SlideType.title)],
      ),
    );

    expect(notifier.state.filePath, isNull);
    expect(notifier.state.deck!.projectPath, isNull);
    expect(notifier.state.deck!.themeProfile.logoPath, logo.path);
  });

  test('addSlide inserts right after the given index', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets); // appended -> index 1
    n.addSlide(SlideType.image, afterIndex: 0); // inserted at index 1
    final types = n.state.deck!.slides.map((s) => s.type).toList();
    expect(types, [SlideType.title, SlideType.image, SlideType.bullets]);
  });

  test('removeSlide removes a slide but never the last one', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    n.removeSlide(0);
    expect(n.state.deck!.slides, hasLength(1));
    // Now only one remains; removing again is a no-op.
    n.removeSlide(0);
    expect(n.state.deck!.slides, hasLength(1));
  });

  test('duplicateSlide inserts a copy with a fresh id', () {
    final n = _notifier()..newDeck('D');
    final originalId = n.state.deck!.slides.first.id;
    n.duplicateSlide(0);
    final slides = n.state.deck!.slides;
    expect(slides, hasLength(2));
    expect(slides[1].title, slides[0].title);
    expect(slides[1].id, isNot(originalId));
  });

  test('splitSlide moves overflow bullets onto a fresh second slide', () {
    // Layout-metingen gebruiken TextPainter; binding moet geïnitialiseerd zijn.
    TestWidgetsFlutterBinding.ensureInitialized();
    final n = _notifier()..newDeck('D');
    final bullets = List.generate(30, (i) => 'Bullet met wat tekst nummer $i');
    n.addSlide(SlideType.bullets, afterIndex: 0);
    n.updateSlide(1, n.state.deck!.slides[1].copyWith(bullets: bullets));

    n.splitSlide(1);

    final slides = n.state.deck!.slides;
    expect(slides, hasLength(3));
    final first = slides[1];
    final second = slides[2];
    expect(first.type, SlideType.bullets);
    expect(second.type, SlideType.bullets);
    expect(second.id, isNot(first.id));
    // Beide helften houden minstens één bullet en samen zijn ze het origineel.
    expect(first.bullets, isNotEmpty);
    expect(second.bullets, isNotEmpty);
    expect([...first.bullets, ...second.bullets], bullets);
    // Slide 1 houdt het optimum: de leesbaarheidsdrempel (8 bullets), niet het
    // fysieke maximum dat nog zou passen.
    expect(first.bullets.length, kSingleColumnBulletWarningCount);
    expect(second.bullets.length, 30 - kSingleColumnBulletWarningCount);
    // Alleen de tweede helft is een vervolgpagina: die deelt straks de
    // fontgrootte met de eerste; de eerste blijft een gewone (start)slide.
    expect(first.continuesSplit, isFalse);
    expect(second.continuesSplit, isTrue);
  });

  test('splitSlide marks the second column-split half as a continuation', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final n = _notifier()..newDeck('D');
    final left = List.generate(12, (i) => 'Links $i');
    final right = List.generate(12, (i) => 'Rechts $i');
    n.addSlide(SlideType.twoBullets, afterIndex: 0);
    n.updateSlide(
      1,
      n.state.deck!.slides[1].copyWith(bullets: left, bullets2: right),
    );

    n.splitSlide(1);

    final slides = n.state.deck!.slides;
    expect(slides, hasLength(3));
    expect(slides[1].continuesSplit, isFalse);
    expect(slides[2].continuesSplit, isTrue);
    expect(slides[2].type, SlideType.twoBullets);
  });

  test('splitSlide is a no-op for non-bullet slides', () {
    final n = _notifier()..newDeck('D'); // enkele titelslide
    n.splitSlide(0);
    expect(n.state.deck!.slides, hasLength(1));
  });

  test('splitSlide also works on a bullets+image slide that still fits', () {
    // De gemelde casus: weinig bullets náást een afbeelding. Het tekstvlak is
    // smal, en de gebruiker wil toch in tweeën knippen; dan splitsen we
    // doormidden in plaats van een dode klik.
    TestWidgetsFlutterBinding.ensureInitialized();
    final n = _notifier()..newDeck('D');
    final bullets = List.generate(6, (i) => 'Bullet $i');
    n.addSlide(SlideType.bulletsImage, afterIndex: 0);
    n.updateSlide(
      1,
      n.state.deck!.slides[1].copyWith(imagePath: 'foto.png', bullets: bullets),
    );

    n.splitSlide(1);

    final slides = n.state.deck!.slides;
    expect(slides, hasLength(3));
    // The first half keeps the image; the continuation page is pure text.
    expect(slides[1].type, SlideType.bulletsImage);
    expect(slides[1].imagePath, 'foto.png');
    expect(slides[2].type, SlideType.bullets);
    expect(slides[2].imagePath, isEmpty);
    expect(slides[1].bullets, isNotEmpty);
    expect(slides[2].bullets, isNotEmpty);
    expect([...slides[1].bullets, ...slides[2].bullets], bullets);
  });

  test('insertSlides duplicates with fresh ids and returns insert index', () {
    final n = _notifier()..newDeck('D');
    final source = Slide.create(SlideType.bullets).copyWith(title: 'Bron');
    final at = n.insertSlides([source], afterIndex: 0);
    expect(at, 1);
    expect(n.state.deck!.slides, hasLength(2));
    expect(n.state.deck!.slides[1].title, 'Bron');
    expect(n.state.deck!.slides[1].id, isNot(source.id));
  });

  test('copying a selection into another deck leaves the source intact', () {
    // Source deck with three slides; "select" indices 0 and 2.
    final source = _notifier()..newDeck('Bron');
    source.addSlide(SlideType.bullets); // 1
    source.addSlide(SlideType.image); // 2
    final picked = [source.state.deck!.slides[0], source.state.deck!.slides[2]];
    final sourceIdsBefore = source.state.deck!.slides.map((s) => s.id).toList();

    // Target deck receives the copies (appended at the end).
    final target = _notifier()..newDeck('Doel');
    final at = target.insertSlides(picked);

    expect(at, 1); // appended after the single title slide
    expect(target.state.deck!.slides, hasLength(3));
    expect(target.state.deck!.slides[1].type, SlideType.title);
    expect(target.state.deck!.slides[2].type, SlideType.image);
    // Copies must have fresh ids, not the source ids.
    expect(
      target.state.deck!.slides[1].id,
      isNot(anyOf(picked.map((s) => s.id))),
    );
    // The source deck is untouched.
    expect(
      source.state.deck!.slides.map((s) => s.id).toList(),
      sourceIdsBefore,
    );
  });

  test('reorderSlides moves a slide to a new position', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets); // 1
    n.addSlide(SlideType.image); // 2
    n.reorderSlides(2, 0);
    expect(n.state.deck!.slides.first.type, SlideType.image);
  });

  // Bouwt een deck met slides getiteld "0".."5" zodat de volgorde traceerbaar is.
  DeckNotifier titledDeck() {
    final n = _notifier()..newDeck('D');
    for (var i = 0; i < 5; i++) {
      n.addSlide(SlideType.bullets);
    }
    final slides = n.state.deck!.slides;
    for (var i = 0; i < slides.length; i++) {
      n.updateSlide(i, slides[i].copyWith(title: '$i'));
    }
    return n;
  }

  List<String> titles(DeckNotifier n) =>
      n.state.deck!.slides.map((s) => s.title).toList();

  test('moveSlides moves a contiguous block downward as one unit', () {
    final n = titledDeck();
    final start = n.moveSlides({0, 1}, 1, 3);
    expect(titles(n), ['2', '3', '0', '1', '4', '5']);
    expect(start, 2);
  });

  test('moveSlides moves a contiguous block upward as one unit', () {
    final n = titledDeck();
    final start = n.moveSlides({3, 4}, 3, 1);
    expect(titles(n), ['0', '3', '4', '1', '2', '5']);
    expect(start, 1);
  });

  test(
    'moveSlides gathers a non-contiguous selection into one ordered block',
    () {
      final n = titledDeck();
      final start = n.moveSlides({0, 2, 4}, 2, 4);
      // De selectie {0,2,4} wordt één aaneengesloten blok in oorspronkelijke
      // volgorde, geplaatst vóór slide "5".
      expect(titles(n), ['1', '3', '0', '2', '4', '5']);
      expect(start, 2);
    },
  );

  test('moveSlides can drop the block at the end', () {
    final n = titledDeck();
    final start = n.moveSlides({0, 1}, 0, 5);
    expect(titles(n), ['2', '3', '4', '5', '0', '1']);
    expect(start, 4);
  });

  test('moveSlides falls back to a single move for a lone selection', () {
    final n = titledDeck();
    n.moveSlides({2}, 2, 0);
    expect(titles(n), ['2', '0', '1', '3', '4', '5']);
  });

  test('updateSlide replaces the slide at an index', () {
    final n = _notifier()..newDeck('D');
    final updated = n.state.deck!.slides.first.copyWith(title: 'Nieuw');
    n.updateSlide(0, updated);
    expect(n.state.deck!.slides.first.title, 'Nieuw');
  });

  test('clearAllChecklists unchecks every checklist item across the deck', () {
    final n = _notifier()..newDeck('D');
    final s1 = Slide.create(SlideType.bullets).copyWith(
      listStyle: ListStyle.checklist,
      bullets: ['[x] Klaar', '\t[X] Subklaar', '[ ] Open'],
    );
    final s2 = Slide.create(SlideType.bullets).copyWith(
      listStyle: ListStyle.checklist,
      bullets: ['[x] Eerste kolom'],
      bullets2: ['[x] Tweede kolom', '[ ] Nog open'],
    );
    n.loadDeck(n.state.deck!.copyWith(slides: [s1, s2]));

    expect(n.checkedChecklistCount, 4);
    final revisionBefore = n.state.revision;

    n.clearAllChecklists();

    expect(n.checkedChecklistCount, 0);
    final out = n.state.deck!.slides;
    expect(out[0].bullets, ['[ ] Klaar', '\t[ ] Subklaar', '[ ] Open']);
    expect(out[1].bullets, ['[ ] Eerste kolom']);
    expect(out[1].bullets2, ['[ ] Tweede kolom', '[ ] Nog open']);
    // Revision bumps so the open slide editor remounts and reflects the change.
    expect(n.state.revision, greaterThan(revisionBefore));
  });

  test(
    'clearAllChecklists is a single undoable step that restores the checks',
    () {
      final n = _notifier()..newDeck('D');
      final slide = Slide.create(SlideType.bullets).copyWith(
        listStyle: ListStyle.checklist,
        bullets: ['[x] Klaar', '[ ] Open'],
        bullets2: ['[x] Tweede'],
      );
      n.loadDeck(n.state.deck!.copyWith(slides: [slide]));
      expect(n.checkedChecklistCount, 2);

      n.clearAllChecklists();
      expect(n.checkedChecklistCount, 0);
      expect(n.state.canUndo, isTrue);
      final revisionAfterClear = n.state.revision;

      n.undo();

      // One undo restores every checked item in both columns...
      expect(n.checkedChecklistCount, 2);
      expect(n.state.deck!.slides.first.bullets, ['[x] Klaar', '[ ] Open']);
      expect(n.state.deck!.slides.first.bullets2, ['[x] Tweede']);
      // ...and bumps the revision again so the open editor reflects the restore.
      expect(n.state.revision, greaterThan(revisionAfterClear));
    },
  );

  test('clearAllChecklists is a no-op when nothing is checked', () {
    final n = _notifier()..newDeck('D');
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(listStyle: ListStyle.checklist, bullets: ['[ ] Open']);
    n.loadDeck(n.state.deck!.copyWith(slides: [slide]));
    expect(n.state.canUndo, isFalse);

    n.clearAllChecklists();

    // No checked items, so no history entry is recorded.
    expect(n.state.canUndo, isFalse);
    expect(n.checkedChecklistCount, 0);
  });

  test('updateMeta changes deck title/theme/paginate', () {
    final n = _notifier()..newDeck('D');
    n.updateMeta(title: 'Andere titel', theme: 'custom', paginate: false);
    expect(n.state.deck!.title, 'Andere titel');
    expect(n.state.deck!.theme, 'custom');
    expect(n.state.deck!.paginate, isFalse);
  });

  test('updateInfo can update the presentation title', () {
    final n = _notifier()..newDeck('D');
    n.updateInfo(title: 'Nieuwe presentatietitel', author: 'Auteur');
    expect(n.state.deck!.title, 'Nieuwe presentatietitel');
    expect(n.state.deck!.author, 'Auteur');
  });

  test('generateMarkdown and applyMarkdown round-trip the deck', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bulletsImage, afterIndex: 0);
    n.updateSlide(
      1,
      n.state.deck!.slides[1].copyWith(
        title: 'Met beeld',
        bullets: ['Punt'],
        imagePath: 'images/x.png',
      ),
    );

    final markdown = n.generateMarkdown();
    expect(n.applyMarkdown(markdown), isTrue);

    final slides = n.state.deck!.slides;
    expect(slides, hasLength(2));
    expect(slides[1].type, SlideType.bulletsImage);
    expect(slides[1].imagePath, 'images/x.png');
  });

  test('slide operations are no-ops when no deck is open', () {
    final n = _notifier();
    n.addSlide(SlideType.bullets);
    n.removeSlide(0);
    n.duplicateSlide(0);
    expect(n.state.isOpen, isFalse);
  });

  // ── Ongedaan maken / opnieuw uitvoeren ─────────────────────────────────────

  test('a fresh deck has nothing to undo or redo', () {
    final n = _notifier()..newDeck('D');
    expect(n.canUndo, isFalse);
    expect(n.canRedo, isFalse);
    expect(n.state.canUndo, isFalse);
    expect(n.state.canRedo, isFalse);
  });

  test('undo reverts the last structural change and redo re-applies it', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    expect(n.state.deck!.slides, hasLength(2));
    expect(n.canUndo, isTrue);

    n.undo();
    expect(n.state.deck!.slides, hasLength(1));
    expect(n.canUndo, isFalse);
    expect(n.canRedo, isTrue);

    n.redo();
    expect(n.state.deck!.slides, hasLength(2));
    expect(n.canRedo, isFalse);
  });

  test('undo/redo bumps revision so editors can re-sync', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    final rev0 = n.state.revision;
    n.undo();
    expect(n.state.revision, rev0 + 1);
    n.redo();
    expect(n.state.revision, rev0 + 2);
  });

  test('rapid edits to the same slide coalesce into one undo step', () {
    final n = _notifier()..newDeck('D');
    // Three quick edits to slide 0 within the coalesce window.
    n.updateSlide(0, n.state.deck!.slides.first.copyWith(title: 'A'));
    n.updateSlide(0, n.state.deck!.slides.first.copyWith(title: 'AB'));
    n.updateSlide(0, n.state.deck!.slides.first.copyWith(title: 'ABC'));
    expect(n.state.deck!.slides.first.title, 'ABC');

    // A single undo jumps back past the whole burst to the original title.
    n.undo();
    expect(n.state.deck!.slides.first.title, 'D');
    expect(n.canUndo, isFalse);
  });

  test('a new edit clears the redo stack', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    n.undo();
    expect(n.canRedo, isTrue);
    n.addSlide(SlideType.image); // diverging edit
    expect(n.canRedo, isFalse);
  });

  test('undo and redo are no-ops when their stacks are empty', () {
    final n = _notifier()..newDeck('D');
    n.undo(); // nothing to undo
    expect(n.state.deck!.slides, hasLength(1));
    n.redo(); // nothing to redo
    expect(n.state.deck!.slides, hasLength(1));
  });

  test('loading a deck clears the history', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    expect(n.canUndo, isTrue);
    n.loadDeck(n.state.deck!);
    expect(n.canUndo, isFalse);
    expect(n.canRedo, isFalse);
  });

  // ── Slides overslaan ───────────────────────────────────────────────────────

  test('toggleSkip flips a single slide and reports the count', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    expect(n.skippedCount, 0);

    n.toggleSkip(1);
    expect(n.state.deck!.slides[1].skipped, isTrue);
    expect(n.state.deck!.slides[0].skipped, isFalse);
    expect(n.skippedCount, 1);

    n.toggleSkip(1);
    expect(n.state.deck!.slides[1].skipped, isFalse);
    expect(n.skippedCount, 0);
  });

  test('toggleSkip is undoable', () {
    final n = _notifier()..newDeck('D');
    n.toggleSkip(0);
    expect(n.state.deck!.slides.first.skipped, isTrue);
    n.undo();
    expect(n.state.deck!.slides.first.skipped, isFalse);
  });

  test('clearAllSkips resets every slide in one step', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    n.addSlide(SlideType.image);
    n.toggleSkip(0);
    n.toggleSkip(2);
    expect(n.skippedCount, 2);

    n.clearAllSkips();
    expect(n.skippedCount, 0);

    // One undo brings back the whole skipped set.
    n.undo();
    expect(n.skippedCount, 2);
  });

  test('clearAllSkips is a no-op when nothing is skipped', () {
    final n = _notifier()..newDeck('D');
    final before = n.canUndo;
    n.clearAllSkips();
    expect(n.canUndo, before); // geen nieuwe ongedaan-maken-stap
  });

  // ── Bulk-acties (multi-select) ─────────────────────────────────────────────

  test('removeSlides deletes several at once but keeps at least one', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets); // 1
    n.addSlide(SlideType.image); // 2
    n.addSlide(SlideType.quote); // 3  → 4 slides total
    n.removeSlides({1, 3});
    final types = n.state.deck!.slides.map((s) => s.type).toList();
    expect(types, [SlideType.title, SlideType.image]);

    // Mag nooit alles verwijderen.
    n.removeSlides({0, 1});
    expect(n.state.deck!.slides, hasLength(2));
  });

  test('removeSlides is one undoable step', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    n.addSlide(SlideType.image);
    n.removeSlides({1, 2});
    expect(n.state.deck!.slides, hasLength(1));
    n.undo();
    expect(n.state.deck!.slides, hasLength(3));
  });

  test('setSkippedForSlides toggles skip on a set in one step', () {
    final n = _notifier()..newDeck('D');
    n.addSlide(SlideType.bullets);
    n.addSlide(SlideType.image);
    n.setSkippedForSlides({0, 2}, true);
    expect(n.state.deck!.slides[0].skipped, isTrue);
    expect(n.state.deck!.slides[1].skipped, isFalse);
    expect(n.state.deck!.slides[2].skipped, isTrue);
    expect(n.skippedCount, 2);

    n.setSkippedForSlides({0, 2}, false);
    expect(n.skippedCount, 0);
  });

  // ── Zoeken & vervangen ─────────────────────────────────────────────────────

  test('countMatches and replaceAll span all text fields', () {
    final n = _notifier()..newDeck('Acme jaarverslag');
    n.updateSlide(
      0,
      n.state.deck!.slides.first.copyWith(
        title: 'Acme groeit',
        bullets: ['Acme wint', 'overig'],
        notes: 'Acme intern',
      ),
    );

    expect(n.countMatches('Acme'), 3);

    final replaced = n.replaceAll('Acme', 'Globex');
    expect(replaced, 3);
    expect(n.countMatches('Acme'), 0);

    final slide = n.state.deck!.slides.first;
    expect(slide.title, 'Globex groeit');
    expect(slide.bullets.first, 'Globex wint');
    expect(slide.notes, 'Globex intern');
  });

  test('replaceAll is case-insensitive by default and exact when asked', () {
    final n = _notifier()..newDeck('D');
    n.updateSlide(
      0,
      n.state.deck!.slides.first.copyWith(title: 'Test test TEST'),
    );

    // Default: alle drie, ongeacht hoofdletters.
    expect(n.countMatches('test'), 3);
    // Hoofdlettergevoelig: alleen de exacte 'test'.
    expect(n.countMatches('test', caseSensitive: true), 1);

    n.replaceAll('test', 'x', caseSensitive: true);
    expect(n.state.deck!.slides.first.title, 'Test x TEST');
  });

  test('replaceAll is a single undoable step and a no-op without matches', () {
    final n = _notifier()..newDeck('D');
    n.updateSlide(
      0,
      n.state.deck!.slides.first.copyWith(title: 'Hallo wereld'),
    );
    final undosBefore = n.canUndo;

    expect(n.replaceAll('xyz', 'q'), 0); // geen match → niets verandert
    expect(n.canUndo, undosBefore);

    n.replaceAll('wereld', 'aarde');
    expect(n.state.deck!.slides.first.title, 'Hallo aarde');
    n.undo(); // één stap terug herstelt de hele vervanging
    expect(n.state.deck!.slides.first.title, 'Hallo wereld');
  });

  test('find and replace covers the second column and both column titles', () {
    final n = _notifier();
    n.loadDeck(
      Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.twoBullets).copyWith(
            title: 'foo title',
            columnTitle1: 'foo left',
            columnTitle2: 'foo right',
            bullets: ['foo a'],
            bullets2: ['foo b', 'foo c'],
          ),
        ],
      ),
    );

    // title + columnTitle1 + columnTitle2 + bullets(1) + bullets2(2) = 6
    expect(n.countMatches('foo'), 6);
    expect(n.replaceAll('foo', 'bar'), 6);

    final s = n.state.deck!.slides.first;
    expect(s.columnTitle1, 'bar left');
    expect(s.columnTitle2, 'bar right');
    expect(s.bullets2, ['bar b', 'bar c']);
  });

  test('applyMarkdown preserves annotations across a toggle', () {
    final n = _notifier();
    n.loadDeck(
      Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.title).copyWith(title: 'A'),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'B', bullets: ['punt']),
        ],
      ),
    );
    final slideId = n.state.deck!.slides[1].id;
    n.setAnnotations({
      slideId: const [
        InkStroke(
          tool: InkTool.pen,
          color: 0xFF112233,
          width: 0.01,
          points: [Offset(0.1, 0.1), Offset(0.2, 0.2)],
        ),
      ],
    });
    expect(n.state.deck!.annotations, isNotEmpty);

    final md = n.generateMarkdown();
    expect(n.applyMarkdown(md), isTrue);

    // The ink layer survived the markdown round-trip (re-anchored to the new
    // slide id), so a subsequent save won't wipe the drawing's sidecar.
    final strokes = n.state.deck!.annotations.values.expand((s) => s).toList();
    expect(strokes, isNotEmpty);
    expect(strokes.first.color, 0xFF112233);
  });

  test('generateMarkdown inlines linked chart data for the editor', () {
    final n = _notifier();
    const chartBlock =
        '{"type":"bar","source":"data.csv",'
        '"x":["a","b"],"series":[{"label":"S","data":[1,2]}]}';
    n.loadDeck(
      Deck(
        title: 'C',
        slides: [
          Slide.create(SlideType.chart).copyWith(customMarkdown: chartBlock),
        ],
      ),
    );
    final md = n.generateMarkdown();
    // Inline points are kept (not dropped to source-only) so a toggle round-trip
    // doesn't blank the chart; the source link is still present.
    expect(md, contains('"x"'));
    expect(md, contains('data.csv'));
    expect(n.applyMarkdown(md), isTrue);
    expect(n.state.deck!.slides.first.customMarkdown, contains('"x"'));
  });

  test('updateSlide coalesces consecutive edits of the same slide', () {
    final n = _notifier()..newDeck('Deck');
    n.addSlide(SlideType.bullets); // 2 slides; undo stack now has 1 entry
    final undoDepthBefore = n.canUndo;
    expect(undoDepthBefore, isTrue);
    final slide = n.state.deck!.slides[0];
    // Two quick edits to the same slide collapse into a single undo step.
    n.updateSlide(0, slide.copyWith(title: 'X'));
    n.updateSlide(0, slide.copyWith(title: 'XY'));
    // Undo once returns to before BOTH edits (title back to the original).
    n.undo();
    expect(n.state.deck!.slides[0].title, isNot('XY'));
    expect(n.state.deck!.slides[0].title, isNot('X'));
  });
}
