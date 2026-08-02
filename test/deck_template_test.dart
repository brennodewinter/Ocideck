import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/scorecard_spec.dart';
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

/// De vijf projectvormen en het kader dat het nieuwe deck in de frontmatter
/// moet meekrijgen. SIPOC is een los hulpmiddel en heeft daarom geen kader.
const improvementProjectFrameworks = {
  'procesverbetering-dmaic': 'dmaic',
  'procesverbetering-dmadv': 'dmadv',
  'procesverbetering-kaizen': 'kaizen',
  'procesverbetering-a3': 'a3',
  'procesverbetering-8d': '8d',
};

const improvementTemplateIds = [
  'procesverbetering-dmaic',
  'procesverbetering-dmadv',
  'procesverbetering-kaizen',
  'procesverbetering-a3',
  'procesverbetering-8d',
  'procesverbetering-sipoc',
];

/// De inhoudstalen van de sjabloondocumenten. Klingon valt voorlopig terug op
/// Engels totdat de inhoud betrouwbaar door een mens is vertaald.
final contentLanguages = AppLocalizations.supportedLocales
    .map((locale) => locale.languageCode)
    .where((languageCode) => languageCode != 'tlh')
    .toList(growable: false);

final _deckCache = <String, Deck>{};

/// The parsed template document for [id] in [language], read straight from
/// `assets/templates/` — tests guard the shipped documents, not a builder.
Deck deckOf(String id, {String language = 'nl'}) =>
    _deckCache.putIfAbsent('$id.$language', () {
      final file = File('assets/templates/$id.$language.md');
      final deck = MarkdownService().parseDeck(file.readAsStringSync());
      expect(deck, isNotNull, reason: file.path);
      return deck!;
    });

List<Slide> slidesOf(String id, {String language = 'nl'}) =>
    deckOf(id, language: language).slides;

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
          // De veertien werkdecks plus de twee sessiedecks.
          ...werkdeckIds,
          'bobCrisis', 'pplFlightPrep',
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

    test('module visibility follows the template requirement', () {
      final ordinary = deckTemplateById('briefing')!;
      final security = deckTemplateById('miauwReport')!;

      bool visible(
        DeckTemplate template, {
        bool sec = false,
        bool imp = false,
      }) => deckTemplateVisible(
        template,
        infoSafetyRevealed: sec,
        procesverbeteringRevealed: imp,
      );

      expect(visible(ordinary), isTrue);
      expect(visible(security), isFalse);
      expect(visible(security, sec: true), isTrue);
      for (final id in improvementTemplateIds) {
        final improvement = deckTemplateById(id)!;
        expect(visible(improvement), isFalse, reason: id);
        expect(visible(improvement, imp: true), isTrue, reason: id);
      }
    });

    test('every improvement project declares its framework', () {
      for (final entry in improvementProjectFrameworks.entries) {
        final template = deckTemplateById(entry.key);
        expect(template, isNotNull, reason: entry.key);
        expect(template!.requiresProcesverbetering, isTrue, reason: entry.key);
        expect(template.improvementFramework, entry.value, reason: entry.key);
      }
      expect(
        deckTemplateById('procesverbetering-sipoc')!.improvementFramework,
        isEmpty,
      );
    });
  });

  group('template documents', () {
    test('every template ships a document in every content language', () {
      for (final template in deckTemplates) {
        for (final language in contentLanguages) {
          final file = File('assets/templates/${template.id}.$language.md');
          expect(file.existsSync(), isTrue, reason: file.path);
        }
      }
    });

    test('no stray documents without a registered template', () {
      final known = deckTemplates.map((t) => t.id).toSet();
      final files = Directory('assets/templates')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      for (final name in files) {
        final match = RegExp(r'^(.+)\.([a-z]{2,3})\.md$').firstMatch(name);
        expect(match, isNotNull, reason: name);
        expect(known, contains(match!.group(1)), reason: name);
      }
    });

    test('every document parses, starts with a title slide, unique ids', () {
      for (final template in deckTemplates) {
        for (final language in contentLanguages) {
          final slides = slidesOf(template.id, language: language);
          final label = '${template.id}.$language';
          expect(slides, isNotEmpty, reason: label);
          expect(slides.first.type, SlideType.title, reason: label);
          expect(slides.first.title, isNotEmpty, reason: label);
          final ids = slides.map((s) => s.id).toSet();
          expect(ids, hasLength(slides.length), reason: label);
          expect(deckOf(template.id, language: language).language, language);
        }
      }
    });

    test('table slides have a header row and consistent column counts', () {
      for (final template in deckTemplates) {
        for (final language in contentLanguages) {
          for (final slide in slidesOf(template.id, language: language)) {
            if (slide.tableRows.isEmpty) continue;
            expect(slide.tableRows.length, greaterThan(1), reason: template.id);
            final columns = slide.tableRows.first.length;
            for (final row in slide.tableRows) {
              expect(row, hasLength(columns), reason: '${template.id}: $row');
            }
          }
        }
      }
    });

    test('timeline slides carry parseable, non-empty events', () {
      for (final template in deckTemplates) {
        for (final language in contentLanguages) {
          for (final slide in slidesOf(template.id, language: language)) {
            if (slide.type != SlideType.timeline) continue;
            final events = parseTimelineEvents(slide.bullets);
            expect(events.length, greaterThan(1), reason: template.id);
          }
        }
      }
    });

    test('question slides are presentable as authored', () {
      for (final template in deckTemplates) {
        for (final language in contentLanguages) {
          for (final slide in slidesOf(template.id, language: language)) {
            if (slide.type != SlideType.question) continue;
            final spec = QuestionSpec.parse(slide.customMarkdown);
            expect(spec.isPresentable, isTrue, reason: template.id);
          }
        }
      }
    });
  });

  group('nl/en parity', () {
    // De Engelse variant is een vertaling van het Nederlandse document, geen
    // eigen sjabloon: zelfde slidetypes, zelfde invulbaarheid, zelfde maten.
    test('both languages carry the same structure per template', () {
      for (final template in deckTemplates) {
        final nl = slidesOf(template.id);
        final en = slidesOf(template.id, language: 'en');
        final label = template.id;
        expect(
          en.map((s) => s.type).toList(),
          nl.map((s) => s.type).toList(),
          reason: label,
        );
        for (var i = 0; i < nl.length; i++) {
          final where = '$label slide ${i + 1}';
          expect(en[i].tableEditable, nl[i].tableEditable, reason: where);
          expect(en[i].skipped, nl[i].skipped, reason: where);
          expect(en[i].listStyle, nl[i].listStyle, reason: where);
          expect(
            en[i].showChecklistProgress,
            nl[i].showChecklistProgress,
            reason: where,
          );
          expect(en[i].bullets.length, nl[i].bullets.length, reason: where);
          expect(en[i].tableRows.length, nl[i].tableRows.length, reason: where);
          if (nl[i].tableRows.isNotEmpty) {
            expect(
              en[i].tableRows.first.length,
              nl[i].tableRows.first.length,
              reason: where,
            );
          }
        }
      }
    });
  });

  group('expected slide types per template', () {
    List<SlideType> typesOf(String id) =>
        slidesOf(id).map((s) => s.type).toList();

    test('empty deck is a title page and nothing else', () {
      // Het was een titeldia plús een agenda met Nederlandse voorbeeldregels.
      // Voor een sjabloon is dat verdedigbaar — de dialoog waarschuwt ervoor —
      // maar dit is het lege deck: de standaardkeuze, niet als sjabloon
      // gepresenteerd, en dus onontkoombaar voor wie de app in het Engels
      // draait (#622).
      for (final language in contentLanguages) {
        expect(slidesOf('empty', language: language).map((s) => s.type), [
          SlideType.title,
        ]);
      }
    });

    test('geen enkel sjabloon draagt de oude agenda-voorbeeldregels', () {
      // Een regressie hier is stil: het deck opent gewoon, alleen staat er
      // Nederlands in een Engelse app.
      for (final template in deckTemplates) {
        for (final language in contentLanguages) {
          for (final slide in slidesOf(template.id, language: language)) {
            expect(
              slide.bullets,
              isNot(contains('Opening en aanleiding')),
              reason: 'sjabloon ${template.id}',
            );
          }
        }
      }
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

    test(
      'report leads with figures-against-last-time, then trend, then asks',
      () {
        final types = typesOf('report');
        // A recurring report leads with what changed, so the KPI slide is a
        // scorecard (figure + the figure it replaces) rather than a cockpit.
        expect(types, contains(SlideType.scorecard));
        expect(types, contains(SlideType.chart));
        // Owner and deadline are columns now, not text in brackets on a bullet.
        // A plain table, not a type of its own: the columns were the whole of
        // what a separate type added.
        expect(types, contains(SlideType.table));
      },
    );

    test('report scorecard shows a rise, a fall and an unchanged figure', () {
      for (final language in contentLanguages) {
        final slide = slidesOf(
          'report',
          language: language,
        ).firstWhere((s) => s.type == SlideType.scorecard);
        final entries = ScorecardSpec.fromSlide(
          slide.title,
          slide.tableRows,
        ).entries;
        // The starting point teaches the type: all three outcomes are visible,
        // so an author sees what the direction setting actually does.
        expect(
          entries.map((e) => e.direction),
          containsAll([
            ScorecardDirection.up,
            ScorecardDirection.down,
            ScorecardDirection.flat,
          ]),
          reason: language,
        );
        // And both verdicts, so the colouring is not a mystery either.
        expect(
          entries.map((e) => e.sentiment),
          containsAll([ScorecardSentiment.good, ScorecardSentiment.bad]),
          reason: language,
        );
      }
    });

    test('report action table matches the editor preset columns', () {
      final slide = slidesOf(
        'report',
      ).firstWhere((s) => s.type == SlideType.table);
      // The same columns the table editor's action-list preset lays down, so a
      // deck started from the template and one started from the preset read
      // alike.
      expect(slide.tableRows.first, [
        'Actie',
        'Eigenaar',
        'Deadline',
        'Status',
      ]);
      expect(slide.tableRows.length, greaterThan(1));
      // Deadlines are left for the meeting to settle; a template with baked-in
      // dates ages.
      for (final row in slide.tableRows.skip(1)) {
        expect(row[2], isEmpty);
      }
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
      for (final language in contentLanguages) {
        final kinds = slidesOf('quiz', language: language)
            .where((s) => s.type == SlideType.question)
            .map((s) => QuestionSpec.parse(s.customMarkdown).kind)
            .toList();
        expect(kinds, [
          QuestionKind.multipleChoice,
          QuestionKind.trueFalse,
          QuestionKind.multipleCorrect,
        ], reason: language);
      }
    });
  });

  group('werkdeck templates', () {
    test('every werkdeck yields at least eight slides and a table', () {
      for (final id in werkdeckIds) {
        final slides = slidesOf(id);
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
        final slides = slidesOf(id);
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
        final slides = slidesOf(id);
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
        final slides = slidesOf(id);
        expect(
          slides.any((s) => s.type == SlideType.table && s.tableEditable),
          isTrue,
          reason: id,
        );
      }
    });
  });

  group('BOB-crisisrapportage', () {
    test('exists and starts with a title slide', () {
      expect(deckTemplateById('bobCrisis')!.title, 'BOB-crisisrapportage');
      expect(slidesOf('bobCrisis').length, greaterThanOrEqualTo(12));
      expect(slidesOf('bobCrisis').first.type, SlideType.title);
    });

    test('has the B/O/B section dividers', () {
      final sections = slidesOf(
        'bobCrisis',
      ).where((s) => s.type == SlideType.section).map((s) => s.title).toList();
      expect(sections, ['Beeldvorming', 'Oordeelsvorming', 'Besluitvorming']);
    });

    test('work tables are live-editable', () {
      final editableTables = slidesOf(
        'bobCrisis',
      ).where((s) => s.type == SlideType.table && s.tableEditable);
      expect(editableTables.length, greaterThanOrEqualTo(2));
    });

    test('the action list is a checklist with progress', () {
      final actionList = slidesOf(
        'bobCrisis',
      ).firstWhere((s) => s.title == 'Actielijst');
      expect(actionList.listStyle, ListStyle.checklist);
      expect(actionList.showChecklistProgress, isTrue);
    });
  });

  group('PPL Vluchtvoorbereiding', () {
    test('exists, is large enough and starts with a title slide', () {
      expect(deckTemplateById('pplFlightPrep'), isNotNull);
      expect(slidesOf('pplFlightPrep').length, greaterThanOrEqualTo(18));
      expect(slidesOf('pplFlightPrep').first.type, SlideType.title);
    });

    test(
      'shows the mandatory-preparation warning visibly in both languages',
      () {
        expect(
          slidesOf('pplFlightPrep').any(
            (s) => s.customMarkdown.contains(
              'vervangt geen verplichte vluchtvoorbereiding',
            ),
          ),
          isTrue,
        );
        expect(
          slidesOf('pplFlightPrep', language: 'en').any(
            (s) => s.customMarkdown.toLowerCase().contains(
              'does not replace mandatory flight preparation',
            ),
          ),
          isTrue,
        );
      },
    );

    test('planning tables are live-editable', () {
      final editableTables = slidesOf(
        'pplFlightPrep',
      ).where((s) => s.type == SlideType.table && s.tableEditable);
      expect(editableTables.length, greaterThanOrEqualTo(5));
    });

    test('has at least three checklists', () {
      final checklists = slidesOf(
        'pplFlightPrep',
      ).where((s) => s.listStyle == ListStyle.checklist);
      expect(checklists.length, greaterThanOrEqualTo(3));
    });

    test('go/no-go and final decision show checklist progress', () {
      for (final title in ['Go / No-Go Samenvatting', 'Laatste Besluit']) {
        final slide = slidesOf(
          'pplFlightPrep',
        ).firstWhere((s) => s.title == title);
        expect(slide.listStyle, ListStyle.checklist, reason: title);
        expect(slide.showChecklistProgress, isTrue, reason: title);
      }
    });
  });

  group('gesprekssjablonen', () {
    // De negen echt lastige gesprekken weven de Crucial Conversations-methode
    // erdoorheen; de zes commerciële/sollicitatiesjablonen gebruiken een
    // scenario-eigen kader.
    const crucialIds = [
      'performanceReview',
      'salaryNegotiation',
      'moreResponsibility',
      'raiseWorkplaceIssue',
      'resolveConflict',
      'giveReceiveFeedback',
      'deliverBadNews',
      'setBoundaries',
      'strainedRelationship',
    ];
    const scenarioIds = [
      'jobInterview',
      'clientConversation',
      'salesConversation',
      'supplierNegotiation',
      'pitch',
      'meetingToGetBuyIn',
    ];
    final conversationIds = [...crucialIds, ...scenarioIds];

    test('all fifteen conversation templates are registered', () {
      final ids = deckTemplates.map((t) => t.id).toSet();
      expect(ids, containsAll(conversationIds));
      expect(conversationIds.toSet(), hasLength(15));
    });

    test(
      'every conversation template is live-invulbaar with a progress list',
      () {
        for (final id in conversationIds) {
          final slides = slidesOf(id);
          expect(
            slides.any((s) => s.type == SlideType.table && s.tableEditable),
            isTrue,
            reason: '$id: editable table',
          );
          expect(
            slides.any(
              (s) =>
                  s.listStyle == ListStyle.checklist && s.showChecklistProgress,
            ),
            isTrue,
            reason: '$id: progress checklist',
          );
        }
      },
    );

    test('crucial conversations carry the Crucial Conversations method', () {
      for (final id in crucialIds) {
        expect(
          slidesOf(id).any(
            (s) =>
                s.type == SlideType.section &&
                s.title == 'De aanpak: een cruciaal gesprek voeren',
          ),
          isTrue,
          reason: id,
        );
      }
    });

    test('scenario conversations do not force the crucial method section', () {
      for (final id in scenarioIds) {
        expect(
          slidesOf(id).any((s) => s.type == SlideType.section),
          isFalse,
          reason: id,
        );
      }
    });
  });

  group('nieuwe rolsjablonen', () {
    // De negentien rolgerichte overdrachts- en veiligheidssjablonen, elk gebouwd
    // op een erkende methode. Ze vallen buiten de werkdeck- en gespreksgroepen,
    // dus deze groep bewaakt hun eigen belofte: substantieel, live-invulbaar, en
    // waar de vorm de methode draagt ook dát.
    const roleTemplateIds = [
      'sbarHandover',
      'mistHandover',
      'mdtMeeting',
      'surgicalChecklist',
      'nursingHandover',
      'onboardingPlan',
      'firstDayInduction',
      'buddyMentor',
      'offboarding',
      'imsafeCheck',
      'crewBriefing',
      'occurrenceReport',
      'toolboxTalk',
      'eventSafety',
      'evacuationDrill',
      'permitToWork',
      'methaneReport',
      'gripEscalation',
      'bridgePassageBriefing',
    ];

    test('all nineteen role templates are registered', () {
      final ids = deckTemplates.map((t) => t.id).toSet();
      expect(ids, containsAll(roleTemplateIds));
      expect(roleTemplateIds.toSet(), hasLength(19));
    });

    test('every role template is substantial and starts with a title', () {
      for (final id in roleTemplateIds) {
        for (final language in contentLanguages) {
          final slides = slidesOf(id, language: language);
          expect(
            slides.length,
            greaterThanOrEqualTo(6),
            reason: '$id.$language',
          );
          expect(slides.first.type, SlideType.title, reason: '$id.$language');
        }
      }
    });

    test('every role template is live-invulbaar: editable table or progress '
        'checklist', () {
      for (final id in roleTemplateIds) {
        final slides = slidesOf(id);
        final editable = slides.any(
          (s) => s.type == SlideType.table && s.tableEditable,
        );
        final progress = slides.any(
          (s) => s.listStyle == ListStyle.checklist && s.showChecklistProgress,
        );
        expect(editable || progress, isTrue, reason: id);
      }
    });

    test('the onboarding plan lays out a 30-60-90 timeline', () {
      for (final language in contentLanguages) {
        expect(
          slidesOf(
            'onboardingPlan',
            language: language,
          ).any((s) => s.type == SlideType.timeline),
          isTrue,
          reason: language,
        );
      }
    });

    test('the WHO surgical check keeps its three sign-in/time-out/sign-out '
        'lists', () {
      for (final language in contentLanguages) {
        final progressLists = slidesOf('surgicalChecklist', language: language)
            .where(
              (s) =>
                  s.listStyle == ListStyle.checklist && s.showChecklistProgress,
            );
        expect(progressLists.length, greaterThanOrEqualTo(3), reason: language);
      }
    });
  });

  group('MIAUW-pentestrapport', () {
    test('is registered as a module-only template', () {
      final template = deckTemplateById('miauwReport')!;
      expect(template.requiresInfoSafety, isTrue);
      expect(template.title, 'MIAUW-pentestrapport');
      expect(slidesOf('miauwReport').first.type, SlideType.title);
    });

    test('has the four MIAUW report parts as section dividers', () {
      final sections = slidesOf(
        'miauwReport',
      ).where((s) => s.type == SlideType.section).map((s) => s.title).toList();
      expect(sections, [
        '1. Algemeen',
        '2. Plan van aanpak',
        '3. Executie',
        '4. Rapportage',
      ]);
    });

    test('scaffolds every module-only slide type in both languages', () {
      for (final language in contentLanguages) {
        final types = slidesOf(
          'miauwReport',
          language: language,
        ).map((s) => s.type).toSet();
        expect(
          types,
          containsAll([
            SlideType.signOff,
            SlideType.scopeMatrix,
            SlideType.findingsSummary,
            SlideType.finding,
            SlideType.checklist,
          ]),
          reason: language,
        );
      }
    });

    test('the example finding is a numberable header with a full spec', () {
      for (final language in contentLanguages) {
        final finding = slidesOf(
          'miauwReport',
          language: language,
        ).singleWhere((s) => s.type == SlideType.finding);
        // Recognised as a finding by the numbering/list services.
        expect(finding.findingRole, FindingRole.header, reason: language);
        final spec = FindingSpec.parse(finding.customMarkdown);
        expect(spec.heading, contains('F-01'), reason: language);
        expect(spec.description, isNotEmpty, reason: language);
        expect(spec.recommendation, isNotEmpty, reason: language);
      }
    });
  });

  group('SIPOC-procesoverzicht', () {
    test('is registered behind the process-improvement module', () {
      final template = deckTemplateById('procesverbetering-sipoc')!;
      expect(template.requiresProcesverbetering, isTrue);
      expect(template.title, 'SIPOC-procesoverzicht');
    });

    test('contains one typed SIPOC matrix in every content language', () {
      for (final language in contentLanguages) {
        final matrix = slidesOf(
          'procesverbetering-sipoc',
          language: language,
        ).singleWhere((slide) => slide.type == SlideType.matrix);
        expect(matrix.improvementTemplateId, 'sipoc', reason: language);
        expect(matrix.tableRows.first, [
          'Supplier',
          'Input',
          'Process',
          'Output',
          'Customer',
        ], reason: language);
        expect(matrix.tableRows.length, inInclusiveRange(5, 8));
      }
    });

    test(
      'puts boundary fields and completion instructions before the matrix',
      () {
        const expectedRows = {
          'nl': [
            ['Afbakening', 'Waarde'],
            ['Proces', ''],
            ['Startpunt', ''],
            ['Eindpunt', ''],
          ],
          'en': [
            ['Boundary', 'Value'],
            ['Process', ''],
            ['Start point', ''],
            ['End point', ''],
          ],
        };
        const instructionTitles = {
          'nl': 'Checklist — Invullen van rechts naar links',
          'en': 'Checklist — Complete from right to left',
        };

        for (final language in expectedRows.keys) {
          final slides = slidesOf(
            'procesverbetering-sipoc',
            language: language,
          );
          final matrixIndex = slides.indexWhere(
            (slide) => slide.type == SlideType.matrix,
          );
          final boundaryIndex = slides.indexWhere(
            (slide) =>
                slide.type == SlideType.table &&
                slide.tableEditable &&
                slide.tableRows.length == 4,
          );
          final instructionIndex = slides.indexWhere(
            (slide) => slide.title == instructionTitles[language],
          );

          expect(matrixIndex, greaterThan(0), reason: language);
          expect(
            boundaryIndex,
            inInclusiveRange(1, matrixIndex - 1),
            reason: language,
          );
          expect(
            instructionIndex,
            inInclusiveRange(boundaryIndex + 1, matrixIndex - 1),
            reason: language,
          );
          expect(
            slides[boundaryIndex].tableRows,
            expectedRows[language],
            reason: language,
          );
          final instruction = slides[instructionIndex];
          expect(instruction.listStyle, ListStyle.numbered, reason: language);
          expect(instruction.bullets, hasLength(6), reason: language);
          expect(
            instruction.bullets.every((step) => step.trim().isNotEmpty),
            isTrue,
            reason: language,
          );
        }
      },
    );

    test('teaches scope, comparison and right-to-left completion', () {
      final slides = slidesOf('procesverbetering-sipoc');
      expect(slides, hasLength(9));
      expect(
        slides.any((slide) => slide.title.contains('gedetailleerde flowchart')),
        isTrue,
      );
      expect(
        slides.any((slide) => slide.title.contains('rechts naar links')),
        isTrue,
      );
    });
  });

  group('procesverbetering invulhulp', () {
    test('every project phase is immediately followed by skipped guidance', () {
      for (final id in improvementProjectFrameworks.keys) {
        for (final language in contentLanguages) {
          final slides = slidesOf(id, language: language);
          final label = '$id.$language';

          expect(slides[1].skipped, isTrue, reason: '$label start guidance');
          expect(slides[1].type, SlideType.bullets, reason: label);
          expect(slides[1].bullets, hasLength(4), reason: label);

          for (var i = 0; i < slides.length; i++) {
            if (slides[i].type != SlideType.section) continue;
            expect(i + 1, lessThan(slides.length), reason: label);
            final guidance = slides[i + 1];
            expect(guidance.skipped, isTrue, reason: '$label after ${i + 1}');
            expect(guidance.type, SlideType.bullets, reason: label);
            expect(guidance.bullets, hasLength(5), reason: label);
            expect(
              guidance.bullets.every((item) => item.trim().isNotEmpty),
              isTrue,
              reason: label,
            );
          }
        }
      }
    });

    test('every project explains SIPOC before the editable matrix', () {
      for (final id in improvementProjectFrameworks.keys) {
        for (final language in contentLanguages) {
          final slides = slidesOf(id, language: language);
          final matrixIndex = slides.indexWhere(
            (slide) => slide.type == SlideType.matrix,
          );
          expect(matrixIndex, greaterThan(0), reason: '$id.$language');
          final guidance = slides[matrixIndex - 1];
          expect(guidance.skipped, isTrue, reason: '$id.$language');
          expect(guidance.type, SlideType.bullets, reason: '$id.$language');
          expect(guidance.bullets, hasLength(5), reason: '$id.$language');
        }
      }
    });

    test(
      'charter and CTQ starters contain prompts rather than empty labels',
      () {
        for (final id in improvementProjectFrameworks.keys) {
          for (final language in contentLanguages) {
            final slides = slidesOf(id, language: language);
            final label = '$id.$language';
            final charter = slides.singleWhere(
              (slide) => slide.improvementTemplateId == 'charter',
            );
            final regions = charter.customMarkdown
                .split(RegExp(r'(?=^## )', multiLine: true))
                .where((region) => region.startsWith('## '));
            expect(regions, isNotEmpty, reason: label);
            for (final region in regions) {
              final lines = region.split('\n');
              expect(
                lines.skip(1).join('\n').trim(),
                isNotEmpty,
                reason: '$label: ${lines.first}',
              );
            }

            final ctq = slides.singleWhere(
              (slide) => slide.improvementTemplateId == 'ctq-tree',
            );
            expect(ctq.bullets, hasLength(3), reason: label);
            expect(
              ctq.bullets.every((item) => item.trim().isNotEmpty),
              isTrue,
              reason: label,
            );
            expect(
              ctq.bullets
                  .skip(1)
                  .any((item) => RegExp(r'^\s*CTQ\s+\d+$').hasMatch(item)),
              isFalse,
              reason: label,
            );
          }
        }
      },
    );

    test('standalone SIPOC keeps guidance out of presentation and export', () {
      for (final language in contentLanguages) {
        final slides = slidesOf('procesverbetering-sipoc', language: language);
        final guidance = slides.where((slide) => slide.skipped).toList();
        expect(guidance, hasLength(4), reason: language);
        expect(guidance.first.type, SlideType.bullets, reason: language);
        expect(
          guidance.any((slide) => slide.type == SlideType.table),
          isTrue,
          reason: language,
        );
        expect(
          guidance.every(
            (slide) => slide.bullets.isNotEmpty || slide.tableRows.length > 1,
          ),
          isTrue,
          reason: language,
        );
        for (final slide in guidance) {
          expect(
            slideReachesAudience(
              slide,
              presentationTlp: TlpLevel.none,
              includeDetail: true,
            ),
            isFalse,
            reason: '$language: ${slide.title}',
          );
        }
      }
    });
  });

  group('uitbreidingssjablonen: besluitvorming, sectoren en gesprekken', () {
    // De negentien sjablonen van de catalogus-uitbreiding: de besluitvormende
    // en financiële as (businesscase, begroting, besluitvormend overleg,
    // sprint review, threat modeling), de sectoren die op nul stonden
    // (publieke sector, onderwijs, vereniging, sociaal domein), de twee
    // generieke gespreksvoorbereidingen naast de scenario-specifieke familie,
    // en de sluitstukken van de luchtvaartketen (debriefing en paxbriefing).
    const uitbreidingIds = [
      'businessCase',
      'budgetPresentation',
      'decisionMeeting',
      'sprintReview',
      'threatModeling',
      'conversationPrep',
      'crucialConversation',
      'familyCareConversation',
      'socialCaseReview',
      'worksCouncilRequest',
      'fireServiceBriefing',
      'afterActionReview',
      'councilProposal',
      'residentsMeeting',
      'parentsEvening',
      'internshipPresentation',
      'membersAssembly',
      'flightDebrief',
      'passengerBriefing',
    ];

    test('all nineteen expansion templates are registered', () {
      final ids = deckTemplates.map((t) => t.id).toSet();
      expect(ids, containsAll(uitbreidingIds));
      expect(uitbreidingIds.toSet(), hasLength(19));
    });

    test('every expansion template is substantial in both languages', () {
      for (final id in uitbreidingIds) {
        for (final language in contentLanguages) {
          expect(
            slidesOf(id, language: language).length,
            greaterThanOrEqualTo(9),
            reason: '$id.$language',
          );
        }
      }
    });

    test('every expansion template is live-invulbaar with a progress list', () {
      for (final id in uitbreidingIds) {
        final slides = slidesOf(id);
        expect(
          slides.any((s) => s.type == SlideType.table && s.tableEditable),
          isTrue,
          reason: '$id: editable table',
        );
        expect(
          slides.any(
            (s) =>
                s.listStyle == ListStyle.checklist && s.showChecklistProgress,
          ),
          isTrue,
          reason: '$id: progress checklist',
        );
      }
    });

    test('the generic crucial conversation carries the family method', () {
      expect(
        slidesOf('crucialConversation').any(
          (s) =>
              s.type == SlideType.section &&
              s.title == 'De aanpak: een cruciaal gesprek voeren',
        ),
        isTrue,
      );
      // De lichte variant blijft licht: geen methodesectie.
      expect(
        slidesOf('conversationPrep').any((s) => s.type == SlideType.section),
        isFalse,
      );
    });

    test('the financial decks lead with figures', () {
      final budget = slidesOf('budgetPresentation').map((s) => s.type).toList();
      expect(budget, contains(SlideType.scorecard));
      expect(budget, contains(SlideType.chart));
      expect(
        slidesOf('sprintReview').any((s) => s.type == SlideType.scorecard),
        isTrue,
      );
    });

    test('proposal and process decks carry a timeline', () {
      const withTimeline = [
        'businessCase',
        'councilProposal',
        'residentsMeeting',
        'worksCouncilRequest',
        'parentsEvening',
        'internshipPresentation',
      ];
      for (final id in withTimeline) {
        expect(
          slidesOf(id).any((s) => s.type == SlideType.timeline),
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

    test('document title slides match the l10n picker title per language', () {
      // Wat de kiezer belooft is wat het document opent: de titeldia van
      // <id>.en.md draagt dezelfde titel als de Engelse l10n van de kiezer.
      for (final template in deckTemplates) {
        expect(slidesOf(template.id).first.title, template.title);
        expect(
          slidesOf(template.id, language: 'en').first.title,
          AppLocalizations.sourceFor('en', template.title),
          reason: template.id,
        );
      }
    });
  });

  group('round trip', () {
    test(
      'every template document survives serialize + parse with its types',
      () {
        final md = MarkdownService();
        for (final template in deckTemplates) {
          for (final language in contentLanguages) {
            final deck = deckOf(template.id, language: language);
            final parsed = md.parseDeck(md.generateDeck(deck));
            expect(parsed, isNotNull, reason: template.id);
            expect(
              parsed!.slides.map((s) => s.type).toList(),
              deck.slides.map((s) => s.type).toList(),
              reason: '${template.id}.$language',
            );
          }
        }
      },
    );
  });
}
