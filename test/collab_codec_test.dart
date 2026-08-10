import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_codec.dart';
import 'package:ocideck/collab/collab_transport.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/quality_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';

/// A slide with every field set to a non-default value, so a round-trip that
/// drops any field fails a concrete assertion below.
Slide maximalSlide() => Slide(
  id: 'slide-xyz',
  type: SlideType.table,
  title: 'Title',
  subtitle: 'Subtitle',
  bullets: const ['a', 'b'],
  bullets2: const ['c'],
  listStyle: ListStyle.numbered,
  showChecklistProgress: true,
  continueNumbering: true,
  continuesSplit: true,
  columnTitle1: 'C1',
  columnTitle2: 'C2',
  imagePath: 'img1.png',
  imagePath2: 'img2.png',
  imageCaption: 'cap1',
  imageCaption2: 'cap2',
  imageAltText: 'alt1',
  imageAltText2: 'alt2',
  imageFocalX: 0.1,
  imageFocalY: 0.2,
  imageFocalX2: 0.3,
  imageFocalY2: 0.4,
  videoPath: 'clip.mp4',
  videoAutoplay: true,
  videoStartMs: 100,
  videoEndMs: 200,
  audioPath: 'sound.mp3',
  audioAutoplay: true,
  mediaRedacted: true,
  contentRedacted: true,
  quote: 'Q',
  quoteAuthor: 'QA',
  customMarkdown: '# body',
  codeLanguage: 'dart',
  cssClass: 'fancy',
  notes: 'speaker notes',
  preservedMarpLines: const ['<!-- _unknown: keep -->'],
  marpStyle: const MarpStyle(
    color: '#123456',
    backgroundColor: '#abcdef',
    backgroundImage: "url('background.png')",
    header: '**Header**',
    footer: 'Footer',
    imageFit: 'contain',
    imageFilters: ['blur:2px'],
    headingFit: true,
  ),
  advanceDuration: 3.5,
  imageSize: 42,
  titleImageOverlay: false,
  imageTitleAbove: true,
  titleTextColorOverride: '#FFFFFF',
  titleColumnLayout: TitleColumnLayout.both,
  titleColumnWidth: 30,
  bulletMarkerOverride: BulletMarker.paw,
  showLogo: false,
  showFooter: false,
  skipped: true,
  tlp: TlpLevel.amber,
  privacy: PrivacyDisposition.shield,
  quality: QualityDisposition.accept,
  tableRows: const [
    ['h1', 'h2'],
    ['a', 'b'],
  ],
  tableEditable: true,
  tableMarkOverdue: true,
  viewLimit: const DisplayWindowSpec(
    limit: 5,
    mode: DisplayWindowMode.top,
    key: 'col',
    remainder: DisplayWindowRemainder.other,
    showCount: false,
  ),
  isDetail: true,
  timelineLayout: TimelineLayout.horizontal,
  timelineReveal: TimelineReveal.steps,
  timelineAnimationMs: 800,
  timelineCurrentIndex: 2,
  findingId: 'F-01',
  findingRole: FindingRole.evidence,
  aiAssistedFields: const ['title', 'notes'],
  checklistScope: 'https://app.example/login',
  improvementTemplateId: 'fmea',
  improvementLayout: 'fishbone',
  renderPage: 3,
);

void main() {
  group('slide (de)serialiser', () {
    test('a maximally-populated slide round-trips field for field', () {
      final s = maximalSlide();
      final r = slideFromJson(slideToJson(s));

      expect(r.id, s.id);
      expect(r.type, s.type);
      expect(r.title, s.title);
      expect(r.subtitle, s.subtitle);
      expect(r.bullets, s.bullets);
      expect(r.bullets2, s.bullets2);
      expect(r.listStyle, s.listStyle);
      expect(r.showChecklistProgress, s.showChecklistProgress);
      expect(r.continueNumbering, s.continueNumbering);
      expect(r.continuesSplit, s.continuesSplit);
      expect(r.columnTitle1, s.columnTitle1);
      expect(r.columnTitle2, s.columnTitle2);
      expect(r.imagePath, s.imagePath);
      expect(r.imagePath2, s.imagePath2);
      expect(r.imageCaption, s.imageCaption);
      expect(r.imageCaption2, s.imageCaption2);
      expect(r.imageAltText, s.imageAltText);
      expect(r.imageAltText2, s.imageAltText2);
      expect(r.imageFocalX, s.imageFocalX);
      expect(r.imageFocalY, s.imageFocalY);
      expect(r.imageFocalX2, s.imageFocalX2);
      expect(r.imageFocalY2, s.imageFocalY2);
      expect(r.videoPath, s.videoPath);
      expect(r.videoAutoplay, s.videoAutoplay);
      expect(r.videoStartMs, s.videoStartMs);
      expect(r.videoEndMs, s.videoEndMs);
      expect(r.audioPath, s.audioPath);
      expect(r.audioAutoplay, s.audioAutoplay);
      expect(r.mediaRedacted, s.mediaRedacted);
      expect(r.contentRedacted, s.contentRedacted);
      expect(r.quote, s.quote);
      expect(r.quoteAuthor, s.quoteAuthor);
      expect(r.customMarkdown, s.customMarkdown);
      expect(r.codeLanguage, s.codeLanguage);
      expect(r.cssClass, s.cssClass);
      expect(r.notes, s.notes);
      expect(r.preservedMarpLines, s.preservedMarpLines);
      expect(r.marpStyle, s.marpStyle);
      expect(r.advanceDuration, s.advanceDuration);
      expect(r.imageSize, s.imageSize);
      expect(r.titleImageOverlay, s.titleImageOverlay);
      expect(r.imageTitleAbove, s.imageTitleAbove);
      expect(r.titleTextColorOverride, s.titleTextColorOverride);
      expect(r.titleColumnLayout, s.titleColumnLayout);
      expect(r.titleColumnWidth, s.titleColumnWidth);
      expect(r.bulletMarkerOverride, s.bulletMarkerOverride);
      expect(r.showLogo, s.showLogo);
      expect(r.showFooter, s.showFooter);
      expect(r.skipped, s.skipped);
      expect(r.tlp, s.tlp);
      expect(r.privacy, s.privacy);
      expect(r.quality, s.quality);
      expect(r.tableRows, s.tableRows);
      expect(r.tableEditable, s.tableEditable);
      expect(r.tableMarkOverdue, s.tableMarkOverdue);
      expect(r.viewLimit?.limit, s.viewLimit?.limit);
      expect(r.viewLimit?.mode, s.viewLimit?.mode);
      expect(r.viewLimit?.key, s.viewLimit?.key);
      expect(r.viewLimit?.remainder, s.viewLimit?.remainder);
      expect(r.viewLimit?.showCount, s.viewLimit?.showCount);
      expect(r.isDetail, s.isDetail);
      expect(r.timelineLayout, s.timelineLayout);
      expect(r.timelineReveal, s.timelineReveal);
      expect(r.timelineAnimationMs, s.timelineAnimationMs);
      expect(r.timelineCurrentIndex, s.timelineCurrentIndex);
      expect(r.findingId, s.findingId);
      expect(r.findingRole, s.findingRole);
      expect(r.aiAssistedFields, s.aiAssistedFields);
      expect(r.checklistScope, s.checklistScope);
      expect(r.improvementTemplateId, s.improvementTemplateId);
      expect(r.improvementLayout, s.improvementLayout);
      expect(r.renderPage, s.renderPage);
    });

    test('nullable slide fields at their defaults round-trip as null', () {
      final s = Slide.create(SlideType.bullets);
      final r = slideFromJson(slideToJson(s));
      expect(r.bulletMarkerOverride, isNull);
      expect(r.privacy, isNull);
      expect(r.viewLimit, isNull);
      expect(r.timelineAnimationMs, isNull);
      expect(r.timelineCurrentIndex, isNull);
    });
  });

  group('deck op (de)serialiser', () {
    test('every op type round-trips through the JSON string form', () {
      final ops = <DeckOp>[
        InsertSlide(
          version: 4,
          authorId: 'p1',
          index: 2,
          slide: maximalSlide(),
        ),
        const RemoveSlide(version: 5, authorId: 'p2', slideId: 'slide-xyz'),
        const ReorderSlide(
          version: 6,
          authorId: 'p1',
          slideId: 'slide-xyz',
          newIndex: 0,
        ),
        const SetSlideField(
          version: 7,
          authorId: 'p2',
          slideId: 'slide-xyz',
          field: SlideField.title,
          value: 'New title',
        ),
        const SetDeckMeta(
          version: 8,
          authorId: 'p1',
          field: DeckMetaField.tlp,
          value: TlpLevel.red,
        ),
      ];
      for (final op in ops) {
        final r = decodeDeckOp(encodeDeckOp(op));
        expect(r.runtimeType, op.runtimeType);
        expect(r.version, op.version);
        expect(r.authorId, op.authorId);
      }
    });

    test('InsertSlide carries the whole slide through the wire', () {
      final op = InsertSlide(
        version: 1,
        authorId: 'p1',
        index: 0,
        slide: maximalSlide(),
      );
      final r = decodeDeckOp(encodeDeckOp(op)) as InsertSlide;
      expect(r.index, 0);
      expect(r.slide.id, 'slide-xyz');
      expect(r.slide.tableRows, op.slide.tableRows);
      expect(r.slide.privacy, PrivacyDisposition.shield);
    });

    test('typed values survive by field kind', () {
      // one representative per value kind
      final cases = <SetSlideField>[
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.skipped,
          value: true,
        ),
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.imageSize,
          value: 30,
        ),
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.imageFocalX,
          value: 0.25,
        ),
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.bullets,
          value: ['x', 'y'],
        ),
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.type,
          value: SlideType.image,
        ),
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.listStyle,
          value: ListStyle.checklist,
        ),
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.tlp,
          value: TlpLevel.green,
        ),
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.preservedMarpLines,
          value: ['<!-- _unknown: keep -->'],
        ),
        const SetSlideField(
          version: 1,
          authorId: 'p',
          slideId: 's',
          field: SlideField.marpStyle,
          value: MarpStyle(color: '#123456', headingFit: true),
        ),
      ];
      for (final op in cases) {
        final r = decodeDeckOp(encodeDeckOp(op)) as SetSlideField;
        expect(r.field, op.field);
        expect(r.value, op.value);
      }
    });

    test('SetDeckMeta privacy enum survives', () {
      const op = SetDeckMeta(
        version: 1,
        authorId: 'p',
        field: DeckMetaField.privacy,
        value: PrivacyDisposition.redact,
      );
      final r = decodeDeckOp(encodeDeckOp(op)) as SetDeckMeta;
      expect(r.value, PrivacyDisposition.redact);
    });

    test('SetDeckMeta Marp style survives', () {
      const op = SetDeckMeta(
        version: 1,
        authorId: 'p',
        field: DeckMetaField.marpStyle,
        value: MarpStyle(header: '**Header**', footer: 'Footer'),
      );
      final r = decodeDeckOp(encodeDeckOp(op)) as SetDeckMeta;
      expect(r.value, op.value);
    });

    test('a decoded op applies to a deck exactly like the original', () {
      final deck = Deck(
        title: 'd',
        slides: [const Slide(id: 's1', type: SlideType.bullets, title: 'x')],
      );
      const op = SetSlideField(
        version: 1,
        authorId: 'p',
        slideId: 's1',
        field: SlideField.title,
        value: 'edited',
      );
      final viaWire = applyOp(deck, decodeDeckOp(encodeDeckOp(op)));
      expect(viaWire.slides.single.title, 'edited');
    });
  });

  group('lock event (de)serialiser', () {
    test('round-trips including the forced flag', () {
      const e = LockEvent(
        slideId: 's3',
        held: true,
        participantId: 'p9',
        forced: true,
      );
      final r = decodeLockEvent(encodeLockEvent(e));
      expect(r.slideId, e.slideId);
      expect(r.held, e.held);
      expect(r.participantId, e.participantId);
      expect(r.forced, e.forced);
    });
  });

  group('completeness of the field→kind maps', () {
    test('every SlideField has a wire kind', () {
      expect(mappedSlideFields, containsAll(SlideField.values));
    });
    test('every DeckMetaField has a wire kind', () {
      expect(mappedDeckMetaFields, containsAll(DeckMetaField.values));
    });
  });

  group('fail-closed decoding', () {
    test('non-JSON input throws FormatException', () {
      expect(() => decodeDeckOp('not json {'), throwsFormatException);
    });
    test('a JSON array (not an object) throws', () {
      expect(() => decodeDeckOp('[1,2,3]'), throwsFormatException);
    });
    test('an unknown op discriminator throws', () {
      expect(
        () => decodeDeckOp('{"op":"teleport","version":1,"authorId":"p"}'),
        throwsFormatException,
      );
    });
    test('an unknown enum name throws rather than defaulting', () {
      expect(
        () => decodeDeckOp(
          '{"op":"setDeckMeta","version":1,"authorId":"p",'
          '"field":"tlp","value":"chartreuse"}',
        ),
        throwsFormatException,
      );
    });
    test('a wrong value type throws', () {
      expect(
        () => decodeDeckOp(
          '{"op":"setSlideField","version":1,"authorId":"p",'
          '"slideId":"s","field":"skipped","value":"yes"}',
        ),
        throwsFormatException,
      );
    });
    test('a missing required field throws', () {
      expect(
        () => decodeDeckOp('{"op":"removeSlide","version":1,"authorId":"p"}'),
        throwsFormatException,
      );
    });
  });
}
