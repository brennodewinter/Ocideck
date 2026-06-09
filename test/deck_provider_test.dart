import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
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

  test('loadDeck resolves a relative logo for an unsaved recovered deck', () {
    final temp = Directory.systemTemp.createTempSync(
      'ocideck_recovered_logo_test_',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final logo = File('${temp.path}/logos/client.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    final md = MarkdownService();
    final file = FileService(
      md,
      ImageService(),
      () => const ThemeProfile(),
      homeDirectory: () => temp.path,
    );
    final notifier = DeckNotifier(md, file);
    notifier.loadDeck(
      Deck(
        title: 'Hersteld',
        themeProfile: const ThemeProfile(logoPath: 'logos/client.png'),
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

  test('clearAllChecklists is a single undoable step that restores the checks', () {
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
  });

  test('clearAllChecklists is a no-op when nothing is checked', () {
    final n = _notifier()..newDeck('D');
    final slide = Slide.create(SlideType.bullets).copyWith(
      listStyle: ListStyle.checklist,
      bullets: ['[ ] Open'],
    );
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
}
