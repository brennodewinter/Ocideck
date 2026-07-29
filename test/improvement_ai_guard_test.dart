import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/improvement_ai_guard.dart';
import 'package:ocideck/services/improvement_ai_service.dart';

class _FakeTransport implements AiHttpTransport {
  String? lastBody;
  AiHttpResult result = const AiHttpResult(
    200,
    '{"choices":[{"message":{"content":"draft"}}]}',
  );

  @override
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    lastBody = body;
    return result;
  }
}

const _localSettings = AiSettings(
  enabled: true,
  mode: AiBackendMode.local,
  baseUrl: 'http://127.0.0.1:11434/v1',
  model: 'gemma3:4b',
);

void main() {
  group('stripFabricatedImprovementIds', () {
    test('removes ids absent from the context', () {
      final out = stripFabricatedImprovementIds(
        'See **X-03** and **Y-01** here.',
        'Field: **Y-01**',
      );
      expect(out, contains('Y-01'));
      expect(out, isNot(contains('X-03')));
    });

    test('removes bare ids absent from the context', () {
      final out = stripFabricatedImprovementIds(
        'Linked to X-99 and Y-02.',
        'Other: Y-02',
      );
      expect(out, contains('Y-02'));
      expect(out, isNot(contains('X-99')));
    });
  });

  group('stripStatisticClaims', () {
    test('strips Cpk and percentage claims', () {
      final out = stripStatisticClaims(
        'Process runs at Cpk=1.45 with 12,3% scrap.',
      );
      expect(out.toLowerCase(), isNot(contains('cpk')));
      expect(out, isNot(contains('%')));
    });

    test('strips RPN and measurement units', () {
      final out = stripStatisticClaims('RPN 180 and gap 2,5 mm noted.');
      expect(out.toUpperCase(), isNot(contains('RPN')));
      expect(out, isNot(contains('mm')));
    });
  });

  group('containsCauseListPattern', () {
    test('detects multi-line bullet cause lists', () {
      expect(
        containsCauseListPattern(
          '- Man: training\n- Machine: calibration\n- Method: SOP',
        ),
        isTrue,
      );
    });

    test('allows a single wording line', () {
      expect(
        containsCauseListPattern('Late intake due to unclear handover.'),
        isFalse,
      );
    });
  });

  group('containsConclusionPattern', () {
    test('detects explicit conclusions', () {
      expect(
        containsConclusionPattern('Therefore the root cause is training.'),
        isTrue,
      );
    });
  });

  group('filterImprovementDraft', () {
    test('rejects fishbone cause lists entirely', () {
      expect(
        filterImprovementDraft(
          '- People: skill\n- Process: handover',
          '',
          treeOrFishbone: true,
        ),
        isEmpty,
      );
    });

    test('strips fabricated ids and stats on canvas wording', () {
      final out = filterImprovementDraft(
        'Target **X-01** with Cpk 1,2 and 5% rework.',
        'Field: **X-01**',
        treeOrFishbone: false,
      );
      expect(out, contains('X-01'));
      expect(out.toLowerCase(), isNot(contains('cpk')));
      expect(out, isNot(contains('%')));
    });
  });

  group('ImprovementAiService.suggest', () {
    test('grounds on facts and applies guardrails', () async {
      final fake = _FakeTransport()
        ..result = const AiHttpResult(
          200,
          '{"choices":[{"message":{"content":'
          '"Possible causes: Man and Machine. Cpk 2,0 and **X-99**."}}]}',
        );
      final client = AiClientService(
        settings: _localSettings,
        hasOutboundConsent: false,
        transport: fake,
        isWeb: false,
      );
      final draft = await ImprovementAiService(client).suggest(
        field: ImprovementAiField.treeBullet,
        context: const ImprovementAiContext(
          slideTitle: 'Ishikawa',
          templateId: 'ishikawa',
          fieldLabel: 'Bullet 1',
        ),
        languageName: 'English',
      );
      expect(draft, isEmpty);
      expect(fake.lastBody, contains('Ishikawa'));
    });

    test('returns filtered canvas wording', () async {
      final fake = _FakeTransport()
        ..result = const AiHttpResult(
          200,
          '{"choices":[{"message":{"content":'
          '"Orders wait because intake is unclear (Y-01). RPN 90."}}]}',
        );
      final client = AiClientService(
        settings: _localSettings,
        hasOutboundConsent: false,
        transport: fake,
        isWeb: false,
      );
      final draft = await ImprovementAiService(client).suggest(
        field: ImprovementAiField.canvasRegion,
        context: const ImprovementAiContext(
          slideTitle: 'Charter',
          fieldLabel: 'Problem',
          existingText: '**Y-01**',
        ),
        languageName: 'English',
      );
      expect(draft, contains('Y-01'));
      expect(draft.toUpperCase(), isNot(contains('RPN')));
    });
  });

  group('improvementInstruction', () {
    test('forbids invented ids and tree causes', () {
      final i = improvementInstruction(
        ImprovementAiField.treeBullet,
        'Dutch',
        treeOrFishbone: true,
      );
      expect(i, contains('Dutch'));
      expect(i.toLowerCase(), contains('do not'));
      expect(i.toLowerCase(), contains('causes'));
    });
  });
}
