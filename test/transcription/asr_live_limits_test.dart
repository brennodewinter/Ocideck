import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/asr_live_limits.dart';
import 'package:ocideck/services/transcription/asr_live_protocol.dart';

void main() {
  test('UTF-8-grens accepteert exact de grens en telt multibyte tekst', () {
    expect(checkedLiveTextBytes('éé', 4), 4);
    expect(checkedLiveTextBytes('abc', 4), 3);
    expect(
      () => checkedLiveTextBytes('éé', 3),
      throwsA(isA<LiveResponseLimitExceeded>()),
    );
    expect(
      () => checkedLiveFrameBytes(
        Uint8List(5),
        const LiveResponseLimits(messageBytes: 4),
      ),
      throwsA(isA<LiveResponseLimitExceeded>()),
    );
  });

  test('veel kleine berichten hebben een eigen sessie- en aantalgrens', () {
    final bytes = LiveResponseBudget(const LiveResponseLimits(sessionBytes: 4));
    bytes.admit('ab');
    bytes.admit('cd');
    expect(() => bytes.admit('e'), throwsA(isA<LiveResponseLimitExceeded>()));
    final count = LiveResponseBudget(const LiveResponseLimits(messages: 2));
    count.admit('');
    count.admit('');
    expect(() => count.admit(''), throwsA(isA<LiveResponseLimitExceeded>()));
  });

  test('resultaatbytes en segmentaantal worden vóór toevoegen getoetst', () {
    final bytes = LiveResponseBudget(const LiveResponseLimits(resultBytes: 4));
    bytes.retainResult('é');
    bytes.retainResult('é');
    expect(
      () => bytes.retainResult('x'),
      throwsA(isA<LiveResponseLimitExceeded>()),
    );
    final count = LiveResponseBudget(const LiveResponseLimits(segments: 2));
    count.retainResult('a');
    count.retainResult('b');
    expect(
      () => count.retainResult('c'),
      throwsA(isA<LiveResponseLimitExceeded>()),
    );
  });

  test(
    'pauzerende afnemer houdt slechts een begrensde wachtrij vast',
    () async {
      var aborts = 0;
      final input = BoundedLiveInput(
        limits: const LiveResponseLimits(queuedBytes: 4),
        onLimit: () => aborts++,
      );
      final received = <Object>[];
      final errors = <Object>[];
      final done = Completer<void>();
      final sub = input.stream.listen(
        received.add,
        onError: errors.add,
        onDone: done.complete,
      )..pause();
      input.add('abc');
      input.add('de');
      input.add('ignored');
      expect(aborts, 1);
      sub.resume();
      await done.future;
      expect(received, ['abc']);
      expect(errors.single, isA<LiveResponseLimitExceeded>());
    },
  );

  test(
    'ook lege berichten vóór een luisteraar hebben een queuegrens',
    () async {
      var aborts = 0;
      final input = BoundedLiveInput(
        limits: const LiveResponseLimits(queuedMessages: 2),
        onLimit: () => aborts++,
      );
      input.add('');
      input.add('');
      input.add('');
      expect(aborts, 1);
      await expectLater(
        input.stream,
        emitsInOrder([
          '',
          '',
          emitsError(isA<LiveResponseLimitExceeded>()),
          emitsDone,
        ]),
      );
    },
  );

  test('parser begrenst raw JSON, gedecodeerde tekst en woordlijsten', () {
    expect(
      () => parseLiveMessage(
        'x' * 9,
        limits: const LiveResponseLimits(messageBytes: 8),
      ),
      throwsA(isA<LiveResponseLimitExceeded>()),
    );
    expect(
      () => parseLiveMessage(
        jsonEncode({'partial': 'éé'}),
        limits: const LiveResponseLimits(textBytes: 3),
      ),
      throwsA(isA<LiveResponseLimitExceeded>()),
    );
    expect(
      () => parseLiveMessage(
        '{"result":[{},{},{}]}',
        limits: const LiveResponseLimits(words: 2),
      ),
      throwsA(isA<LiveResponseLimitExceeded>()),
    );
    final valid = parseLiveMessage(
      '{"text":"éé"}',
      limits: const LiveResponseLimits(textBytes: 4),
    );
    expect((valid as LiveResult).text, 'éé');
  });

  test('ongeldige numerieke woordmetadata crasht de parser niet', () {
    final result =
        parseLiveMessage(
              '{"result":[{"word":"oneindig","start":1e999,"end":1e999},'
              '{"word":"te groot","start":0,"end":1e20},'
              '{"word":"achteruit","start":2,"end":1},'
              '{"word":"goed","start":0.125,"end":0.25}],"text":"goed"}',
            )
            as LiveResult;
    expect(result.words.single.word, 'goed');
    expect(result.words.single.start, const Duration(milliseconds: 125));
  });
}
