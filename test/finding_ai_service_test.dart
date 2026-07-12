import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/finding_ai_service.dart';

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
  group('buildFindingContext', () {
    test('includes only the non-empty facts', () {
      final ctx = buildFindingContext(
        const FindingAiContext(
          heading: 'F-01 · SQLi',
          scopeObject: 'https://app/login',
          cwe: 'CWE-89 — SQL Injection',
        ),
      );
      expect(ctx, contains('Finding: F-01 · SQLi'));
      expect(ctx, contains('CWE: CWE-89 — SQL Injection'));
      expect(ctx, isNot(contains('Recommendation')));
    });
  });

  group('findingInstruction', () {
    test('names the language and forbids invented identifiers', () {
      final i = findingInstruction(FindingAiField.impact, 'Dutch');
      expect(i, contains('Dutch'));
      expect(i.toLowerCase(), contains('do not invent'));
    });
  });

  group('stripFabricatedIds', () {
    test('removes identifiers absent from the context', () {
      final out = stripFabricatedIds(
        'Related to CVE-2024-9999 and CWE-89.',
        'CWE: CWE-89',
      );
      expect(out, contains('CWE-89'));
      expect(out, isNot(contains('CVE-2024-9999')));
    });

    test('keeps identifiers present in the context (case-insensitive)', () {
      final out = stripFabricatedIds('See cwe-89.', 'CWE-89');
      expect(out, contains('cwe-89'));
    });

    test('strips a fabricated CVSS vector', () {
      final out = stripFabricatedIds(
        'Score CVSS:4.0/AV:N/AC:L here.',
        'no vector in the facts',
      );
      expect(out, isNot(contains('CVSS:4.0')));
    });
  });

  group('cleanFindingDraft', () {
    test('unwraps surrounding quotes and collapses spaces', () {
      expect(cleanFindingDraft('"A   short   draft"'), 'A short draft');
    });
  });

  group('FindingAiService.suggest', () {
    test('grounds on the facts and returns the id-filtered draft', () async {
      final fake = _FakeTransport()
        ..result = const AiHttpResult(
          200,
          '{"choices":[{"message":{"content":'
          '"Injection flaw tied to CVE-2030-1 and CWE-89."}}]}',
        );
      final client = AiClientService(
        settings: _localSettings,
        hasOutboundConsent: false,
        transport: fake,
        isWeb: false,
      );
      final draft = await FindingAiService(client).suggest(
        field: FindingAiField.description,
        context: const FindingAiContext(heading: 'F', cwe: 'CWE-89'),
        languageName: 'English',
      );
      // CVE-2030-1 wasn't in the facts → stripped; CWE-89 was → kept.
      expect(draft, contains('CWE-89'));
      expect(draft, isNot(contains('CVE-2030-1')));
      // The finding facts reached the model.
      expect(fake.lastBody, contains('CWE-89'));
    });
  });
}
