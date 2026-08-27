import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/slide.dart';

/// A distinctive, non-default value for each [SlideField], paired with a reader
/// that pulls the field back off a [Slide]. Every value differs from a freshly
/// created slide's default so that a wrong-field mapping (setting `subtitle`
/// where `title` was meant) is observable, not just a readback that happens to
/// match.
final Map<SlideField, ({Object? value, Object? Function(Slide) read})>
_slideCases = {
  SlideField.type: (value: SlideType.quote, read: (s) => s.type),
  SlideField.listStyle: (value: ListStyle.numbered, read: (s) => s.listStyle),
  SlideField.tlp: (value: TlpLevel.red, read: (s) => s.tlp),
  SlideField.title: (value: 'a title', read: (s) => s.title),
  SlideField.subtitle: (value: 'a subtitle', read: (s) => s.subtitle),
  SlideField.columnTitle1: (value: 'col1', read: (s) => s.columnTitle1),
  SlideField.columnTitle2: (value: 'col2', read: (s) => s.columnTitle2),
  SlideField.imagePath: (value: 'img/a.png', read: (s) => s.imagePath),
  SlideField.imagePath2: (value: 'img/b.png', read: (s) => s.imagePath2),
  SlideField.imageCaption: (value: 'cap', read: (s) => s.imageCaption),
  SlideField.imageCaption2: (value: 'cap2', read: (s) => s.imageCaption2),
  SlideField.imageAltText: (value: 'alt', read: (s) => s.imageAltText),
  SlideField.imageAltText2: (value: 'alt2', read: (s) => s.imageAltText2),
  SlideField.videoPath: (value: 'v/a.mp4', read: (s) => s.videoPath),
  SlideField.audioPath: (value: 'a/a.mp3', read: (s) => s.audioPath),
  SlideField.quote: (value: 'be excellent', read: (s) => s.quote),
  SlideField.quoteAuthor: (value: 'someone', read: (s) => s.quoteAuthor),
  SlideField.customMarkdown: (value: '# hi', read: (s) => s.customMarkdown),
  SlideField.codeLanguage: (value: 'dart', read: (s) => s.codeLanguage),
  SlideField.cssClass: (value: 'lead', read: (s) => s.cssClass),
  SlideField.notes: (value: 'speaker note', read: (s) => s.notes),
  SlideField.titleTextColorOverride: (
    value: '#ff0000',
    read: (s) => s.titleTextColorOverride,
  ),
  SlideField.titleColumnLayout: (
    value: TitleColumnLayout.both,
    read: (s) => s.titleColumnLayout,
  ),
  SlideField.findingId: (value: 'F-1', read: (s) => s.findingId),
  SlideField.checklistScope: (value: 'web', read: (s) => s.checklistScope),
  SlideField.improvementTemplateId: (
    value: 'tmpl-1',
    read: (s) => s.improvementTemplateId,
  ),
  SlideField.bullets: (value: ['a', 'b'], read: (s) => s.bullets),
  SlideField.bullets2: (value: ['c', 'd'], read: (s) => s.bullets2),
  SlideField.preservedMarpLines: (
    value: ['<!-- _future: value -->'],
    read: (s) => s.preservedMarpLines,
  ),
  SlideField.marpStyle: (
    value: const MarpStyle(color: '#123456'),
    read: (s) => s.marpStyle,
  ),
  SlideField.showChecklistProgress: (
    value: true,
    read: (s) => s.showChecklistProgress,
  ),
  SlideField.continueNumbering: (value: true, read: (s) => s.continueNumbering),
  SlideField.continuesSplit: (value: true, read: (s) => s.continuesSplit),
  SlideField.videoAutoplay: (value: true, read: (s) => s.videoAutoplay),
  SlideField.audioAutoplay: (value: true, read: (s) => s.audioAutoplay),
  SlideField.titleImageOverlay: (
    value: false,
    read: (s) => s.titleImageOverlay,
  ),
  SlideField.imageTitleAbove: (value: true, read: (s) => s.imageTitleAbove),
  SlideField.showLogo: (value: false, read: (s) => s.showLogo),
  SlideField.showFooter: (value: false, read: (s) => s.showFooter),
  SlideField.skipped: (value: true, read: (s) => s.skipped),
  SlideField.isDetail: (value: true, read: (s) => s.isDetail),
  SlideField.tableEditable: (value: true, read: (s) => s.tableEditable),
  SlideField.tableMarkOverdue: (value: true, read: (s) => s.tableMarkOverdue),
  SlideField.videoStartMs: (value: 1500, read: (s) => s.videoStartMs),
  SlideField.videoEndMs: (value: 3000, read: (s) => s.videoEndMs),
  SlideField.imageSize: (value: 42, read: (s) => s.imageSize),
  SlideField.imageZoom: (value: 140, read: (s) => s.imageZoom),
  SlideField.titleColumnWidth: (value: 30, read: (s) => s.titleColumnWidth),
  SlideField.imageFocalX: (value: 0.25, read: (s) => s.imageFocalX),
  SlideField.imageFocalY: (value: 0.75, read: (s) => s.imageFocalY),
  SlideField.imageFocalX2: (value: 0.1, read: (s) => s.imageFocalX2),
  SlideField.imageFocalY2: (value: 0.9, read: (s) => s.imageFocalY2),
  SlideField.advanceDuration: (value: 5.0, read: (s) => s.advanceDuration),
};

final Map<DeckMetaField, ({Object? value, Object? Function(Deck) read})>
_deckCases = {
  DeckMetaField.title: (value: 'the deck', read: (d) => d.title),
  DeckMetaField.theme: (value: 'dark', read: (d) => d.theme),
  DeckMetaField.author: (value: 'me', read: (d) => d.author),
  DeckMetaField.organization: (value: 'LibreKAT', read: (d) => d.organization),
  DeckMetaField.version: (value: '2.0', read: (d) => d.version),
  DeckMetaField.date: (value: '2026-07-30', read: (d) => d.date),
  DeckMetaField.description: (value: 'desc', read: (d) => d.description),
  DeckMetaField.keywords: (value: 'a, b', read: (d) => d.keywords),
  DeckMetaField.language: (value: 'en', read: (d) => d.language),
  DeckMetaField.improvementFramework: (
    value: 'dmaic',
    read: (d) => d.improvementFramework,
  ),
  DeckMetaField.tlp: (value: TlpLevel.amber, read: (d) => d.tlp),
  DeckMetaField.privacy: (
    value: PrivacyDisposition.redact,
    read: (d) => d.privacy,
  ),
  DeckMetaField.paginate: (value: false, read: (d) => d.paginate),
  DeckMetaField.showRehearsalSummary: (
    value: true,
    read: (d) => d.showRehearsalSummary,
  ),
  DeckMetaField.playOnly: (value: true, read: (d) => d.playOnly),
  DeckMetaField.presentationTargetSeconds: (
    value: 600,
    read: (d) => d.presentationTargetSeconds,
  ),
  DeckMetaField.standardsUsed: (
    value: ['OWASP WSTG@4.2'],
    read: (d) => d.standardsUsed,
  ),
  DeckMetaField.marpStyle: (
    value: const MarpStyle(footer: 'Voet'),
    read: (d) => d.marpStyle,
  ),
};

void main() {
  // Three slides with known, distinct ids to move and address.
  Slide slideA() => Slide.create(SlideType.bullets).copyWith(title: 'A');
  Slide slideB() => Slide.create(SlideType.bullets).copyWith(title: 'B');
  Slide slideC() => Slide.create(SlideType.bullets).copyWith(title: 'C');

  Deck deckOf(List<Slide> slides) => Deck(title: 'base', slides: slides);

  const author = 'u:tester';

  group('applyOp — structural', () {
    test('InsertSlide inserts at the index and leaves the rest in order', () {
      final a = slideA(), b = slideB(), c = slideC();
      final deck = deckOf([a, c]);
      final result = applyOp(
        deck,
        InsertSlide(version: 1, authorId: author, index: 1, slide: b),
      );
      expect(result.slides.map((s) => s.id), [a.id, b.id, c.id]);
      // Purity: the source deck is untouched.
      expect(deck.slides.map((s) => s.id), [a.id, c.id]);
    });

    test('InsertSlide accepts the end index but rejects beyond it', () {
      final deck = deckOf([slideA()]);
      final b = slideB();
      final atEnd = applyOp(
        deck,
        InsertSlide(version: 1, authorId: author, index: 1, slide: b),
      );
      expect(atEnd.slides.last.id, b.id);
      expect(
        () => applyOp(
          deck,
          InsertSlide(version: 1, authorId: author, index: 2, slide: b),
        ),
        throwsArgumentError,
      );
      expect(
        () => applyOp(
          deck,
          InsertSlide(version: 1, authorId: author, index: -1, slide: b),
        ),
        throwsArgumentError,
      );
    });

    test('RemoveSlide drops the addressed slide; unknown id throws', () {
      final a = slideA(), b = slideB();
      final deck = deckOf([a, b]);
      final result = applyOp(
        deck,
        RemoveSlide(version: 1, authorId: author, slideId: a.id),
      );
      expect(result.slides.map((s) => s.id), [b.id]);
      expect(
        () => applyOp(
          deck,
          RemoveSlide(version: 1, authorId: author, slideId: 'nope'),
        ),
        throwsArgumentError,
      );
    });

    test('ReorderSlide moves a slide to the new index', () {
      final a = slideA(), b = slideB(), c = slideC();
      final deck = deckOf([a, b, c]);
      final result = applyOp(
        deck,
        ReorderSlide(version: 1, authorId: author, slideId: a.id, newIndex: 2),
      );
      expect(result.slides.map((s) => s.id), [b.id, c.id, a.id]);
    });

    test('ReorderSlide rejects an out-of-range index and an unknown id', () {
      final a = slideA(), b = slideB();
      final deck = deckOf([a, b]);
      expect(
        () => applyOp(
          deck,
          ReorderSlide(
            version: 1,
            authorId: author,
            slideId: a.id,
            newIndex: 2,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => applyOp(
          deck,
          ReorderSlide(
            version: 1,
            authorId: author,
            slideId: 'nope',
            newIndex: 0,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('applyOp — SetSlideField', () {
    test('the case table covers every SlideField (completeness)', () {
      expect(_slideCases.keys.toSet(), SlideField.values.toSet());
    });

    for (final entry in _slideCases.entries) {
      final field = entry.key;
      final value = entry.value.value;
      final read = entry.value.read;
      test('sets ${field.name} and leaves the value readable', () {
        final a = slideA();
        final deck = deckOf([a]);
        // The value is genuinely different from the default, so a wrong-field
        // mapping would leave the target unchanged and fail here.
        expect(
          read(a),
          isNot(value),
          reason:
              '${field.name} test value is a '
              'no-op against the default; pick a distinctive value',
        );
        final result = applyOp(
          deck,
          SetSlideField(
            version: 1,
            authorId: author,
            slideId: a.id,
            field: field,
            value: value,
          ),
        );
        expect(read(result.slides.single), value);
      });
    }

    test('a value of the wrong type fails closed', () {
      final a = slideA();
      final deck = deckOf([a]);
      expect(
        () => applyOp(
          deck,
          SetSlideField(
            version: 1,
            authorId: author,
            slideId: a.id,
            field: SlideField.title, // expects String
            value: 42,
          ),
        ),
        throwsArgumentError,
      );
      // A List whose elements are the wrong type is rejected too.
      expect(
        () => applyOp(
          deck,
          SetSlideField(
            version: 1,
            authorId: author,
            slideId: a.id,
            field: SlideField.bullets, // expects List<String>
            value: [1, 2],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('an unknown slide id fails closed', () {
      final deck = deckOf([slideA()]);
      expect(
        () => applyOp(
          deck,
          SetSlideField(
            version: 1,
            authorId: author,
            slideId: 'nope',
            field: SlideField.title,
            value: 'x',
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('applyOp — SetDeckMeta', () {
    test('the case table covers every DeckMetaField (completeness)', () {
      expect(_deckCases.keys.toSet(), DeckMetaField.values.toSet());
    });

    for (final entry in _deckCases.entries) {
      final field = entry.key;
      final value = entry.value.value;
      final read = entry.value.read;
      test('sets ${field.name}', () {
        final deck = deckOf([slideA()]);
        expect(
          read(deck),
          isNot(value),
          reason:
              '${field.name} test value is '
              'a no-op against the default',
        );
        final result = applyOp(
          deck,
          SetDeckMeta(version: 1, authorId: author, field: field, value: value),
        );
        expect(read(result), value);
      });
    }

    test('a value of the wrong type fails closed', () {
      final deck = deckOf([slideA()]);
      expect(
        () => applyOp(
          deck,
          SetDeckMeta(
            version: 1,
            authorId: author,
            field: DeckMetaField.paginate, // expects bool
            value: 'yes',
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  test('a version-ordered sequence reproduces the intended deck', () {
    final a = slideA(), b = slideB();
    var deck = deckOf([a]);
    final ops = <DeckOp>[
      InsertSlide(version: 1, authorId: author, index: 1, slide: b),
      SetSlideField(
        version: 2,
        authorId: author,
        slideId: b.id,
        field: SlideField.title,
        value: 'renamed B',
      ),
      SetDeckMeta(
        version: 3,
        authorId: author,
        field: DeckMetaField.title,
        value: 'final',
      ),
      ReorderSlide(version: 4, authorId: author, slideId: b.id, newIndex: 0),
    ];
    for (final op in ops) {
      deck = applyOp(deck, op);
    }
    expect(deck.title, 'final');
    expect(deck.slides.map((s) => s.id), [b.id, a.id]);
    expect(deck.slides.firstWhere((s) => s.id == b.id).title, 'renamed B');
  });

  test('a DeckOp carries its version and author', () {
    const op = RemoveSlide(version: 7, authorId: 'u:x', slideId: 's');
    expect(op.version, 7);
    expect(op.authorId, 'u:x');
  });
}
