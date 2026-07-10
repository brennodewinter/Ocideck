import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_request.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake transport that never touches the network: it records the last request
/// and returns a canned response. Used to prove the request builder produces
/// the right `/v1/chat/completions` payload and that a refused request never
/// reaches the transport at all.
class _FakeTransport implements AiHttpTransport {
  int calls = 0;
  String? lastMethod;
  Uri? lastUrl;
  AiResolveStrategy? lastStrategy;
  Map<String, String>? lastHeaders;
  String? lastBody;
  AiHttpResult result = const AiHttpResult(200, _okChat);

  static const _okChat =
      '{"choices":[{"message":{"role":"assistant","content":"draft text"}}]}';

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
    lastMethod = method;
    lastUrl = url;
    lastStrategy = strategy;
    lastHeaders = headers;
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
  group('AiSettings config round-trip', () {
    test('defaults are off and none', () {
      const s = AiSettings();
      expect(s.enabled, isFalse);
      expect(s.mode, AiBackendMode.none);
      expect(s.baseUrl, isEmpty);
      expect(s.isConfigured, isFalse);
    });

    test('toJson/fromJson round-trips every field', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.selfHosted,
        baseUrl: 'https://ai.lan:8443/v1',
        model: 'llama3.2-vision:11b',
        trustedInternal: true,
        cloudConfirmed: true,
      );
      final back = AiSettings.fromJson(s.toJson());
      expect(back, s);
      expect(back.mode, AiBackendMode.selfHosted);
      expect(back.trustedInternal, isTrue);
      expect(back.cloudConfirmed, isTrue);
    });

    test('fromJson tolerates an unknown mode and missing fields', () {
      final back = AiSettings.fromJson(const {'mode': 'quantum'});
      expect(back.mode, AiBackendMode.none);
      expect(back.enabled, isFalse);
      expect(back.baseUrl, isEmpty);
    });

    test('copyWith updates only the given field', () {
      const s = AiSettings(enabled: true, mode: AiBackendMode.local);
      expect(s.copyWith(model: 'moondream').model, 'moondream');
      expect(s.copyWith(model: 'moondream').mode, AiBackendMode.local);
    });
  });

  group('AiSettings prefs round-trip', () {
    test('persists to and loads from the single prefs domain', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      const settings = AiSettings(
        enabled: true,
        mode: AiBackendMode.cloud,
        baseUrl: 'https://api.example.com/v1',
        model: 'gpt-4o-mini',
        cloudConfirmed: true,
      );
      await writer.setAiSettings(settings);
      expect(writer.state.aiSettings, settings);

      // A fresh notifier reads the same mock store.
      final reader = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reader.state.aiSettings, settings);
    });

    test('defaults to a disabled AiSettings when nothing stored', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.aiSettings.enabled, isFalse);
      expect(n.state.aiSettings.mode, AiBackendMode.none);
    });
  });

  group('AiChatRequest payload builder', () {
    test('serialises a text-only chat request', () {
      const request = AiChatRequest(
        model: 'gemma3:4b',
        messages: [
          AiMessage(AiRole.system, [AiTextPart('rules')]),
          AiMessage(AiRole.user, [AiTextPart('hello')]),
        ],
        maxTokens: 128,
      );
      final json = request.toJson();
      expect(json['model'], 'gemma3:4b');
      expect(json['stream'], isFalse);
      expect(json['temperature'], 0.2);
      expect(json['max_tokens'], 128);
      final messages = json['messages'] as List;
      expect(messages, hasLength(2));
      expect((messages.first as Map)['role'], 'system');
      // A single text part serialises as a bare string.
      expect((messages.first as Map)['content'], 'rules');
    });

    test('serialises a multimodal message with an image data URI', () {
      const msg = AiMessage(AiRole.user, [
        AiTextPart('describe'),
        AiImagePart('data:image/jpeg;base64,QUJD'),
      ]);
      final content = msg.toJson()['content'] as List;
      expect(content, hasLength(2));
      expect((content[0] as Map)['type'], 'text');
      expect((content[1] as Map)['type'], 'image_url');
      expect(
        ((content[1] as Map)['image_url'] as Map)['url'],
        'data:image/jpeg;base64,QUJD',
      );
    });

    test('client posts to /v1/chat/completions with the built body', () async {
      final fake = _FakeTransport();
      final client = AiClientService(
        settings: _localSettings,
        hasOutboundConsent: false,
        transport: fake,
        isWeb: false,
      );
      final response = await client.chat(
        const AiChatRequest(
          model: 'gemma3:4b',
          messages: [
            AiMessage(AiRole.user, [AiTextPart('hi')]),
          ],
        ),
      );
      expect(response.text, 'draft text');
      expect(fake.lastMethod, 'POST');
      expect(
        fake.lastUrl,
        Uri.parse('http://127.0.0.1:11434/v1/chat/completions'),
      );
      expect(fake.lastStrategy, AiResolveStrategy.loopbackDirect);
      final body = jsonDecode(fake.lastBody!) as Map<String, Object?>;
      expect(body['model'], 'gemma3:4b');
      expect(body['stream'], isFalse);
      expect(fake.lastHeaders!['content-type'], 'application/json');
      // No API key configured → no Authorization header.
      expect(fake.lastHeaders!.containsKey('authorization'), isFalse);
    });

    test('suggest() frames a grounded system+user pair', () async {
      final fake = _FakeTransport();
      final client = AiClientService(
        settings: _localSettings,
        hasOutboundConsent: false,
        transport: fake,
        isWeb: false,
      );
      final text = await client.suggest(
        context: 'The finding is an outdated TLS cipher.',
        instruction: 'Draft a one-line impact statement.',
      );
      expect(text, 'draft text');
      final body = jsonDecode(fake.lastBody!) as Map<String, Object?>;
      final messages = body['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect((messages.last as Map)['role'], 'user');
      expect(
        (messages.last as Map)['content'].toString(),
        contains('outdated TLS cipher'),
      );
    });

    test('AiChatResponse tolerates an unexpected shape', () {
      expect(AiChatResponse.fromJson(const {}).text, isEmpty);
      expect(AiChatResponse.fromJson(const {'choices': []}).text, isEmpty);
    });
  });

  group('AiSecurityGate — three-tier egress gating', () {
    AiGateDecision gate(
      AiSettings s, {
      bool consent = false,
      bool web = false,
    }) => AiSecurityGate.evaluate(
      s,
      hasOutboundConsent: consent,
      cloudConfirmed: s.cloudConfirmed,
      isWeb: web,
    );

    test('nothing fires when the toggle is off', () {
      const s = AiSettings(
        mode: AiBackendMode.local,
        baseUrl: 'http://127.0.0.1/v1',
      );
      final d = gate(s);
      expect(d, isA<AiGateDeny>());
      expect((d as AiGateDeny).reason, AiGateDenial.disabled);
    });

    test('nothing fires when mode is none', () {
      const s = AiSettings(enabled: true);
      expect((gate(s) as AiGateDeny).reason, AiGateDenial.modeNone);
    });

    test('empty/invalid base URL is refused', () {
      const s = AiSettings(enabled: true, mode: AiBackendMode.local);
      expect((gate(s) as AiGateDeny).reason, AiGateDenial.notConfigured);
      const bad = AiSettings(
        enabled: true,
        mode: AiBackendMode.local,
        baseUrl: 'ftp://127.0.0.1/v1',
      );
      expect((gate(bad) as AiGateDeny).reason, AiGateDenial.notConfigured);
    });

    test('local: loopback endpoint is allowed via loopbackDirect', () {
      final d = gate(_localSettings);
      expect(d, isA<AiGateAllow>());
      expect((d as AiGateAllow).strategy, AiResolveStrategy.loopbackDirect);
    });

    test('local: localhost is treated as loopback', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.local,
        baseUrl: 'http://localhost:11434/v1',
      );
      expect(
        (gate(s) as AiGateAllow).strategy,
        AiResolveStrategy.loopbackDirect,
      );
    });

    test('local: a non-loopback host is refused (no egress via local)', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.local,
        baseUrl: 'http://192.168.1.50:11434/v1',
      );
      expect((gate(s) as AiGateDeny).reason, AiGateDenial.loopbackRequired);
      const pub = AiSettings(
        enabled: true,
        mode: AiBackendMode.local,
        baseUrl: 'https://api.example.com/v1',
      );
      expect((gate(pub) as AiGateDeny).reason, AiGateDenial.loopbackRequired);
    });

    test('self-hosted: refused without the trusted opt-in', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.selfHosted,
        baseUrl: 'http://192.168.1.50:11434/v1',
      );
      expect((gate(s) as AiGateDeny).reason, AiGateDenial.privateNotTrusted);
    });

    test('self-hosted: allowed via trustedPrivate once opted in', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.selfHosted,
        baseUrl: 'http://192.168.1.50:11434/v1',
        trustedInternal: true,
      );
      expect(
        (gate(s) as AiGateAllow).strategy,
        AiResolveStrategy.trustedPrivate,
      );
    });

    test('cloud: needs the outbound consent first', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.cloud,
        baseUrl: 'https://api.example.com/v1',
        cloudConfirmed: true,
      );
      expect(
        (gate(s, consent: false) as AiGateDeny).reason,
        AiGateDenial.cloudNeedsConsent,
      );
    });

    test('cloud: needs the distinct destination confirmation', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.cloud,
        baseUrl: 'https://api.example.com/v1',
      );
      expect(
        (gate(s, consent: true) as AiGateDeny).reason,
        AiGateDenial.cloudNotConfirmed,
      );
    });

    test('cloud: allowed via publicGuarded with consent + confirmation', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.cloud,
        baseUrl: 'https://api.example.com/v1',
        cloudConfirmed: true,
      );
      final d = gate(s, consent: true);
      expect((d as AiGateAllow).strategy, AiResolveStrategy.publicGuarded);
    });

    test('cloud: blocked on web regardless of consent', () {
      const s = AiSettings(
        enabled: true,
        mode: AiBackendMode.cloud,
        baseUrl: 'https://api.example.com/v1',
        cloudConfirmed: true,
      );
      expect(
        (gate(s, consent: true, web: true) as AiGateDeny).reason,
        AiGateDenial.cloudBlockedOnWeb,
      );
    });
  });

  group('AiClientService refuses to touch the network when gated', () {
    test(
      'disabled toggle: chat throws and transport is never called',
      () async {
        final fake = _FakeTransport();
        final client = AiClientService(
          settings: const AiSettings(),
          hasOutboundConsent: true,
          transport: fake,
          isWeb: false,
        );
        await expectLater(
          client.chat(
            const AiChatRequest(
              model: 'x',
              messages: [
                AiMessage(AiRole.user, [AiTextPart('hi')]),
              ],
            ),
          ),
          throwsA(isA<AiGateException>()),
        );
        expect(fake.calls, 0);
      },
    );

    test('cloud without consent: testConnection throws, no network', () async {
      final fake = _FakeTransport();
      final client = AiClientService(
        settings: const AiSettings(
          enabled: true,
          mode: AiBackendMode.cloud,
          baseUrl: 'https://api.example.com/v1',
          cloudConfirmed: true,
        ),
        hasOutboundConsent: false,
        transport: fake,
        isWeb: false,
      );
      await expectLater(
        client.testConnection(),
        throwsA(isA<AiGateException>()),
      );
      expect(fake.calls, 0);
    });

    test('an API key becomes a Bearer Authorization header', () async {
      final fake = _FakeTransport();
      final client = AiClientService(
        settings: _localSettings,
        hasOutboundConsent: false,
        apiKey: 'sk-secret',
        transport: fake,
        isWeb: false,
      );
      await client.testConnection();
      expect(fake.lastMethod, 'GET');
      expect(fake.lastUrl, Uri.parse('http://127.0.0.1:11434/v1/models'));
      expect(fake.lastHeaders!['authorization'], 'Bearer sk-secret');
    });
  });
}
