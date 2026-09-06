import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/elearning_assessment.dart';
import 'package:ocideck/models/question.dart';

void main() {
  group('ElearningAssessment', () {
    test('round-trips through JSON with defaults', () {
      const a = ElearningAssessment(title: 'Toets');
      final json = a.toJson();
      expect(json['title'], 'Toets');
      expect(json['maxScore'], 100);
      expect(json['passThreshold'], 60);
      expect(json['navigation'], 'linear');
      final back = ElearningAssessment.fromJson(json);
      expect(back.title, 'Toets');
      expect(back.maxScore, 100);
      expect(back.passThreshold, 60);
      expect(back.navigation, AssessmentNavigation.linear);
    });

    test('round-trips sections with random selection', () {
      final a = ElearningAssessment(
        title: 'Eindtoets',
        maxScore: 50,
        passThreshold: 70,
        timeLimitSeconds: 3600,
        navigation: AssessmentNavigation.free,
        completionRule: AssessmentCompletion.allCorrect,
        sections: [
          AssessmentSection(
            title: 'Deel A',
            questionRefs: const ['slide:3', 'slide:5'],
            selection: AssessmentSelection.random,
            poolSize: 4,
            drawCount: 2,
            timeLimitSeconds: 600,
          ),
        ],
      );
      final json = a.toJson();
      final back = ElearningAssessment.fromJson(json);
      expect(back.sections, hasLength(1));
      final s = back.sections.single;
      expect(s.title, 'Deel A');
      expect(s.questionRefs, ['slide:3', 'slide:5']);
      expect(s.selection, AssessmentSelection.random);
      expect(s.poolSize, 4);
      expect(s.drawCount, 2);
      expect(s.timeLimitSeconds, 600);
    });

    test('isEmpty is true for a default assessment', () {
      const a = ElearningAssessment();
      expect(a.isEmpty, isTrue);
    });

    test('isEmpty is false with a title or sections', () {
      const a = ElearningAssessment(title: 'X');
      expect(a.isEmpty, isFalse);
    });
  });

  group('ElearningSidecar', () {
    test('round-trips through encode/parse', () {
      final sc = ElearningSidecar(
        assessment: ElearningAssessment(
          title: 'Netwerken',
          sections: [
            AssessmentSection(title: 'Basis', questionRefs: const ['slide:1']),
          ],
        ),
      );
      final encoded = sc.encode();
      final back = ElearningSidecar.parse(encoded);
      expect(back, isNotNull);
      expect(back!.version, kElearningSidecarVersion);
      expect(back.assessment?.title, 'Netwerken');
      expect(back.assessment?.sections, hasLength(1));
    });

    test('parse returns null on invalid JSON', () {
      expect(ElearningSidecar.parse('not json'), isNull);
    });

    test('parse returns null on non-map', () {
      expect(ElearningSidecar.parse('[1,2,3]'), isNull);
    });

    // De doc-comment beloofde dit contract al; gebouwd was het niet. Half
    // inlezen is hier het gevaarlijke geval: wat deze build niet begrijpt,
    // verdwijnt bij de eerstvolgende opslag.
    test('parse weigert een sidecar van een nieuwere build', () {
      final raw = '{"version": ${kElearningSidecarVersion + 1}}';
      expect(
        ElearningSidecar.parse(raw),
        isNull,
        reason: 'een hogere versie draagt aantoonbaar iets dat deze build niet '
            'kent — die mag niet half ingelezen en teruggeschreven worden',
      );
    });

    test('parse leest een sidecar zonder versiesleutel als de oudste', () {
      expect(ElearningSidecar.parse('{}'), isNotNull);
    });

    test('onbekende sleutels overleven een lees-schrijfronde', () {
      // §7 rekent structure/source/scoring tot versie 1; deze build leest ze
      // niet. Dezelfde versie, dus de versiepoort grijpt niet in — zonder
      // bewaren zou het bestand armer terugkomen dan het inging.
      final back = ElearningSidecar.parse(
        '{"version":$kElearningSidecarVersion,"structure":{"modules":[1]},'
        '"source":"scorm"}',
      );
      expect(back, isNotNull);
      final again = jsonDecode(back!.encode()) as Map<String, dynamic>;
      expect(again['source'], 'scorm');
      expect(again['structure'], {'modules': [1]});
    });

    test('accessibility round-trips extensions and warnings', () {
      final sc = ElearningSidecar(
        accessibility: ElearningAccessibility(
          extensions: {
            'afa': {'v': 1},
          },
          warnings: const ['Niet-ondersteunde audio-alt'],
        ),
      );
      final encoded = sc.encode();
      final back = ElearningSidecar.parse(encoded);
      expect(back!.accessibility, isNotNull);
      expect(back.accessibility!.extensions['afa'], {'v': 1});
      expect(back.accessibility!.warnings, ['Niet-ondersteunde audio-alt']);
    });

    test('accessibility is omitted when empty', () {
      const sc = ElearningSidecar(accessibility: ElearningAccessibility());
      expect(sc.encode(), contains('version'));
      expect(sc.encode(), isNot(contains('accessibility')));
    });
  });

  group('QuestionFeedback copyWith', () {
    test('copies individual fields', () {
      const f = QuestionFeedback(correct: 'Goed!');
      final updated = f.copyWith(wrong: 'Fout!');
      expect(updated.correct, 'Goed!');
      expect(updated.wrong, 'Fout!');
      expect(updated.partial, isEmpty);
    });
  });

  group('QuestionMetadata copyWith', () {
    test('copies individual fields', () {
      const m = QuestionMetadata(title: 'Vraag 1');
      final updated = m.copyWith(subject: 'Netwerken', difficulty: 'hard');
      expect(updated.title, 'Vraag 1');
      expect(updated.subject, 'Netwerken');
      expect(updated.difficulty, 'hard');
    });
  });
}
