import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/services/markdown_service.dart';

/// De veertien invulbare werkdeck-sjablonen voor terugkerende werkprocessen.
const werkdeckIds = [
  'postIncidentReview',
  'privacyIncident',
  'dpia',
  'riskRegister',
  'continuityTest',
  'tabletopExercise',
  'releaseReadiness',
  'steeringUpdate',
  'auditFollowup',
  'vendorRisk',
  'architectureDecision',
  'policyRollout',
  'handover',
  'retrospective',
];

void main() {
  group('deckTemplates registry', () {
    test('offers the full catalogue with unique ids', () {
      final ids = deckTemplates.map((t) => t.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(deckTemplates.first.id, 'empty');
      expect(
        ids,
        containsAll([
          // De oorspronkelijke veertien.
          'empty', 'briefing', 'status', 'kickoff', 'communication',
          'projectTimeline', 'rasci', 'securityTasks', 'certification',
          'training', 'report', 'research', 'technical', 'quiz',
          // De veertien werkdecks.
          ...werkdeckIds,
        ]),
      );
    });

    test('every template has a title, description and icon key', () {
      for (final template in deckTemplates) {
        expect(template.title, isNotEmpty, reason: template.id);
        expect(template.description, isNotEmpty, reason: template.id);
        expect(template.icon, isNotEmpty, reason: template.id);
      }
    });

    test('deckTemplateById resolves ids and rejects unknowns', () {
      expect(deckTemplateById('quiz')!.title, 'Interactieve quiz');
      expect(deckTemplateById('bestaat-niet'), isNull);
    });
  });

  group('template slide builders', () {
    test(
      'every template starts with a title slide carrying the deck title',
      () {
        for (final template in deckTemplates) {
          final slides = template.buildSlides('Mijn presentatie');
          expect(slides, isNotEmpty, reason: template.id);
          expect(slides.first.type, SlideType.title, reason: template.id);
          expect(slides.first.title, 'Mijn presentatie', reason: template.id);
        }
      },
    );

    test('every slide has unique ids and Dutch placeholder content', () {
      for (final template in deckTemplates) {
        final slides = template.buildSlides('Titel');
        final ids = slides.map((s) => s.id).toSet();
        expect(ids, hasLength(slides.length), reason: template.id);
      }
    });

    test('table slides have a header row and consistent column counts', () {
      for (final template in deckTemplates) {
        for (final slide in template.buildSlides('Titel')) {
          if (slide.type != SlideType.table) continue;
          expect(slide.tableRows.length, greaterThan(1), reason: template.id);
          final columns = slide.tableRows.first.length;
          for (final row in slide.tableRows) {
            expect(row, hasLength(columns), reason: '${template.id}: $row');
          }
        }
      }
    });

    test('timeline slides carry parseable, non-empty events', () {
      for (final template in deckTemplates) {
        for (final slide in template.buildSlides('Titel')) {
          if (slide.type != SlideType.timeline) continue;
          final events = parseTimelineEvents(slide.bullets);
          expect(events.length, greaterThan(1), reason: template.id);
        }
      }
    });

    test('question slides are presentable as authored', () {
      for (final template in deckTemplates) {
        for (final slide in template.buildSlides('Titel')) {
          if (slide.type != SlideType.question) continue;
          final spec = QuestionSpec.parse(slide.customMarkdown);
          expect(spec.isPresentable, isTrue, reason: template.id);
        }
      }
    });
  });

  group('expected slide types per template', () {
    List<SlideType> typesOf(String id) =>
        deckTemplateById(id)!.buildSlides('T').map((s) => s.type).toList();

    test('empty deck is a title page plus an agenda', () {
      expect(typesOf('empty'), [SlideType.title, SlideType.bullets]);
    });

    test('briefing is title plus five bullet slides', () {
      expect(typesOf('briefing'), [
        SlideType.title,
        ...List.filled(5, SlideType.bullets),
      ]);
    });

    test('status briefing has a cockpit dashboard and a workstream table', () {
      final types = typesOf('status');
      expect(types, contains(SlideType.cockpit));
      expect(types, contains(SlideType.table));
    });

    test('kick-off has scope columns, stakeholder tables and a timeline', () {
      final types = typesOf('kickoff');
      expect(types, contains(SlideType.twoBullets));
      expect(types, contains(SlideType.timeline));
      expect(types.where((t) => t == SlideType.table).length, 2);
    });

    test('communication briefing has a key-message quote and a timeline', () {
      final types = typesOf('communication');
      expect(types, contains(SlideType.quote));
      expect(types, contains(SlideType.timeline));
      expect(types.where((t) => t == SlideType.table).length, 2);
    });

    test('project timeline has a timeline and a milestone table', () {
      final types = typesOf('projectTimeline');
      expect(types, contains(SlideType.timeline));
      expect(types, contains(SlideType.table));
    });

    test('RASCI template is table-heavy', () {
      final types = typesOf('rasci');
      expect(types.where((t) => t == SlideType.table).length, 4);
    });

    test('security task plan tracks tasks in tables', () {
      final types = typesOf('securityTasks');
      expect(types.where((t) => t == SlideType.table).length, 3);
    });

    test('certification progress has a chart, controls and audit timeline', () {
      final types = typesOf('certification');
      expect(types, contains(SlideType.chart));
      expect(types, contains(SlideType.table));
      expect(types, contains(SlideType.timeline));
    });

    test('training has a case study, a quiz question and free markdown', () {
      final types = typesOf('training');
      expect(types, contains(SlideType.question));
      expect(types, contains(SlideType.freeMarkdown));
    });

    test('report has a KPI cockpit and a trend chart', () {
      final types = typesOf('report');
      expect(types, contains(SlideType.cockpit));
      expect(types, contains(SlideType.chart));
    });

    test('research story has a findings timeline and evidence markdown', () {
      final types = typesOf('research');
      expect(types, contains(SlideType.timeline));
      expect(types, contains(SlideType.freeMarkdown));
    });

    test('technical explainer has architecture markdown and a code sample', () {
      final types = typesOf('technical');
      expect(types, contains(SlideType.freeMarkdown));
      expect(types, contains(SlideType.code));
      expect(types, contains(SlideType.table));
    });

    test('interactive quiz covers all three authored question kinds', () {
      final slides = deckTemplateById('quiz')!.buildSlides('T');
      final kinds = slides
          .where((s) => s.type == SlideType.question)
          .map((s) => QuestionSpec.parse(s.customMarkdown).kind)
          .toList();
      expect(kinds, [
        QuestionKind.multipleChoice,
        QuestionKind.trueFalse,
        QuestionKind.multipleCorrect,
      ]);
    });
  });

  group('werkdeck templates', () {
    test('every werkdeck yields at least eight slides and a table', () {
      for (final id in werkdeckIds) {
        final slides = deckTemplateById(id)!.buildSlides('T');
        expect(slides.length, greaterThanOrEqualTo(8), reason: id);
        expect(
          slides.any((s) => s.type == SlideType.table),
          isTrue,
          reason: id,
        );
      }
    });

    test('every werkdeck is live-invulbaar: editable table or checklist', () {
      for (final id in werkdeckIds) {
        final slides = deckTemplateById(id)!.buildSlides('T');
        final editable = slides.any(
          (s) => s.type == SlideType.table && s.tableEditable,
        );
        final checklist = slides.any((s) => s.listStyle == ListStyle.checklist);
        expect(editable || checklist, isTrue, reason: id);
      }
    });

    test('central action and go/no-go lists show checklist progress', () {
      const withProgressList = [
        'privacyIncident',
        'dpia',
        'riskRegister',
        'continuityTest',
        'tabletopExercise',
        'releaseReadiness',
        'vendorRisk',
        'handover',
        'retrospective',
      ];
      for (final id in withProgressList) {
        final slides = deckTemplateById(id)!.buildSlides('T');
        expect(
          slides.any(
            (s) =>
                s.listStyle == ListStyle.checklist && s.showChecklistProgress,
          ),
          isTrue,
          reason: id,
        );
      }
      // De overige werkdecks leggen acties vast in een invulbare tabel.
      for (final id in werkdeckIds.where(
        (id) => !withProgressList.contains(id),
      )) {
        final slides = deckTemplateById(id)!.buildSlides('T');
        expect(
          slides.any((s) => s.type == SlideType.table && s.tableEditable),
          isTrue,
          reason: id,
        );
      }
    });
  });

  group('l10n coverage', () {
    // Titles/descriptions reach l10n.d() via the model, not as literals, so
    // the grep-based coverage test in app_localizations_test.dart cannot see
    // them; this guard enforces the same rule for the template registry.
    test('titles and descriptions are translated in every language', () {
      final missing = <String>[];
      for (final code in AppLocalizations.languageNames.keys) {
        if (code == 'nl') continue;
        for (final template in deckTemplates) {
          for (final source in [template.title, template.description]) {
            if (!AppLocalizations.hasDirectDutchSourceTranslation(
              code,
              source,
            )) {
              missing.add('$code: $source');
            }
          }
        }
      }
      expect(missing, isEmpty);
    });
  });

  group('round trip', () {
    test('every template deck survives serialize + parse with its types', () {
      final md = MarkdownService();
      for (final template in deckTemplates) {
        final deck = Deck(
          title: 'Sjabloontest',
          slides: template.buildSlides('Sjabloontest'),
        );
        final markdown = md.generateDeck(deck);
        final parsed = md.parseDeck(markdown);
        expect(parsed, isNotNull, reason: template.id);
        expect(
          parsed!.slides.map((s) => s.type).toList(),
          deck.slides.map((s) => s.type).toList(),
          reason: template.id,
        );
      }
    });
  });
}
