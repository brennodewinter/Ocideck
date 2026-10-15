import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/models/document_dossier.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/document_dossier_store.dart';
import 'package:ocideck/services/dossier_ai_suggestions.dart';

class _Transport implements AiHttpTransport {
  String? body;
  String answer = '{}';

  @override
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    this.body = body;
    return AiHttpResult(
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': answer},
          },
        ],
      }),
    );
  }
}

const _settings = AiSettings(
  enabled: true,
  mode: AiBackendMode.local,
  baseUrl: 'http://127.0.0.1:11434/v1',
  model: 'test',
);

void main() {
  test('parses JSON but rejects unsupported date and invented author', () {
    final suggestion = parseDossierAiSuggestion(
      '```json\n{"title":"Rapport","description":"Kort.",'
          '"documentDate":"2026-10-15","author":"Onbekende auteur"}\n```',
      'Rapport van 2026-10-14 door Ada.',
    );
    expect(suggestion.title, 'Rapport');
    expect(suggestion.description, 'Kort.');
    expect(suggestion.documentDate, isEmpty);
    expect(suggestion.author, isEmpty);
  });

  test('returns empty draft for malformed model output', () {
    expect(parseDossierAiSuggestion('not JSON', 'source').isEmpty, isTrue);
  });

  test('disabled AI cannot read or send the document', () async {
    final directory = await Directory.systemTemp.createTemp('dossier-ai-');
    addTearDown(() => directory.delete(recursive: true));
    final transport = _Transport();
    final client = AiClientService(
      settings: const AiSettings(),
      hasOutboundConsent: false,
      transport: transport,
      isWeb: false,
    );
    final store = DocumentDossierStore(File('${directory.path}/dossier.json'));
    final entry = DossierEntry(
      id: 'one',
      title: 'Document',
      relativePath: 'missing.md',
      sourcePath: '${directory.path}/missing.md',
      sha256: '0',
    );
    await expectLater(
      DossierAiSuggestionsService(
        client,
        store,
      ).suggest(entry, languageName: 'Dutch'),
      throwsA(isA<AiGateException>()),
    );
    expect(transport.body, isNull);
  });

  test('projects private text and returns only a reviewable draft', () async {
    final directory = await Directory.systemTemp.createTemp('dossier-ai-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.md');
    await source.writeAsString(
      '# Onderzoek\n\nOpsteller: Ada. Datum: 2026-10-15. '
      'Vertrouwelijk: [[geheim nummer]].',
    );
    final transport = _Transport()
      ..answer = jsonEncode({
        'title': 'Onderzoek',
        'description': 'Kort onderzoek.',
        'documentDate': '2026-10-15',
        'author': 'Ada',
      });
    final client = AiClientService(
      settings: _settings,
      hasOutboundConsent: false,
      transport: transport,
      isWeb: false,
    );
    final store = DocumentDossierStore(File('${directory.path}/dossier.json'));
    final entry = DossierEntry(
      id: 'one',
      title: 'Document',
      relativePath: 'source.md',
      sourcePath: await source.resolveSymbolicLinks(),
      sha256: '0',
    );
    final draft = await DossierAiSuggestionsService(
      client,
      store,
    ).suggest(entry, languageName: 'Dutch');
    expect(draft?.documentDate, '2026-10-15');
    expect(draft?.author, 'Ada');
    expect(transport.body, isNot(contains('geheim nummer')));
    expect(transport.body, contains('████████'));
    expect(await store.manifestFile.exists(), isFalse);
    expect(await source.readAsString(), contains('geheim nummer'));
  });

  test('oversize document is never sent', () async {
    final directory = await Directory.systemTemp.createTemp('dossier-ai-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/huge.md');
    await source.writeAsString('x' * (kDossierAiMaxSourceBytes + 1));
    final transport = _Transport();
    final client = AiClientService(
      settings: _settings,
      hasOutboundConsent: false,
      transport: transport,
      isWeb: false,
    );
    final store = DocumentDossierStore(File('${directory.path}/dossier.json'));
    final entry = DossierEntry(
      id: 'one',
      title: 'Document',
      relativePath: 'huge.md',
      sourcePath: await source.resolveSymbolicLinks(),
      sha256: '0',
    );
    await expectLater(
      DossierAiSuggestionsService(
        client,
        store,
      ).suggest(entry, languageName: 'Dutch'),
      throwsA(isA<FileSystemException>()),
    );
    expect(transport.body, isNull);
  });
}
