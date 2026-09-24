import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/ai_translate_service.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Nep-transport dat elk chat-verzoek beantwoordt door de gemarkeerde
/// segmenten in de user-message terug te leveren als `T<n>` — zo testen we de
/// hele ketting zonder netwerk en zonder model.
class _FakeTransport implements AiHttpTransport {
  _FakeTransport({this.failOnCall});

  /// Welke aanroep (1-based) een netwerkfout moet geven — om te toetsen dat
  /// een falende dia zijn origineel behoudt.
  final int? failOnCall;
  int calls = 0;

  @override
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    if (calls == failOnCall) {
      throw AiRequestException('network');
    }
    final request = jsonDecode(body!) as Map<String, Object?>;
    final messages = request['messages'] as List;
    final user = messages.last as Map<String, Object?>;
    final packed = user['content'] as String;
    final marks = RegExp(r'⟦\s*(\d+)\s*⟧').allMatches(packed);
    final response = [
      for (final m in marks) '⟦${m.group(1)}⟧ T${m.group(1)}',
    ].join('\n');
    return AiHttpResult(
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': response},
          },
        ],
      }),
    );
  }
}

AiClientService _client(_FakeTransport transport) => AiClientService(
  settings: const AiSettings(
    enabled: true,
    mode: AiBackendMode.local,
    baseUrl: 'http://127.0.0.1:11434/v1',
    model: 'testmodel',
  ),
  hasOutboundConsent: false,
  transport: transport,
);

void main() {
  group('pack/parse', () {
    test('segmenten overleven de rondgang', () {
      final packed = packTranslationUnits(['eerste', 'tweede regel']);
      expect(packed, '⟦1⟧ eerste\n⟦2⟧ tweede regel');
      expect(parseTranslationResponse(packed), {
        1: 'eerste',
        2: 'tweede regel',
      });
    });

    test('preambule en ontbrekende nummers worden genegeerd', () {
      final parsed = parseTranslationResponse(
        'Hier is de vertaling:\n⟦2⟧ twee\n⟦4⟧ vier',
      );
      expect(parsed, {2: 'twee', 4: 'vier'});
    });

    test('merktekens in de inhoud breken de segmentatie niet', () {
      final packed = packTranslationUnits(['tekst met ⟧ erin']);
      expect(parseTranslationResponse(packed).values.single, 'tekst met  erin');
    });
  });

  group('translationPlanFor', () {
    test('vlakke dia: titel, bullets en notities zijn eenheden', () {
      final slide = Slide(
        id: 's1',
        type: SlideType.bullets,
        title: 'Titel',
        bullets: ['eerste', '\tgenest', '[ ] afvinken'],
        notes: 'notitie',
      );
      final plan = translationPlanFor(slide);
      expect(plan.units.map((u) => u.text), [
        'Titel',
        'notitie',
        'eerste',
        'genest',
        'afvinken',
      ]);
      final (out, fields) = plan.apply([
        'Title',
        'note',
        'one',
        'nested',
        'todo',
      ]);
      expect(out.title, 'Title');
      expect(out.notes, 'note');
      // Inspringing en checklist-markering zijn van het formaat, niet van de
      // vertaler.
      expect(out.bullets, ['one', '\tnested', '[ ] todo']);
      expect(fields, {'title', 'notes', 'bullets'});
    });

    test('menu-blok: label en uitleg vertalen, anker en pad blijven', () {
      final slide = Slide(
        id: 'm1',
        type: SlideType.menu,
        title: 'Menu',
        bullets: [
          '[Introductie](#intro) — korte uitleg ![](mem:logo)',
          'Groep',
        ],
      );
      final plan = translationPlanFor(slide);
      // label, uitleg, groepskop = 3 eenheden
      expect(plan.units.length, 4); // + title
      final (out, _) = plan.apply([null, 'Intro', 'short intro', 'Group']);
      expect(out.bullets[0], contains('(#intro)'));
      expect(out.bullets[0], contains('mem:logo'));
      expect(out.bullets[0], contains('Intro'));
      expect(out.bullets[0], contains('short intro'));
    });

    test('tijdlijn: :: -velden blijven drie delen', () {
      final slide = Slide(
        id: 't1',
        type: SlideType.timeline,
        bullets: ['2024 :: Lancering :: eerste release'],
      );
      final plan = translationPlanFor(slide);
      final (out, _) = plan.apply(['2024', 'Launch', 'first release']);
      expect(out.bullets.single, '2024 :: Launch :: first release');
    });

    test('flow-bullet: alleen de titel vertaalt, kind/attrs blijven', () {
      final slide = Slide(
        id: 'f1',
        type: SlideType.flow,
        bullets: ['Start hier :: process :: lane=1'],
      );
      final plan = translationPlanFor(slide);
      expect(plan.units.single.text, 'Start hier');
      final (out, _) = plan.apply(['Start here']);
      expect(out.bullets.single, 'Start here :: process :: lane=1');
    });

    test('vraag-dia: gestructureerde body blijft ongemoeid', () {
      final slide = Slide(
        id: 'q1',
        type: SlideType.question,
        title: 'Vraag',
        customMarkdown: '{"kind":"mc","prompt":"Wat?"}',
      );
      final plan = translationPlanFor(slide);
      expect(plan.units.map((u) => u.field), isNot(contains('customMarkdown')));
      final (out, _) = plan.apply(['Question']);
      expect(out.customMarkdown, '{"kind":"mc","prompt":"Wat?"}');
    });
  });

  group('gantt', () {
    test('afhankelijkheden verwijzen naar de vertaalde taaknamen', () {
      final slide = Slide(
        id: 'g1',
        type: SlideType.gantt,
        tableRows: [
          ['Taak', 'Start', 'Duur', 'Voortgang', 'Afhankelijk van'],
          ['Ontwerp', '2024-01-01', '5d', 'done', ''],
          ['Bouw', '', '10d', 'active', 'Ontwerp'],
        ],
      );
      final plan = translationPlanFor(slide);
      // Koprij (5) + twee taaknamen; datum/duur/status/deps zijn geen eenheden.
      expect(plan.units.length, 7);
      final (out, _) = plan.apply([
        'Task',
        'Start',
        'Duration',
        'Progress',
        'Depends on',
        'Design',
        'Build',
      ]);
      final applied = applyGanttDependencies(plan.slide, out);
      expect(applied.tableRows[2][4], 'Design');
      expect(applied.tableRows[2][1], ''); // ongemoeid
      expect(applied.tableRows[1][3], 'done'); // status-token ongemoeid
    });
  });

  group('translateDeck', () {
    test('vertaalt dia\'s, zet taal en markeert aiAssistedFields', () async {
      final transport = _FakeTransport();
      final deck = Deck(
        title: 'Mijn deck',
        language: 'nl',
        projectPath: '/tmp/project',
        slides: [
          Slide(
            id: 's1',
            type: SlideType.bullets,
            title: 'Welkom',
            bullets: ['hallo'],
          ),
        ],
      );
      final result = await AiTranslateService(
        _client(transport),
      ).translateDeck(deck: deck, languageCode: 'en', languageName: 'English');
      expect(result, isNotNull);
      expect(result!.deck.language, 'en');
      expect(result.deck.title, 'T1');
      expect(result.deck.projectPath, '/tmp/project');
      final slide = result.deck.slides.single;
      expect(slide.title, 'T1');
      expect(slide.bullets, ['T2']);
      expect(slide.aiAssistedFields, containsAll(['title', 'bullets']));
      expect(result.failedSlides, 0);
      // Bron-deck ongemoeid.
      expect(deck.slides.single.title, 'Welkom');
    });

    test('een falende dia behoudt zijn origineel', () async {
      // Aanroep 1 = deck-meta, aanroep 3 = tweede dia → die faalt.
      final transport = _FakeTransport(failOnCall: 3);
      final deck = Deck(
        title: 'Deck',
        slides: [
          Slide(id: 'a', type: SlideType.bullets, title: 'Een'),
          Slide(id: 'b', type: SlideType.bullets, title: 'Twee'),
        ],
      );
      final result = await AiTranslateService(
        _client(transport),
      ).translateDeck(deck: deck, languageCode: 'en', languageName: 'English');
      expect(result!.failedSlides, 1);
      expect(result.deck.slides[1].title, 'Twee');
      expect(result.deck.slides[0].title, 'T1');
    });

    test('annuleren levert null en stopt meteen', () async {
      final transport = _FakeTransport();
      final deck = Deck(
        title: '',
        slides: [
          Slide(id: 'a', type: SlideType.bullets, title: 'Een'),
          Slide(id: 'b', type: SlideType.bullets, title: 'Twee'),
        ],
      );
      var calls = 0;
      final result = await AiTranslateService(_client(transport)).translateDeck(
        deck: deck,
        languageCode: 'en',
        languageName: 'English',
        isCancelled: () => ++calls > 1, // na de meta-check meteen stoppen
      );
      expect(result, isNull);
    });

    test('round-trip: vertaalde dia overleeft serialize → parse', () async {
      final transport = _FakeTransport();
      final deck = Deck(
        title: 'D',
        slides: [
          Slide(
            id: 's1',
            type: SlideType.menu,
            title: 'Menu',
            bullets: ['[Deel een](#deel1) — uitleg'],
          ),
        ],
      );
      final result = await AiTranslateService(
        _client(transport),
      ).translateDeck(deck: deck, languageCode: 'en', languageName: 'English');
      final service = MarkdownService();
      final md = service.generateDeck(result!.deck);
      final reparsed = service.parseDeck(md)!;
      expect(reparsed.language, 'en');
      final slide = reparsed.slides.single;
      expect(slide.bullets.single, contains('(#deel1)'));
      expect(slide.aiAssistedFields, isNotEmpty);
    });
  });
}
