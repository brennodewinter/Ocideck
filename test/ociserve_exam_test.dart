import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_exam.dart';

Map<String, Object?> _itemJson({Map<String, Object?>? content}) => {
  'attempt_id': 'attempt-1',
  'attempt_item_id': 'item-1',
  'position': 0,
  'content':
      content ??
      {
        'question': 'Wat is twee plus twee?',
        'options': [
          {'id': 'a', 'text': 'Vier'},
          {'id': 'b', 'text': 'Vijf'},
        ],
      },
  'option_order': ['b', 'a'],
  'deadline_at': '2026-09-12T12:00:00Z',
  'revision': 3,
  'challenge': 'AAAAAAAAAAAAAAAAAAAAAA',
  'challenge_expires_at': '2026-09-12T11:05:00Z',
};

void main() {
  test('current item follows only the server-supplied option order', () {
    final item = OciServeCurrentExamItem.fromJson(_itemJson());

    expect(item.options.map((option) => option.id), ['b', 'a']);
    expect(item.answerData('b'), {'selected_option_id': 'b'});
    expect(item.revision, 3);
  });

  for (final forbidden in [
    'correct_option_id',
    'answer_model',
    'score',
    'randomization_context',
  ]) {
    test('refuses participant content containing $forbidden', () {
      final content = Map<String, Object?>.from(_itemJson()['content']! as Map)
        ..['nested'] = {forbidden: 'leak'};

      expect(
        () => OciServeCurrentExamItem.fromJson(_itemJson(content: content)),
        throwsFormatException,
      );
    });
  }

  test(
    'refuses future item fields instead of silently widening disclosure',
    () {
      final json = _itemJson()..['next_item'] = {'question': 'te vroeg'};

      expect(
        () => OciServeCurrentExamItem.fromJson(json),
        throwsFormatException,
      );
    },
  );

  test('refuses a malformed or padded challenge', () {
    final json = _itemJson()..['challenge'] = 'AAAAAAAAAAAAAAAAAAAAAA==';

    expect(() => OciServeCurrentExamItem.fromJson(json), throwsFormatException);
  });

  test('refuses a score added to an attempt response', () {
    final json = <String, Object?>{
      'id': 'attempt-1',
      'participant_id': 'participant-1',
      'blueprint_version_id': 'blueprint-1',
      'status': 'submitted',
      'started_at': '2026-09-12T11:00:00Z',
      'deadline_at': null,
      'submitted_at': '2026-09-12T11:30:00Z',
      'scored_at': null,
      'released_at': null,
      'score': 10,
    };

    expect(() => OciServeExamAttempt.fromJson(json), throwsFormatException);
  });
}
